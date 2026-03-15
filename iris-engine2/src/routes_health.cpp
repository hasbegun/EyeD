#include "routes_health.h"
#include <nlohmann/json.hpp>

using json = nlohmann::json;

namespace eyed {

void register_health_routes(httplib::Server& svr, ServerContext& ctx) {
    svr.Get("/health/alive", [](const httplib::Request&, httplib::Response& res) {
        res.set_content(json({{"alive", true}}).dump(), "application/json");
    });

    svr.Get("/health/ready", [&ctx](const httplib::Request&, httplib::Response& res) {
        json j = {
            {"alive",                 true},
            {"ready",                 true},
            {"pipeline_loaded",       true},
            {"nats_connected",        false},
            {"gallery_size",          static_cast<int>(ctx.gallery.size())},
            {"db_connected",          ctx.db.is_connected()},
            {"redis_connected",       false},
            {"he_active",             ctx.fhe.is_active()},
            {"pipeline_pool_size",    1},
            {"pipeline_pool_available", 1},
            {"version",               "0.1.0"},
        };
        res.set_content(j.dump(), "application/json");
    });
}

} // namespace eyed
