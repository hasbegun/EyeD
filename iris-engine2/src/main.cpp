#include "config.h"
#include "db.h"
#include "gallery.h"
#include "smpc.h"
#include "server_context.h"
#include "routes_health.h"
#include "routes_analyze.h"
#include "routes_enroll.h"
#include "routes_gallery.h"
#include "routes_config.h"

#include <fstream>
#include <iostream>
#include <mutex>
#include <httplib.h>
#include <iris/pipeline/iris_pipeline.hpp>
#include <spdlog/spdlog.h>

int main() {
    auto config = Config::from_env();

    // Set log level from mode (applies to all spdlog loggers, including libiris)
    if (config.mode == "prod")      spdlog::set_level(spdlog::level::warn);
    else if (config.mode == "test") spdlog::set_level(spdlog::level::info);
    else                            spdlog::set_level(spdlog::level::debug);

    std::cout << "[iris-engine2] Starting in " << config.mode << " mode..." << std::endl;
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

    // --- Initialize SMPC ---
    SMPCManager smpc;
    if (config.smpc_enabled) {
        std::cout << "[iris-engine2] SMPC enabled (mode=" << config.smpc_mode
                  << "), initializing..." << std::endl;
        SMPCManager::SecurityConfig sec_cfg;
        sec_cfg.tls_cert_dir = config.tls_cert_dir;
        sec_cfg.audit_log_path = config.audit_log_path;
        sec_cfg.security_monitor_enabled = config.security_monitor_enabled;

        if (!smpc.initialize(config.smpc_mode, config.nats_url,
                             config.smpc_num_parties,
                             config.smpc_pipeline_depth,
                             config.smpc_shards_per_participant,
                             sec_cfg)) {
            if (config.smpc_fallback_plaintext) {
                std::cerr << "[iris-engine2] WARNING: SMPC init failed, "
                          << "falling back to plaintext matching "
                          << "(EYED_SMPC_FALLBACK_PLAINTEXT=true)" << std::endl;
            } else {
                std::cerr << "[iris-engine2] FATAL: SMPC initialization failed"
                          << std::endl;
                return 1;
            }
        }
    } else {
        std::cout << "[iris-engine2] SMPC disabled by configuration" << std::endl;
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
    Gallery gallery(config.match_threshold, config.dedup_threshold);
    if (smpc.is_active()) {
        if (smpc.is_distributed()) {
            gallery.enable_smpc_distributed(&smpc);
        } else {
            gallery.enable_smpc(smpc.gallery());
        }
    }
    if (db.is_connected()) {
        auto db_templates = db.load_all_templates();

        // Migrate plaintext templates into SMPC shares (if SMPC is active)
        if (smpc.is_active() && !db_templates.empty()) {
            std::cout << "[iris-engine2] Migrating " << db_templates.size()
                      << " DB templates into SMPC shares..." << std::endl;

            std::vector<std::pair<std::string, iris::IrisTemplate>> migration_pairs;
            migration_pairs.reserve(db_templates.size());
            for (const auto& t : db_templates) {
                migration_pairs.emplace_back(t.template_id, t.tmpl);
            }
            auto stats = smpc.migrate_templates(migration_pairs);
            if (stats.failed > 0) {
                std::cerr << "[iris-engine2] WARNING: " << stats.failed
                          << " templates failed SMPC migration" << std::endl;
            }
        }

        // Add to in-memory gallery (metadata + plaintext for non-SMPC match path)
        for (auto& t : db_templates) {
            GalleryEntry e;
            e.template_id   = t.template_id;
            e.identity_id   = t.identity_id;
            e.identity_name = t.identity_name;
            e.eye_side      = t.eye_side;
            e.tmpl          = std::move(t.tmpl);
            gallery.add_metadata_only(std::move(e));
        }
        std::cout << "[iris-engine2] Gallery loaded: " << gallery.size()
                  << " templates" << std::endl;
    }

    // --- Register routes ---
    eyed::ServerContext ctx{config, pipeline, pipeline_mutex, smpc, db, gallery, {}};
    httplib::Server svr;

    eyed::register_health_routes (svr, ctx);
    eyed::register_analyze_routes(svr, ctx);
    eyed::register_enroll_routes (svr, ctx);
    eyed::register_gallery_routes(svr, ctx);
    eyed::register_config_routes (svr, ctx);

    // --- Start server ---
    std::cout << "[iris-engine2] Listening on 0.0.0.0:" << config.port << std::endl;
    svr.listen("0.0.0.0", config.port);

    return 0;
}
