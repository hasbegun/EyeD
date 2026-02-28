import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/analyze_result.dart';
import 'results_provider.dart';

class DeviceInfo {
  final String id;
  final DateTime lastSeen;
  final AnalyzeResult? lastResult;
  final int frameCount;

  const DeviceInfo({
    required this.id,
    required this.lastSeen,
    this.lastResult,
    this.frameCount = 0,
  });
}

class DeviceMapNotifier extends StateNotifier<Map<String, DeviceInfo>> {
  DeviceMapNotifier() : super({});

  void onResult(AnalyzeResult result) {
    final existing = state[result.deviceId];
    state = {
      ...state,
      result.deviceId: DeviceInfo(
        id: result.deviceId,
        lastSeen: DateTime.now(),
        lastResult: result,
        frameCount: (existing?.frameCount ?? 0) + 1,
      ),
    };
  }
}

final deviceMapProvider =
    StateNotifierProvider<DeviceMapNotifier, Map<String, DeviceInfo>>((ref) {
  final notifier = DeviceMapNotifier();
  ref.listen(resultsStreamProvider, (_, next) {
    next.whenData(notifier.onResult);
  });
  return notifier;
});
