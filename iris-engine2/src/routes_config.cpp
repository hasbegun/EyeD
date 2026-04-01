#include "routes_config.h"

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
            // prod: return only operational fields — no mode, no sensitive data
            res.set_content(json({
                {"gallery_size", static_cast<int>(ctx.gallery.size())},
                {"db_connected", db_ok},
                {"version",      "0.1.0"},
            }).dump(), "application/json");
        } else {
            // dev / test: full visibility
            res.set_content(json({
                {"mode",            ctx.config.mode},
                {"smpc_enabled",    ctx.config.smpc_enabled},
                {"smpc_active",     ctx.smpc.is_active()},
                {"smpc_mode",       ctx.smpc.mode()},
                {"gallery_size",    static_cast<int>(ctx.gallery.size())},
                {"db_connected",    db_ok},
                {"db_name",         ctx.config.db_name},
                {"version",         "0.1.0"},
            }).dump(), "application/json");
        }
    });
}

} // namespace eyed
