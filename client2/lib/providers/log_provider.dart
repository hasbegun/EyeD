import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/analyze_result.dart';

class LogEntry {
  final AnalyzeResponse result;
  final DateTime timestamp;
  final String? fileName;

  const LogEntry({
    required this.result,
    required this.timestamp,
    this.fileName,
  });
}

class LogNotifier extends StateNotifier<List<LogEntry>> {
  LogNotifier() : super([]);

  void add(AnalyzeResponse result, {String? fileName}) {
    state = [
      LogEntry(result: result, timestamp: DateTime.now(), fileName: fileName),
      ...state,
    ];
    // Keep at most 500 entries
    if (state.length > 500) {
      state = state.sublist(0, 500);
    }
  }

  void clear() {
    state = [];
  }
}

final logProvider =
    StateNotifierProvider<LogNotifier, List<LogEntry>>((ref) {
  return LogNotifier();
});
