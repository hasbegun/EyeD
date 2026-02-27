#include "camera.h"

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <thread>

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <spdlog/spdlog.h>

namespace fs = std::filesystem;

Camera::Camera(const CameraConfig& cfg) : cfg_(cfg) {
    frame_interval_us_ = std::chrono::microseconds(1'000'000 / cfg_.frame_rate_fps);

    if (cfg_.source == "directory") {
        load_directory_images();
    } else if (cfg_.source == "webcam") {
        // Open webcam: URL stream or device path
        bool opened = false;
        if (cfg_.device.starts_with("http://") || cfg_.device.starts_with("rtsp://")) {
            spdlog::info("Camera: opening stream URL {}", cfg_.device);
            opened = cap_.open(cfg_.device, cv::CAP_FFMPEG);
        } else {
            spdlog::info("Camera: opening device {}", cfg_.device);
            opened = cap_.open(cfg_.device, cv::CAP_V4L2);
            if (opened) {
                cap_.set(cv::CAP_PROP_FRAME_WIDTH, cfg_.width);
                cap_.set(cv::CAP_PROP_FRAME_HEIGHT, cfg_.height);
                cap_.set(cv::CAP_PROP_FPS, cfg_.frame_rate_fps);
            }
        }
        if (!opened || !cap_.isOpened()) {
            spdlog::error("Camera: failed to open webcam '{}'", cfg_.device);
        } else {
            int w = static_cast<int>(cap_.get(cv::CAP_PROP_FRAME_WIDTH));
            int h = static_cast<int>(cap_.get(cv::CAP_PROP_FRAME_HEIGHT));
            spdlog::info("Camera: webcam opened ({}x{})", w, h);
        }
    } else {
        spdlog::error("Camera source '{}' not supported (use 'directory' or 'webcam')", cfg_.source);
    }
}

void Camera::load_directory_images() {
    for (const auto& entry : fs::recursive_directory_iterator(cfg_.image_dir)) {
        if (!entry.is_regular_file()) continue;
        auto ext = entry.path().extension().string();
        std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
        if (ext == ".jpg" || ext == ".jpeg" || ext == ".bmp" || ext == ".png") {
            image_paths_.push_back(entry.path().string());
        }
    }
    std::sort(image_paths_.begin(), image_paths_.end());
    spdlog::info("Camera: loaded {} images from {}", image_paths_.size(), cfg_.image_dir);
}

bool Camera::next_frame(cv::Mat& out_image, uint64_t& out_timestamp_us) {
    if (cfg_.source == "directory") {
        return capture_from_directory(out_image, out_timestamp_us);
    } else if (cfg_.source == "webcam") {
        return capture_from_webcam(out_image, out_timestamp_us);
    }
    return false;
}

bool Camera::capture_from_directory(cv::Mat& out, uint64_t& ts) {
    if (image_paths_.empty()) return false;

    // Rate limiting — sleep until the next frame is due
    auto now = std::chrono::steady_clock::now();
    if (last_frame_time_ != std::chrono::steady_clock::time_point{}) {
        auto next_due = last_frame_time_ + frame_interval_us_;
        if (now < next_due) {
            std::this_thread::sleep_until(next_due);
        }
    }
    last_frame_time_ = std::chrono::steady_clock::now();

    // Load image as grayscale
    const auto& path = image_paths_[dir_index_];
    out = cv::imread(path, cv::IMREAD_GRAYSCALE);
    if (out.empty()) {
        spdlog::warn("Failed to read image: {}", path);
        dir_index_ = (dir_index_ + 1) % image_paths_.size();
        return true; // skip, try next frame
    }

    ts = static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::system_clock::now().time_since_epoch()
        ).count()
    );

    dir_index_ = (dir_index_ + 1) % image_paths_.size();
    if (dir_index_ == 0) {
        spdlog::debug("Camera: wrapped around image directory");
    }
    return true;
}

bool Camera::capture_from_webcam(cv::Mat& out, uint64_t& ts) {
    if (!cap_.isOpened()) return false;

    cv::Mat frame;
    if (!cap_.read(frame)) {
        spdlog::warn("Camera: failed to read frame from webcam");
        return false;
    }

    if (frame.empty()) return true; // skip empty frames

    // Convert to grayscale
    if (frame.channels() > 1) {
        cv::cvtColor(frame, out, cv::COLOR_BGR2GRAY);
    } else {
        out = std::move(frame);
    }

    ts = static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::system_clock::now().time_since_epoch()
        ).count()
    );

    return true;
}

bool Camera::is_available() const {
    if (cfg_.source == "directory") {
        return !image_paths_.empty();
    } else if (cfg_.source == "webcam") {
        return cap_.isOpened();
    }
    return false;
}
