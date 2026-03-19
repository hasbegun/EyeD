#include "routes_config.h"

#include <fstream>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

namespace eyed {

void register_config_routes(httplib::Server& svr, ServerContext& ctx) {

    svr.Get("/config", [&ctx](const httplib::Request&, httplib::Response& res) {
        bool db_ok;
        {
            std::lock_guard<std::mutex> lock(ctx.db_mutex);
            db_ok = ctx.db.is_connected();
        }
        if (ctx.config.mode == "prod") {
            // prod: return only operational fields — no mode, no FHE status, no sensitive data
            res.set_content(json({
                {"gallery_size", static_cast<int>(ctx.gallery.size())},
                {"db_connected", db_ok},
                {"version",      "0.1.0"},
            }).dump(), "application/json");
        } else {
            // dev / test: full visibility
            res.set_content(json({
                {"mode",            ctx.config.mode},
                {"fhe_enabled",     ctx.config.fhe_enabled},
                {"fhe_active",      ctx.fhe.is_active()},
                {"allow_plaintext", ctx.config.allow_plaintext},
                {"gallery_size",    static_cast<int>(ctx.gallery.size())},
                {"db_connected",    db_ok},
                {"db_name",         ctx.config.db_name},
                {"he_key_dir",      ctx.config.he_key_dir},
                {"version",         "0.1.0"},
            }).dump(), "application/json");
        }
    });

    // POST /config/fhe is only registered in dev/test — not available in prod
    if (ctx.config.mode != "prod") {
        svr.Post("/config/fhe", [&ctx](const httplib::Request& req, httplib::Response& res) {
            auto body = json::parse(req.body, nullptr, false);
            if (body.is_discarded() || !body.contains("enabled")) {
                res.status = 400;
                res.set_content(
                    json({{"detail", "Missing or invalid 'enabled' field"}}).dump(),
                    "application/json");
                return;
            }

            bool enabled = body["enabled"].get<bool>();

            {
                std::lock_guard<std::mutex> lock(ctx.fhe_mutex);
                ctx.config.fhe_enabled = enabled;
            }

            // Persist toggle state so it survives container restarts
            std::ofstream state_file(ctx.config.fhe_state_path);
            if (state_file.good()) {
                state_file << (enabled ? "true" : "false");
            }

            res.set_content(json({
                {"fhe_enabled", ctx.config.fhe_enabled},
                {"fhe_active",  ctx.fhe.is_active()},
            }).dump(), "application/json");
        });
    }
}

} // namespace eyed
