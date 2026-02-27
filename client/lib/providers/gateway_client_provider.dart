import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/gateway_client.dart';
import 'api_config_provider.dart';

final gatewayClientProvider = Provider<GatewayClient>((ref) {
  final config = ref.watch(apiConfigProvider);
  final client = GatewayClient(config);
  ref.onDispose(client.dispose);
  return client;
});
