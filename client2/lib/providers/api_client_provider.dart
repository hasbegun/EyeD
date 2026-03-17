import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';

final apiConfigProvider = Provider<ApiConfig>((ref) {
  return const ApiConfig(engineBaseUrl: ApiConfig.engineUrl);
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(apiConfigProvider);
  final client = ApiClient(config);
  ref.onDispose(client.dispose);
  return client;
});
