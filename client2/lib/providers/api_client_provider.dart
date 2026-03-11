import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';
import 'engine_provider.dart';

final apiConfigProvider = Provider<ApiConfig>((ref) {
  final engine = ref.watch(selectedEngineProvider);
  final baseUrl = engine == SelectedEngine.engine1
      ? ApiConfig.engine1Url
      : ApiConfig.engine2Url;
  return ApiConfig(engineBaseUrl: baseUrl);
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(apiConfigProvider);
  final client = ApiClient(config);
  ref.onDispose(client.dispose);
  return client;
});
