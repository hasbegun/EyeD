import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/constants.dart';
import '../models/analyze_result.dart';
import 'results_provider.dart';

class HistoryEntry {
  final AnalyzeResult result;
  final DateTime timestamp;

  const HistoryEntry({required this.result, required this.timestamp});
}

class HistoryNotifier extends StateNotifier<List<HistoryEntry>> {
  HistoryNotifier() : super([]);

  void onResult(AnalyzeResult result) {
    state = [
      HistoryEntry(result: result, timestamp: DateTime.now()),
      ...state,
    ].take(maxHistoryEntries).toList();
  }
}

final historyProvider =
    StateNotifierProvider<HistoryNotifier, List<HistoryEntry>>((ref) {
  final notifier = HistoryNotifier();
  ref.listen(resultsStreamProvider, (_, next) {
    next.whenData(notifier.onResult);
  });
  return notifier;
});
