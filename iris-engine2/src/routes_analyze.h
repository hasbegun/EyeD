#pragma once

#include <httplib.h>
#include "server_context.h"

namespace eyed {

void register_analyze_routes(httplib::Server& svr, ServerContext& ctx);

} // namespace eyed
