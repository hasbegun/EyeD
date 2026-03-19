#pragma once

#include "config.h"
#include "db.h"
#include "fhe.h"
#include "gallery.h"

#include <mutex>
#include <iris/pipeline/iris_pipeline.hpp>

namespace eyed {

struct ServerContext {
    Config&               config;
    iris::IrisPipeline&   pipeline;
    std::mutex&           pipeline_mutex;
    FHEManager&           fhe;
    Database&             db;
    Gallery&              gallery;
    std::mutex            fhe_mutex;   // Protects runtime fhe_enabled toggle (dev/test only)
};

} // namespace eyed
