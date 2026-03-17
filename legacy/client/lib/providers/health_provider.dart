import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/constants.dart';
import '../models/health.dart';
import 'gateway_client_provider.dart';

final healthPollTickProvider = StreamProvider<int>((ref) {
  return Stream.periodic(healthPollInterval, (i) => i);
});

final gatewayHealthProvider = FutureProvider<HealthReady?>((ref) async {
  ref.watch(healthPollTickProvider);
  try {
    return await ref.read(gatewayClientProvider).checkReady();
  } catch (_) {
    return null;
  }
});

final engineHealthProvider = FutureProvider<EngineHealth?>((ref) async {
  ref.watch(healthPollTickProvider);
  try {
    return await ref.read(gatewayClientProvider).checkEngineReady();
  } catch (_) {
    return null;
  }
});
