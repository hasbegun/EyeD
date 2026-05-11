#include "routes_analyze.h"

#include <chrono>
#include <nlohmann/json.hpp>
#include <opencv2/imgcodecs.hpp>

#include <iris/utils/base64.hpp>

using json = nlohmann::json;

namespace eyed {

void register_analyze_routes(httplib::Server& svr, ServerContext& ctx) {
    svr.Post("/analyze/json", [&ctx](const httplib::Request& req, httplib::Response& res) {
        auto start = std::chrono::steady_clock::now();

        auto body = json::parse(req.body, nullptr, false);
        if (body.is_discarded()) {
            res.status = 400;
            res.set_content(json({{"detail", "Invalid JSON"}}).dump(), "application/json");
            return;
        }

        auto jpeg_b64  = body.value("jpeg_b64",  "");
        auto eye_side_str = body.value("eye_side", "left");
        auto frame_id  = body.value("frame_id",  "");
        auto device_id = body.value("device_id", "local");

        auto make_error = [&](const std::string& msg, double latency) {
            return json({
                {"frame_id", frame_id}, {"device_id", device_id},
                {"error", msg}, {"latency_ms", latency},
                {"match", nullptr}, {"iris_template_b64", nullptr},
                {"segmentation", nullptr}
            }).dump();
        };

        if (jpeg_b64.empty()) {
            res.set_content(make_error("Missing jpeg_b64", 0), "application/json");
            return;
        }

        auto decoded = iris::base64::decode(jpeg_b64);
        if (!decoded) {
            res.set_content(make_error("Failed to decode base64", 0), "application/json");
            return;
        }

        auto img = cv::imdecode(*decoded, cv::IMREAD_GRAYSCALE);
        if (img.empty()) {
            res.set_content(make_error("Failed to decode JPEG image", 0), "application/json");
            return;
        }

        iris::IRImage ir_image{
            img, frame_id,
            eye_side_str == "right" ? iris::EyeSide::Right : iris::EyeSide::Left};

        iris::Result<iris::PipelineOutput> result;
        {
            std::lock_guard lock(ctx.pipeline_mutex);
            result = ctx.pipeline.run(ir_image);
        }

        auto elapsed = std::chrono::steady_clock::now() - start;
        double latency = std::chrono::duration<double, std::milli>(elapsed).count();

        if (!result || !result->iris_template) {
            std::string msg = "Pipeline failed";
            if (!result)          msg = result.error().message;
            else if (result->error) msg = result->error->message;
            res.set_content(make_error(msg, latency), "application/json");
            return;
        }

        auto match = ctx.gallery.match(*result->iris_template);

        json match_json = nullptr;
        if (match) {
            match_json = {
                {"hamming_distance",       match->hamming_distance},
                {"is_match",               match->is_match},
                {"matched_identity_id",
                 match->is_match ? json(match->matched_identity_id) : json(nullptr)},
                {"matched_identity_name",
                 match->is_match ? json(match->matched_identity_name) : json(nullptr)},
                {"best_rotation",          match->best_rotation},
            };

            {
                std::lock_guard<std::mutex> lock(ctx.db_mutex);
                if (ctx.db.is_connected()) {
                    ctx.db.log_match(
                        frame_id,
                        match->is_match ? match->matched_template_id : "",
                        match->is_match ? match->matched_identity_id : "",
                        match->hamming_distance, match->is_match,
                        device_id, static_cast<int>(latency));
                }
            }
        }

        // SMPC2 secure match (when active, runs in parallel with plaintext path)
        json smpc2_match_json = nullptr;
        if (ctx.smpc2.is_active()) {
            auto smpc2_r = ctx.smpc2.verify(*result->iris_template);
            if (smpc2_r.has_value() && !smpc2_r->empty()) {
                const auto& best = smpc2_r->front();
                smpc2_match_json = {
                    {"hamming_distance",  best.distance},
                    {"is_match",          best.is_match},
                    {"matched_template_id",
                     best.is_match ? json(best.subject_id) : json(nullptr)},
                };
            } else if (!smpc2_r.has_value()) {
                std::cerr << "[analyze] SMPC2 verify error: "
                          << smpc2_r.error().message << std::endl;
            }
        }

        res.set_content(json({
            {"frame_id",          frame_id},
            {"device_id",         device_id},
            {"segmentation",      nullptr},
            {"match",             match_json},
            {"smpc2_match",       smpc2_match_json},
            {"iris_template_b64", nullptr},
            {"latency_ms",        latency},
            {"error",             nullptr},
        }).dump(), "application/json");
    });
}

} // namespace eyed
