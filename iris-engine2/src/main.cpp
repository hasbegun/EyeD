#include "config.h"
#include "db.h"
#include "fhe.h"
#include "gallery.h"
#include "server_context.h"
#include "routes_health.h"
#include "routes_analyze.h"
#include "routes_enroll.h"
#include "routes_gallery.h"

#include <iostream>
#include <mutex>
#include <httplib.h>
#include <iris/pipeline/iris_pipeline.hpp>

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
    std::mutex pipeline_mutex;
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

    // --- Load gallery from DB ---
    Gallery gallery(config.match_threshold, config.dedup_threshold,
                    fhe.is_active() ? &fhe : nullptr);
    if (db.is_connected()) {
#ifdef IRIS_HAS_FHE
        if (fhe.is_active() && !config.allow_plaintext) {
            for (auto& rt : db.load_all_raw_templates()) {
                auto decrypted = fhe.decrypt_template(rt.iris_blob);
                if (!decrypted) {
                    std::cerr << "[iris-engine2] WARNING: Failed to decrypt template "
                              << rt.template_id << ", skipping" << std::endl;
                    continue;
                }
                GalleryEntry e;
                e.template_id  = rt.template_id;
                e.identity_id  = rt.identity_id;
                e.identity_name = rt.identity_name;
                e.eye_side     = rt.eye_side;
                e.tmpl         = std::move(*decrypted);
                gallery.add(std::move(e));
            }
        } else
#endif
        {
            for (auto& t : db.load_all_templates()) {
                GalleryEntry e;
                e.template_id  = t.template_id;
                e.identity_id  = t.identity_id;
                e.identity_name = t.identity_name;
                e.eye_side     = t.eye_side;
                e.tmpl         = std::move(t.tmpl);
                gallery.add(std::move(e));
            }
        }
        std::cout << "[iris-engine2] Gallery loaded: " << gallery.size()
                  << " templates" << std::endl;
    }

    // --- Register routes ---
    eyed::ServerContext ctx{config, pipeline, pipeline_mutex, fhe, db, gallery};
    httplib::Server svr;

    eyed::register_health_routes (svr, ctx);
    eyed::register_analyze_routes(svr, ctx);
    eyed::register_enroll_routes (svr, ctx);
    eyed::register_gallery_routes(svr, ctx);

    // --- Start server ---
    std::cout << "[iris-engine2] Listening on 0.0.0.0:" << config.port << std::endl;
    svr.listen("0.0.0.0", config.port);

    return 0;
}
