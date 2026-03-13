#include "config.h"
#include "db.h"
#include "fhe.h"
#include "gallery.h"

#include <chrono>
#include <iostream>
#include <mutex>
#include <random>

#include <httplib.h>
#include <nlohmann/json.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <iris/pipeline/iris_pipeline.hpp>
#include <iris/utils/base64.hpp>

using json = nlohmann::json;

// --- UUID v4 generator ---

static std::string generate_uuid() {
    static thread_local std::mt19937_64 gen{std::random_device{}()};
    std::uniform_int_distribution<uint64_t> dis;
    uint64_t a = dis(gen);
    uint64_t b = dis(gen);
    // Version 4
    a = (a & 0xFFFFFFFFFFFF0FFFULL) | 0x0000000000004000ULL;
    // Variant 1
    b = (b & 0x3FFFFFFFFFFFFFFFULL) | 0x8000000000000000ULL;
    char buf[37];
    std::snprintf(buf, sizeof(buf), "%08x-%04x-%04x-%04x-%012llx",
                  static_cast<uint32_t>(a >> 32),
                  static_cast<uint16_t>((a >> 16) & 0xFFFF),
                  static_cast<uint16_t>(a & 0xFFFF),
                  static_cast<uint16_t>((b >> 48) & 0xFFFF),
                  static_cast<unsigned long long>(b & 0x0000FFFFFFFFFFFFULL));
    return buf;
}

// --- Main ---

