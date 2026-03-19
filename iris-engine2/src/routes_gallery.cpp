#include "routes_gallery.h"

#include <nlohmann/json.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <iris/utils/base64.hpp>

using json = nlohmann::json;

namespace eyed {

void register_gallery_routes(httplib::Server& svr, ServerContext& ctx) {

    svr.Get("/gallery/size", [&ctx](const httplib::Request&, httplib::Response& res) {
        res.set_content(
            json({{"gallery_size", static_cast<int>(ctx.gallery.size())}}).dump(),
            "application/json");
    });

    svr.Get("/gallery/list", [&ctx](const httplib::Request&, httplib::Response& res) {
        auto identities = ctx.gallery.list();
        json arr = json::array();
        for (const auto& id : identities) {
            json templates = json::array();
            for (const auto& t : id.templates) {
                templates.push_back({
                    {"template_id", t.template_id},
                    {"eye_side",    t.eye_side},
                });
            }
            arr.push_back({
                {"identity_id", id.identity_id},
                {"name",        id.name},
                {"templates",   templates},
            });
        }
        res.set_content(arr.dump(), "application/json");
    });

    svr.Get("/gallery/template/:id",
            [&ctx](const httplib::Request& req, httplib::Response& res) {
                auto template_id = req.path_params.at("id");

                if (!ctx.db.is_connected()) {
                    res.status = 503;
                    res.set_content(
                        json({{"detail", "Database not connected"}}).dump(),
                        "application/json");
                    return;
                }

                auto row = ctx.db.load_template(template_id);
                if (!row) {
                    res.status = 404;
                    res.set_content(
                        json({{"detail", "Template not found"}}).dump(),
                        "application/json");
                    return;
                }

                json iris_code_b64 = nullptr;
                json mask_code_b64 = nullptr;
                bool is_encrypted  = ctx.config.fhe_enabled && ctx.fhe.is_active();

                if (!is_encrypted && !row->tmpl.iris_codes.empty()) {
                    auto [code_mat, mask_mat] = row->tmpl.iris_codes[0].to_mat();

                    code_mat *= 255;
                    mask_mat *= 255;

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
                    {"template_id",    row->template_id},
                    {"identity_id",    row->identity_id},
                    {"identity_name",  row->identity_name},
                    {"eye_side",       row->eye_side},
                    {"width",          row->width},
                    {"height",         row->height},
                    {"n_scales",       row->n_scales},
                    {"quality_score",  row->quality_score},
                    {"device_id",      row->device_id},
                    {"iris_code_b64",  iris_code_b64},
                    {"mask_code_b64",  mask_code_b64},
                    {"is_encrypted",   is_encrypted},
                }).dump(), "application/json");
            });

    svr.Delete("/gallery/delete/:id",
               [&ctx](const httplib::Request& req, httplib::Response& res) {
                   auto identity_id = req.path_params.at("id");

                   int removed = ctx.gallery.remove(identity_id);

                   if (ctx.db.is_connected()) {
                       ctx.db.delete_identity(identity_id);
                   }

                   res.set_content(json({
                       {"deleted",           removed > 0},
                       {"templates_removed", removed},
                   }).dump(), "application/json");
               });
}

} // namespace eyed
