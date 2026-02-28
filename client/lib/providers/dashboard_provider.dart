import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/constants.dart';
import '../models/analyze_result.dart';
import 'results_provider.dart';

class DashboardStats {
  final int total;
  final int matches;
  final int errors;

  const DashboardStats({this.total = 0, this.matches = 0, this.errors = 0});
}

class DashboardStatsNotifier extends StateNotifier<DashboardStats> {
  DashboardStatsNotifier() : super(const DashboardStats());

  void onResult(AnalyzeResult r) {
    state = DashboardStats(
      total: state.total + 1,
      matches: state.matches + (r.match?.isMatch == true ? 1 : 0),
      errors: state.errors + (r.error != null ? 1 : 0),
    );
  }
}

final dashboardStatsProvider =
    StateNotifierProvider<DashboardStatsNotifier, DashboardStats>((ref) {
  final notifier = DashboardStatsNotifier();
  ref.listen(resultsStreamProvider, (_, next) {
    next.whenData(notifier.onResult);
  });
  return notifier;
});

class DashboardResultsNotifier extends StateNotifier<List<AnalyzeResult>> {
  DashboardResultsNotifier() : super([]);

  void onResult(AnalyzeResult r) {
    state = [r, ...state].take(maxDashboardResults).toList();
  }
}

final dashboardResultsProvider =
    StateNotifierProvider<DashboardResultsNotifier, List<AnalyzeResult>>((ref) {
  final notifier = DashboardResultsNotifier();
  ref.listen(resultsStreamProvider, (_, next) {
    next.whenData(notifier.onResult);
  });
  return notifier;
});
