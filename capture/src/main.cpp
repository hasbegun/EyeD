#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <string>
#include <thread>

#include <spdlog/spdlog.h>
#include <toml++/toml.hpp>

#include "camera.h"
#include "client.h"
#include "quality_gate.h"
#include "ring_buffer.h"

using FrameBuffer = RingBuffer<Frame, 4>;

static std::atomic<bool> g_shutdown{false};

static void signal_handler(int) {
    g_shutdown.store(true, std::memory_order_relaxed);
}

// Helper: read env var with default
static std::string env_or(const char* name, const std::string& def) {
    const char* v = std::getenv(name);
    return v ? std::string(v) : def;
}

static float env_or_float(const char* name, float def) {
    const char* v = std::getenv(name);
    return v ? std::stof(v) : def;
}

struct Config {
    GatewayConfig gateway;
    CameraConfig  camera;
    QualityConfig quality;
    std::string   device_id  = "capture-01";
    std::string   log_level  = "info";
};

static Config load_config(const std::string& path) {
    Config cfg;
    try {
        auto tbl = toml::parse_file(path);

        cfg.gateway.address            = tbl["gateway"]["address"].value_or(std::string("gateway:50051"));
        cfg.gateway.reconnect_base_ms  = tbl["gateway"]["reconnect_base_ms"].value_or(500);
        cfg.gateway.reconnect_max_ms   = tbl["gateway"]["reconnect_max_ms"].value_or(30000);
        cfg.gateway.connect_timeout_ms = tbl["gateway"]["connect_timeout_ms"].value_or(5000);

        cfg.camera.source         = tbl["camera"]["source"].value_or(std::string("directory"));
        cfg.camera.image_dir      = tbl["camera"]["image_dir"].value_or(std::string("/data/Iris/CASIA1"));
        cfg.camera.device         = tbl["camera"]["device"].value_or(std::string("/dev/video0"));
        cfg.camera.width          = tbl["camera"]["width"].value_or(640);
        cfg.camera.height         = tbl["camera"]["height"].value_or(480);
        cfg.camera.frame_rate_fps = tbl["camera"]["frame_rate_fps"].value_or(30);
        cfg.camera.eye_side       = tbl["camera"]["eye_side"].value_or(std::string("left"));
        cfg.camera.is_nir         = tbl["camera"]["is_nir"].value_or(false);

        cfg.quality.threshold    = tbl["quality"]["threshold"].value_or(0.30f);
        cfg.quality.jpeg_quality = tbl["quality"]["jpeg_quality"].value_or(85);

        cfg.device_id = tbl["device"]["id"].value_or(std::string("capture-01"));
        cfg.log_level = tbl["device"]["log_level"].value_or(std::string("info"));
    } catch (const toml::parse_error& err) {
        spdlog::warn("Failed to parse config {}: {}. Using defaults.", path, err.what());
    }

    // Environment variable overrides (EYED_* prefix convention)
    cfg.gateway.address   = env_or("EYED_GATEWAY_ADDR", cfg.gateway.address);
    cfg.device_id         = env_or("EYED_DEVICE_ID", cfg.device_id);
    cfg.log_level         = env_or("EYED_LOG_LEVEL", cfg.log_level);
    cfg.camera.source     = env_or("EYED_CAMERA_SOURCE", cfg.camera.source);
    cfg.camera.device     = env_or("EYED_CAMERA_DEVICE", cfg.camera.device);
    cfg.camera.image_dir  = env_or("EYED_IMAGE_DIR", cfg.camera.image_dir);
    cfg.quality.threshold = env_or_float("EYED_QUALITY_THRESHOLD", cfg.quality.threshold);

    return cfg;
}

static void capture_thread(Camera& cam, FrameBuffer& buf) {
    uint32_t frame_id = 0;
    while (!g_shutdown.load(std::memory_order_relaxed)) {
        cv::Mat image;
        uint64_t ts;
        if (!cam.next_frame(image, ts)) {
            spdlog::error("Camera failed, exiting capture thread");
            break;
        }
        if (image.empty()) continue;

        if (!buf.try_push(Frame{std::move(image), frame_id, ts})) {
            spdlog::debug("Ring buffer full, dropping frame {}", frame_id);
        }
        ++frame_id;
    }
}

