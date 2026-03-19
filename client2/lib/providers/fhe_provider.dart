import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client_provider.dart';

/// Immutable snapshot of FHE toggle state returned by GET /config.
class FheState {
  final bool fheEnabled;
  final bool fheActive;
  final bool isToggling;

  const FheState({
    required this.fheEnabled,
    required this.fheActive,
    this.isToggling = false,
  });

  FheState copyWith({bool? fheEnabled, bool? fheActive, bool? isToggling}) =>
      FheState(
        fheEnabled: fheEnabled ?? this.fheEnabled,
        fheActive: fheActive ?? this.fheActive,
        isToggling: isToggling ?? this.isToggling,
      );
}

/// Manages FHE toggle state by calling GET /config (load) and
/// POST /config/fhe (toggle).  Only used in dev/test — in prod the widget
/// tree never renders the toggle so this provider is never initialised.
class FheNotifier extends StateNotifier<AsyncValue<FheState>> {
  final Ref _ref;

  FheNotifier(this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final data = await _ref.read(apiClientProvider).getConfig();
      state = AsyncValue.data(FheState(
        fheEnabled: data['fhe_enabled'] as bool? ?? true,
        fheActive:  data['fhe_active']  as bool? ?? true,
      ));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Sends POST /config/fhe.  Optimistically marks [isToggling] while the
  /// request is in-flight, then commits the server-confirmed state.
  /// Reverts [isToggling] on error and rethrows so callers can show a SnackBar.
  Future<void> toggle(bool enabled) async {
    final current = state.valueOrNull;
    if (current == null) return;

    state = AsyncValue.data(current.copyWith(isToggling: true));
    try {
      final result = await _ref.read(apiClientProvider).toggleFhe(enabled);
      state = AsyncValue.data(FheState(
        fheEnabled: result['fhe_enabled'] as bool? ?? enabled,
        fheActive:  result['fhe_active']  as bool? ?? current.fheActive,
      ));
    } catch (e, st) {
      state = AsyncValue.data(current.copyWith(isToggling: false));
      Error.throwWithStackTrace(e, st);
    }
  }

  /// Refreshes state from the server (e.g. after a hot restart in dev).
  Future<void> refresh() => _load();
}

final fheProvider =
    StateNotifierProvider<FheNotifier, AsyncValue<FheState>>((ref) {
  return FheNotifier(ref);
});
