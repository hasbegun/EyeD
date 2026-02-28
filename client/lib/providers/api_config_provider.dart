import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';

/// Build-time flag: pass --dart-define=API_MODE=proxy for Docker/nginx builds.
const _apiMode = String.fromEnvironment('API_MODE', defaultValue: 'direct');

final apiConfigProvider = Provider<ApiConfig>((ref) {
  if (kIsWeb && _apiMode == 'proxy') {
    // Behind nginx: use same-origin proxy paths.
    // Gateway routes (/health/, /ws/) are served by nginx at same origin.
    // Engine routes use /engine/ prefix, nginx rewrites to iris-engine:7000.
    final origin = Uri.base.origin;
    return ApiConfig(
      gatewayBaseUrl: origin,
      engineBaseUrl: '$origin/engine',
    );
  }
  // Native (macOS) or web dev: connect directly to backend ports.
  return const ApiConfig();
});
