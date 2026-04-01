#pragma once

#include "config.h"
#include "db.h"
#include "gallery.h"
#include "smpc.h"

#include <mutex>
#include <iris/pipeline/iris_pipeline.hpp>

namespace eyed {

struct ServerContext {
    Config&               config;
    iris::IrisPipeline&   pipeline;
    std::mutex&           pipeline_mutex;
    SMPCManager&          smpc;
    Database&             db;
    Gallery&              gallery;
    std::mutex            db_mutex;    // Protects Database (PGconn is not thread-safe)
};

} // namespace eyed
