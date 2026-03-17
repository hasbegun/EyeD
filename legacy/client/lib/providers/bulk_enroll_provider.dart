import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enrollment.dart';
import 'gallery_provider.dart';
import 'gateway_client_provider.dart';

class BulkEnrollState {
  final bool running;
  final String? dataset;

  /// Live counters
  final int processed;
  final int enrolled;
  final int duplicates;
  final int errors;

  /// Only dup and error entries (for summary report)
  final List<BulkEnrollResult> reportEntries;

  /// Server-side summary (set when done)
  final BulkEnrollSummary? summary;

  /// Connection/stream error
  final String? connectionError;

  const BulkEnrollState({
    this.running = false,
    this.dataset,
    this.processed = 0,
    this.enrolled = 0,
    this.duplicates = 0,
    this.errors = 0,
    this.reportEntries = const [],
    this.summary,
    this.connectionError,
  });

  bool get idle => !running && summary == null && connectionError == null;
  bool get done => !running && (summary != null || connectionError != null);

  BulkEnrollState copyWith({
    bool? running,
    String? dataset,
    int? processed,
    int? enrolled,
    int? duplicates,
    int? errors,
    List<BulkEnrollResult>? reportEntries,
    BulkEnrollSummary? summary,
    String? connectionError,
  }) =>
      BulkEnrollState(
        running: running ?? this.running,
        dataset: dataset ?? this.dataset,
        processed: processed ?? this.processed,
        enrolled: enrolled ?? this.enrolled,
        duplicates: duplicates ?? this.duplicates,
        errors: errors ?? this.errors,
        reportEntries: reportEntries ?? this.reportEntries,
        summary: summary ?? this.summary,
        connectionError: connectionError ?? this.connectionError,
      );
}

/// Manages bulk enrollment as a background operation.
///
/// The SSE subscription lives in this provider (not in any widget), so it
/// survives page navigation.  The AppBar chip in [ShellScaffold] shows
/// progress while the user browses other pages.
class BulkEnrollNotifier extends StateNotifier<BulkEnrollState> {
  final Ref _ref;
  StreamSubscription<BulkEnrollEvent>? _subscription;

  BulkEnrollNotifier(this._ref) : super(const BulkEnrollState());

  void start({required String dataset, List<String>? subjects}) {
    _subscription?.cancel();

    state = BulkEnrollState(running: true, dataset: dataset);

    final client = _ref.read(gatewayClientProvider);
    final stream = client.enrollBatch(
      dataset: dataset,
      subjects: subjects,
    );

    _subscription = stream.listen(
      (event) {
        if (!mounted) return;
        switch (event) {
          case BulkEnrollProgress(:final result):
            final isError = result.error != null;
            final isDup = result.isDuplicate;
            final isEnrolled = !isError && !isDup;

            state = state.copyWith(
              processed: state.processed + 1,
              enrolled: state.enrolled + (isEnrolled ? 1 : 0),
              duplicates: state.duplicates + (isDup ? 1 : 0),
              errors: state.errors + (isError ? 1 : 0),
              reportEntries: (isDup || isError)
                  ? [...state.reportEntries, result]
                  : null,
            );
          case BulkEnrollDone(:final summary):
            state = state.copyWith(
              running: false,
              summary: summary,
            );
            _ref.read(galleryProvider.notifier).refresh();
        }
      },
      onError: (e) {
        if (!mounted) return;
        state = state.copyWith(
          running: false,
          connectionError: e.toString(),
        );
      },
    );
  }

  void dismiss() {
    _subscription?.cancel();
    _subscription = null;
    state = const BulkEnrollState();
  }

  void cancel() {
    _subscription?.cancel();
    _subscription = null;
    if (state.enrolled > 0) {
      _ref.read(galleryProvider.notifier).refresh();
    }
    state = const BulkEnrollState();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final bulkEnrollProvider =
    StateNotifierProvider<BulkEnrollNotifier, BulkEnrollState>((ref) {
  return BulkEnrollNotifier(ref);
});