int main() {
    auto config = Config::from_env();

    std::cout << "[iris-engine2] Starting..." << std::endl;
    std::cout << "[iris-engine2] Pipeline config: " << config.pipeline_config << std::endl;
    std::cout << "[iris-engine2] Match threshold: " << config.match_threshold << std::endl;
    std::cout << "[iris-engine2] Dedup threshold: " << config.dedup_threshold << std::endl;

    // --- Load pipeline ---
    auto pipeline_result = iris::IrisPipeline::from_config(config.pipeline_config);
    if (!pipeline_result) {
        std::cerr << "[iris-engine2] FATAL: Failed to load pipeline: "
                  << pipeline_result.error().message << std::endl;
        return 1;
    }
    auto pipeline = std::move(*pipeline_result);
    std::mutex pipeline_mutex;  // Serialize pipeline access (not thread-safe)
    std::cout << "[iris-engine2] Pipeline loaded" << std::endl;

    // --- Initialize FHE ---
    FHEManager fhe;
    if (config.fhe_enabled) {
        std::cout << "[iris-engine2] FHE enabled, initializing..." << std::endl;
        if (!fhe.initialize(config.he_key_dir)) {
            if (!config.allow_plaintext) {
                std::cerr << "[iris-engine2] FATAL: FHE initialization failed "
                          << "and EYED_ALLOW_PLAINTEXT is not set" << std::endl;
                return 1;
            }
            std::cerr << "[iris-engine2] WARNING: FHE init failed, "
                      << "falling back to plaintext mode" << std::endl;
        }
    } else {
        std::cout << "[iris-engine2] FHE disabled by configuration" << std::endl;
        if (!config.allow_plaintext) {
            std::cerr << "[iris-engine2] FATAL: FHE is disabled but "
                      << "EYED_ALLOW_PLAINTEXT is not set" << std::endl;
            return 1;
        }
    }

    // --- Connect to database ---
    Database db;
    if (!config.db_url.empty()) {
        if (!db.connect(config.db_url)) {
            std::cerr << "[iris-engine2] WARNING: DB connection failed, running in-memory only"
                      << std::endl;
        }
    } else {
        std::cout << "[iris-engine2] No DB URL configured, running in-memory only" << std::endl;
    }

    // --- Initialize gallery ---
    Gallery gallery(config.match_threshold, config.dedup_threshold,
                    fhe.is_active() ? &fhe : nullptr);
    if (db.is_connected()) {
#ifdef IRIS_HAS_FHE
        if (fhe.is_active() && !config.allow_plaintext) {
            // Full FHE mode: load encrypted blobs, decrypt to plaintext
            // for in-memory matching (encryption at rest)
            auto raw_templates = db.load_all_raw_templates();
            for (auto& rt : raw_templates) {
                auto decrypted = fhe.decrypt_template(rt.iris_blob);
                if (!decrypted) {
                    std::cerr << "[iris-engine2] WARNING: Failed to decrypt "
                              << "template " << rt.template_id
                              << ", skipping" << std::endl;
                    continue;
                }
                GalleryEntry entry;
                entry.template_id = rt.template_id;
                entry.identity_id = rt.identity_id;
                entry.identity_name = rt.identity_name;
                entry.eye_side = rt.eye_side;
                entry.tmpl = std::move(*decrypted);
                gallery.add(std::move(entry));
            }
        } else
#endif
        {
            // Plaintext mode (also used when allow_plaintext=true)
            auto templates = db.load_all_templates();
            for (auto& t : templates) {
                GalleryEntry entry;
                entry.template_id = t.template_id;
                entry.identity_id = t.identity_id;
                entry.identity_name = t.identity_name;
                entry.eye_side = t.eye_side;
                entry.tmpl = std::move(t.tmpl);
                gallery.add(std::move(entry));
            }
        }
        std::cout << "[iris-engine2] Gallery loaded: " << gallery.size()
                  << " templates" << std::endl;
    }

    // --- HTTP server ---
    httplib::Server svr;

    // ==================== Health ====================

    svr.Get("/health/alive", [](const httplib::Request&, httplib::Response& res) {
        json j = {{"alive", true}};
        res.set_content(j.dump(), "application/json");
    });

    svr.Get("/health/ready", [&](const httplib::Request&, httplib::Response& res) {
        json j = {
            {"alive", true},
            {"ready", true},
            {"pipeline_loaded", true},
            {"nats_connected", false},
            {"gallery_size", static_cast<int>(gallery.size())},
            {"db_connected", db.is_connected()},
            {"redis_connected", false},
            {"he_active", fhe.is_active()},
            {"pipeline_pool_size", 1},
            {"pipeline_pool_available", 1},
            {"version", "0.1.0"},
        };
        res.set_content(j.dump(), "application/json");
    });

    // ==================== Analyze ====================

    svr.Post("/analyze/json", [&](const httplib::Request& req, httplib::Response& res) {
        auto start = std::chrono::steady_clock::now();

        auto body = json::parse(req.body, nullptr, false);
        if (body.is_discarded()) {
            res.status = 400;
            res.set_content(json({{"detail", "Invalid JSON"}}).dump(), "application/json");
            return;
        }

        auto jpeg_b64 = body.value("jpeg_b64", "");
        auto eye_side_str = body.value("eye_side", "left");
        auto frame_id = body.value("frame_id", "");
        auto device_id = body.value("device_id", "local");

        if (jpeg_b64.empty()) {
            res.set_content(json({
                {"frame_id", frame_id}, {"device_id", device_id},
                {"error", "Missing jpeg_b64"}, {"latency_ms", 0},
                {"match", nullptr}, {"iris_template_b64", nullptr},
                {"segmentation", nullptr}
            }).dump(), "application/json");
            return;
        }

        // Decode base64 → JPEG bytes → grayscale image
        auto decoded = iris::base64::decode(jpeg_b64);
        if (!decoded) {
            res.set_content(json({
                {"frame_id", frame_id}, {"device_id", device_id},
                {"error", "Failed to decode base64"}, {"latency_ms", 0},
                {"match", nullptr}, {"iris_template_b64", nullptr},
                {"segmentation", nullptr}
            }).dump(), "application/json");
            return;
        }

        auto img = cv::imdecode(*decoded, cv::IMREAD_GRAYSCALE);
        if (img.empty()) {
            res.set_content(json({
                {"frame_id", frame_id}, {"device_id", device_id},
                {"error", "Failed to decode JPEG image"}, {"latency_ms", 0},
                {"match", nullptr}, {"iris_template_b64", nullptr},
                {"segmentation", nullptr}
            }).dump(), "application/json");
            return;
        }

        // Run pipeline (serialized)
        iris::IRImage ir_image{
            img, frame_id,
            eye_side_str == "right" ? iris::EyeSide::Right : iris::EyeSide::Left};

        iris::Result<iris::PipelineOutput> result;
        {
            std::lock_guard lock(pipeline_mutex);
            result = pipeline.run(ir_image);
        }

        auto elapsed = std::chrono::steady_clock::now() - start;
        double latency = std::chrono::duration<double, std::milli>(elapsed).count();

        if (!result || !result->iris_template) {
            std::string error_msg = "Pipeline failed";
            if (!result) {
                error_msg = result.error().message;
            } else if (result->error) {
                error_msg = result->error->message;
            }
            res.set_content(json({
                {"frame_id", frame_id}, {"device_id", device_id},
                {"error", error_msg}, {"latency_ms", latency},
                {"match", nullptr}, {"iris_template_b64", nullptr},
                {"segmentation", nullptr}
            }).dump(), "application/json");
            return;
        }

        // Match against gallery
        auto match = gallery.match(*result->iris_template);

        json match_json = nullptr;
        if (match) {
            match_json = {
                {"hamming_distance", match->hamming_distance},
                {"is_match", match->is_match},
                {"matched_identity_id",
                 match->is_match ? json(match->matched_identity_id) : json(nullptr)},
                {"matched_identity_name",
                 match->is_match ? json(match->matched_identity_name) : json(nullptr)},
                {"best_rotation", match->best_rotation},
            };

            // Log match to DB
            if (db.is_connected()) {
                db.log_match(
                    frame_id,
                    match->is_match ? match->matched_template_id : "",
                    match->is_match ? match->matched_identity_id : "",
                    match->hamming_distance, match->is_match,
                    device_id, static_cast<int>(latency));
            }
        }

        json resp = {
            {"frame_id", frame_id},
            {"device_id", device_id},
            {"segmentation", nullptr},
            {"match", match_json},
            {"iris_template_b64", nullptr},
            {"latency_ms", latency},
            {"error", nullptr},
        };
        res.set_content(resp.dump(), "application/json");
    });

    // ==================== Enroll ====================

    svr.Post("/enroll", [&](const httplib::Request& req, httplib::Response& res) {
        auto body = json::parse(req.body, nullptr, false);
        if (body.is_discarded()) {
            res.status = 400;
            res.set_content(json({{"detail", "Invalid JSON"}}).dump(), "application/json");
            return;
        }

        auto identity_id = body.value("identity_id", "");
        auto identity_name = body.value("identity_name", "");
        auto jpeg_b64 = body.value("jpeg_b64", "");
        auto eye_side_str = body.value("eye_side", "left");
        auto device_id = body.value("device_id", "local");

        if (identity_id.empty() || jpeg_b64.empty()) {
            res.set_content(json({
                {"identity_id", identity_id}, {"template_id", ""},
                {"is_duplicate", false},
                {"duplicate_identity_id", nullptr},
                {"duplicate_identity_name", nullptr},
                {"error", "Missing identity_id or jpeg_b64"}
            }).dump(), "application/json");
            return;
        }

        // Decode image
        auto decoded = iris::base64::decode(jpeg_b64);
        if (!decoded) {
            res.set_content(json({
                {"identity_id", identity_id}, {"template_id", ""},
                {"is_duplicate", false},
                {"duplicate_identity_id", nullptr},
                {"duplicate_identity_name", nullptr},
                {"error", "Failed to decode base64"}
            }).dump(), "application/json");
            return;
        }

        auto img = cv::imdecode(*decoded, cv::IMREAD_GRAYSCALE);
        if (img.empty()) {
            res.set_content(json({
                {"identity_id", identity_id}, {"template_id", ""},
                {"is_duplicate", false},
                {"duplicate_identity_id", nullptr},
                {"duplicate_identity_name", nullptr},
                {"error", "Failed to decode JPEG image"}
            }).dump(), "application/json");
            return;
        }

        // Run pipeline
        iris::IRImage ir_image{
            img, identity_id,
            eye_side_str == "right" ? iris::EyeSide::Right : iris::EyeSide::Left};

        iris::Result<iris::PipelineOutput> result;
        {
            std::lock_guard lock(pipeline_mutex);
            result = pipeline.run(ir_image);
        }

        if (!result || !result->iris_template) {
            std::string error_msg = "Pipeline failed";
            if (!result) error_msg = result.error().message;
            else if (result->error) error_msg = result->error->message;

            res.set_content(json({
                {"identity_id", identity_id}, {"template_id", ""},
                {"is_duplicate", false},
                {"duplicate_identity_id", nullptr},
                {"duplicate_identity_name", nullptr},
                {"error", error_msg}
            }).dump(), "application/json");
            return;
        }

        // Check duplicate
        auto dup = gallery.check_duplicate(*result->iris_template);
        if (dup.is_duplicate) {
            res.set_content(json({
                {"identity_id", identity_id},
                {"template_id", ""},
                {"is_duplicate", true},
                {"duplicate_identity_id", dup.duplicate_identity_id},
                {"duplicate_identity_name", dup.duplicate_identity_name},
                {"error", nullptr}
            }).dump(), "application/json");
            return;
        }

        // Generate template ID and persist
        auto template_id = generate_uuid();

        // Persist to DB
        if (db.is_connected()) {
            db.ensure_identity(identity_id, identity_name);
#ifdef IRIS_HAS_FHE
            if (fhe.is_active() && !config.allow_plaintext) {
                // Full FHE mode: encrypt template for DB storage (slow)
                auto [iris_blob, mask_blob] = fhe.encrypt_template(*result->iris_template);
                if (iris_blob.empty() || mask_blob.empty()) {
                    res.set_content(json({
                        {"identity_id", identity_id}, {"template_id", ""},
                        {"is_duplicate", false},
                        {"duplicate_identity_id", nullptr},
                        {"duplicate_identity_name", nullptr},
                        {"error", "FHE encryption failed"}
                    }).dump(), "application/json");
                    return;
                }
                db.persist_encrypted_template(
                    template_id, identity_id, eye_side_str,
                    iris_blob, mask_blob,
                    static_cast<int>(result->iris_template->iris_codes.size()),
                    device_id);
            } else
#endif
            {
                // Plaintext DB storage (fast path, also used when allow_plaintext=true)
                db.persist_template(template_id, identity_id, eye_side_str,
                                    *result->iris_template, device_id);
            }
        }

        // Add plaintext entry to in-memory gallery (fast matching)
        {
            GalleryEntry entry;
            entry.template_id = template_id;
            entry.identity_id = identity_id;
            entry.identity_name = identity_name;
            entry.eye_side = eye_side_str;
            entry.tmpl = *result->iris_template;
            gallery.add(std::move(entry));
        }

        res.set_content(json({
            {"identity_id", identity_id},
            {"template_id", template_id},
            {"is_duplicate", false},
            {"duplicate_identity_id", nullptr},
            {"duplicate_identity_name", nullptr},
            {"error", nullptr}
        }).dump(), "application/json");
    });

    // ==================== Gallery ====================

    svr.Get("/gallery/size", [&](const httplib::Request&, httplib::Response& res) {
        res.set_content(
            json({{"gallery_size", static_cast<int>(gallery.size())}}).dump(),
            "application/json");
    });

    svr.Get("/gallery/list", [&](const httplib::Request&, httplib::Response& res) {
        auto identities = gallery.list();
        json arr = json::array();
        for (const auto& id : identities) {
            json templates = json::array();
            for (const auto& t : id.templates) {
                templates.push_back({
                    {"template_id", t.template_id},
                    {"eye_side", t.eye_side},
                });
            }
            arr.push_back({
                {"identity_id", id.identity_id},
                {"name", id.name},
                {"templates", templates},
            });
        }
        res.set_content(arr.dump(), "application/json");
    });

    svr.Get("/gallery/template/:id",
            [&](const httplib::Request& req, httplib::Response& res) {
                auto template_id = req.path_params.at("id");

                if (!db.is_connected()) {
                    res.status = 503;
                    res.set_content(
                        json({{"detail", "Database not connected"}}).dump(),
                        "application/json");
                    return;
                }

                auto row = db.load_template(template_id);
                if (!row) {
                    res.status = 404;
                    res.set_content(
                        json({{"detail", "Template not found"}}).dump(),
                        "application/json");
                    return;
                }

                // Render iris code and mask code as PNG → base64
                // When FHE is active, codes are encrypted — no visualization
                json iris_code_b64 = nullptr;
                json mask_code_b64 = nullptr;
                bool is_encrypted = fhe.is_active();

                if (!is_encrypted && !row->tmpl.iris_codes.empty()) {
                    auto [code_mat, mask_mat] = row->tmpl.iris_codes[0].to_mat();

                    // to_mat() returns 0/1 values; scale to 0/255 for visible PNG
                    code_mat *= 255;
                    mask_mat *= 255;

                    // Scale up for visibility (16x512 → 128x512)
                    cv::Mat iris_vis;
                    cv::resize(code_mat, iris_vis, cv::Size(512, 128),
                               0, 0, cv::INTER_NEAREST);
                    std::vector<uint8_t> iris_png;
                    cv::imencode(".png", iris_vis, iris_png);
                    iris_code_b64 = iris::base64::encode(iris_png);

                    cv::Mat mask_vis;
                    cv::resize(mask_mat, mask_vis, cv::Size(512, 128),
                               0, 0, cv::INTER_NEAREST);
                    std::vector<uint8_t> mask_png;
                    cv::imencode(".png", mask_vis, mask_png);
                    mask_code_b64 = iris::base64::encode(mask_png);
                }

                res.set_content(json({
                    {"template_id", row->template_id},
                    {"identity_id", row->identity_id},
                    {"identity_name", row->identity_name},
                    {"eye_side", row->eye_side},
                    {"width", row->width},
                    {"height", row->height},
                    {"n_scales", row->n_scales},
                    {"quality_score", row->quality_score},
                    {"device_id", row->device_id},
                    {"iris_code_b64", iris_code_b64},
                    {"mask_code_b64", mask_code_b64},
                    {"is_encrypted", is_encrypted},
                }).dump(), "application/json");
            });

    svr.Delete("/gallery/delete/:id",
               [&](const httplib::Request& req, httplib::Response& res) {
                   auto identity_id = req.path_params.at("id");

                   // Remove from in-memory gallery
                   int removed = gallery.remove(identity_id);

                   // Remove from DB
                   if (db.is_connected()) {
                       db.delete_identity(identity_id);
                   }

                   res.set_content(json({
                       {"deleted", removed > 0},
                       {"templates_removed", removed},
                   }).dump(), "application/json");
               });

    // --- Start server ---
    std::cout << "[iris-engine2] Listening on 0.0.0.0:" << config.port << std::endl;
    svr.listen("0.0.0.0", config.port);

    return 0;
}