int main(int argc, char** argv) {
    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);

    // Config file path from env or default
    std::string config_path = env_or("CAPTURE_CONFIG", "/app/config/capture.toml");
    if (argc > 1) config_path = argv[1];

    auto cfg = load_config(config_path);

    // Set log level
    if (cfg.log_level == "debug")      spdlog::set_level(spdlog::level::debug);
    else if (cfg.log_level == "warn")  spdlog::set_level(spdlog::level::warn);
    else if (cfg.log_level == "error") spdlog::set_level(spdlog::level::err);
    else                               spdlog::set_level(spdlog::level::info);

    spdlog::info("EyeD capture device starting");
    spdlog::info("  device_id:  {}", cfg.device_id);
    spdlog::info("  gateway:    {}", cfg.gateway.address);
    spdlog::info("  source:     {}", cfg.camera.source);
    if (cfg.camera.source == "directory") {
        spdlog::info("  image_dir:  {}", cfg.camera.image_dir);
    } else {
        spdlog::info("  device:     {}", cfg.camera.device);
    }
    spdlog::info("  quality:    {:.2f}", cfg.quality.threshold);
    spdlog::info("  fps:        {}", cfg.camera.frame_rate_fps);

    Camera cam(cfg.camera);
    if (!cam.is_available()) {
        spdlog::error("Camera not available (source={}, device={}, image_dir={})",
                      cfg.camera.source, cfg.camera.device, cfg.camera.image_dir);
        return 1;
    }

    QualityGate gate(cfg.quality);
    GrpcClient client(cfg.gateway, cfg.device_id);

    // Initial connection with retry
    spdlog::info("Connecting to gateway...");
    reconnect_with_backoff(client, cfg.gateway);

    // Start capture thread
    FrameBuffer buffer;
    std::thread cap_thread(capture_thread, std::ref(cam), std::ref(buffer));

    // Main loop: gate + send (Thread 2)
    uint64_t sent = 0, rejected_quality = 0, rejected_gw = 0;
    auto stats_time = std::chrono::steady_clock::now();

    while (!g_shutdown.load(std::memory_order_relaxed)) {
        auto maybe_frame = buffer.try_pop();
        if (!maybe_frame) {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
            continue;
        }
        auto& frame = *maybe_frame;

        float q = gate.score(frame.image);
        if (!gate.passes(q)) {
            ++rejected_quality;
            spdlog::debug("Frame {} quality={:.3f} < {:.2f}, skipped",
                          frame.frame_id, q, cfg.quality.threshold);
            continue;
        }

        auto jpeg = gate.encode_jpeg(frame.image);
        if (jpeg.empty()) {
            spdlog::warn("JPEG encode failed for frame {}", frame.frame_id);
            continue;
        }

        auto result = client.send_frame(
            frame.frame_id, jpeg, q, frame.timestamp_us,
            cam.eye_side(), cam.is_nir());

        if (!result.connection_ok) {
            spdlog::warn("Lost connection to gateway, reconnecting...");
            reconnect_with_backoff(client, cfg.gateway);
        } else if (!result.accepted) {
            ++rejected_gw;
            spdlog::warn("Frame {} not accepted (queue_depth={})",
                         frame.frame_id, result.queue_depth);
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
        } else {
            ++sent;
            spdlog::debug("Frame {} sent (quality={:.3f}, {} bytes)",
                          frame.frame_id, q, jpeg.size());
        }

        // Periodic stats log
        auto now = std::chrono::steady_clock::now();
        if (now - stats_time >= std::chrono::seconds(10)) {
            spdlog::info("Stats: sent={} rejected_quality={} rejected_gw={}",
                         sent, rejected_quality, rejected_gw);
            stats_time = now;
        }
    }

    spdlog::info("Shutting down...");
    cap_thread.join();
    spdlog::info("Capture device stopped. Total sent: {}", sent);
    return 0;
}
