#include "routes_enroll.h"
#include "utils.h"

#include <nlohmann/json.hpp>
#include <opencv2/imgcodecs.hpp>
#include <iris/utils/base64.hpp>

using json = nlohmann::json;

namespace eyed {

void register_enroll_routes(httplib::Server& svr, ServerContext& ctx) {
    svr.Post("/enroll", [&ctx](const httplib::Request& req, httplib::Response& res) {
        auto body = json::parse(req.body, nullptr, false);
        if (body.is_discarded()) {
            res.status = 400;
            res.set_content(json({{"detail", "Invalid JSON"}}).dump(), "application/json");
            return;
        }

        auto identity_id   = body.value("identity_id",   "");
        auto identity_name = body.value("identity_name", "");
        auto jpeg_b64      = body.value("jpeg_b64",      "");
        auto eye_side_str  = body.value("eye_side",      "left");
        auto device_id     = body.value("device_id",     "local");

        auto make_error = [&](const std::string& msg) {
            return json({
                {"identity_id",            identity_id},
                {"template_id",            ""},
                {"is_duplicate",           false},
                {"duplicate_identity_id",  nullptr},
                {"duplicate_identity_name",nullptr},
                {"error",                  msg}
            }).dump();
        };

        if (identity_id.empty() || jpeg_b64.empty()) {
            res.set_content(make_error("Missing identity_id or jpeg_b64"), "application/json");
            return;
        }

        auto decoded = iris::base64::decode(jpeg_b64);
        if (!decoded) {
            res.set_content(make_error("Failed to decode base64"), "application/json");
            return;
        }

        auto img = cv::imdecode(*decoded, cv::IMREAD_GRAYSCALE);
        if (img.empty()) {
            res.set_content(make_error("Failed to decode JPEG image"), "application/json");
            return;
        }

        iris::IRImage ir_image{
            img, identity_id,
            eye_side_str == "right" ? iris::EyeSide::Right : iris::EyeSide::Left};

        iris::Result<iris::PipelineOutput> result;
        {
            std::lock_guard lock(ctx.pipeline_mutex);
            result = ctx.pipeline.run(ir_image);
        }

        if (!result || !result->iris_template) {
            std::string msg = "Pipeline failed";
            if (!result)           msg = result.error().message;
            else if (result->error) msg = result->error->message;
            res.set_content(make_error(msg), "application/json");
            return;
        }

        // Duplicate check
        auto dup = ctx.gallery.check_duplicate(*result->iris_template);
        if (dup.is_duplicate) {
            res.set_content(json({
                {"identity_id",            identity_id},
                {"template_id",            ""},
                {"is_duplicate",           true},
                {"duplicate_identity_id",  dup.duplicate_identity_id},
                {"duplicate_identity_name",dup.duplicate_identity_name},
                {"error",                  nullptr}
            }).dump(), "application/json");
            return;
        }

        auto template_id = generate_uuid();

        // Persist to DB
        if (ctx.db.is_connected()) {
            ctx.db.ensure_identity(identity_id, identity_name);
#ifdef IRIS_HAS_FHE
            if (ctx.fhe.is_active() && !ctx.config.allow_plaintext) {
                auto [iris_blob, mask_blob] = ctx.fhe.encrypt_template(*result->iris_template);
                if (iris_blob.empty() || mask_blob.empty()) {
                    res.set_content(make_error("FHE encryption failed"), "application/json");
                    return;
                }
                ctx.db.persist_encrypted_template(
                    template_id, identity_id, eye_side_str,
                    iris_blob, mask_blob,
                    static_cast<int>(result->iris_template->iris_codes.size()),
                    device_id);
            } else
#endif
            {
                ctx.db.persist_template(template_id, identity_id, eye_side_str,
                                        *result->iris_template, device_id);
            }
        }

        // Add to in-memory gallery
        {
            GalleryEntry entry;
            entry.template_id  = template_id;
            entry.identity_id  = identity_id;
            entry.identity_name = identity_name;
            entry.eye_side     = eye_side_str;
            entry.tmpl         = *result->iris_template;
            ctx.gallery.add(std::move(entry));
        }

        res.set_content(json({
            {"identity_id",            identity_id},
            {"template_id",            template_id},
            {"is_duplicate",           false},
            {"duplicate_identity_id",  nullptr},
            {"duplicate_identity_name",nullptr},
            {"is_encrypted",           ctx.fhe.is_active()},
            {"error",                  nullptr}
        }).dump(), "application/json");
    });
}

} // namespace eyed
