#pragma once

#include "server_context.h"
#include <httplib.h>

namespace eyed {

void register_config_routes(httplib::Server& svr, ServerContext& ctx);

} // namespace eyed
