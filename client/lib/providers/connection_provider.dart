import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gateway_client_provider.dart';

/// Maximum number of automatic reconnect attempts before giving up.
const int maxAutoRetries = 10;

/// Seconds between each auto-reconnect attempt.
const int reconnectCountdownSec = 30;

/// How often to poll health when connected.
const _healthPollInterval = Duration(seconds: 5);

/// Timeout for each health-check request.
const _healthTimeout = Duration(seconds: 3);

enum ConnectionStatus { connected, checking, disconnected }

class AppConnectionState {
  final ConnectionStatus status;

  /// Seconds remaining until next auto-reconnect attempt.
  final int countdownSec;

  /// Number of consecutive failed reconnect attempts.
  final int retryCount;

  /// True when auto-retry has been exhausted (retryCount >= maxAutoRetries).
  final bool autoRetryExhausted;

  const AppConnectionState({
    this.status = ConnectionStatus.checking,
    this.countdownSec = 0,
    this.retryCount = 0,
    this.autoRetryExhausted = false,
  });

  AppConnectionState copyWith({
    ConnectionStatus? status,
    int? countdownSec,
    int? retryCount,
    bool? autoRetryExhausted,
  }) {
    return AppConnectionState(
      status: status ?? this.status,
      countdownSec: countdownSec ?? this.countdownSec,
      retryCount: retryCount ?? this.retryCount,
      autoRetryExhausted: autoRetryExhausted ?? this.autoRetryExhausted,
    );
  }
}

class ConnectionNotifier extends StateNotifier<AppConnectionState> {
  final Ref _ref;
  Timer? _countdownTimer;
  Timer? _healthPollTimer;

  ConnectionNotifier(this._ref) : super(const AppConnectionState()) {
    _checkConnection();
  }

  /// Try the health endpoint with a timeout.
  Future<void> _healthCheck() => _ref
      .read(gatewayClientProvider)
      .checkEngineReady()
      .timeout(_healthTimeout);

  /// Initial connection check on startup.
  Future<void> _checkConnection() async {
    try {
      await _healthCheck();
      _setConnected();
    } catch (_) {
      if (!mounted) return;
      state = AppConnectionState(
        status: ConnectionStatus.disconnected,
        countdownSec: reconnectCountdownSec,
      );
      _startCountdown();
    }
  }

  /// Mark as connected, reset retry state, and begin periodic health polling.
  void _setConnected() {
    _cancelCountdown();
    state = const AppConnectionState(status: ConnectionStatus.connected);
    _startHealthPoll();
  }

  // --- Periodic health poll (while connected) ---

  void _startHealthPoll() {
    _stopHealthPoll();
    _healthPollTimer =
        Timer.periodic(_healthPollInterval, (_) => _pollHealth());
  }

  void _stopHealthPoll() {
    _healthPollTimer?.cancel();
    _healthPollTimer = null;
  }

  Future<void> _pollHealth() async {
    if (!mounted || state.status != ConnectionStatus.connected) return;
    try {
      await _healthCheck();
    } catch (_) {
      if (!mounted || state.status != ConnectionStatus.connected) return;
      // Connection lost — enter reconnect cycle.
      _stopHealthPoll();
      state = AppConnectionState(
        status: ConnectionStatus.disconnected,
        countdownSec: reconnectCountdownSec,
      );
      _startCountdown();
    }
  }

  // --- Countdown timer (while disconnected) ---

  void _startCountdown() {
    _cancelCountdown();
    if (state.autoRetryExhausted) return;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = state.countdownSec - 1;
      if (remaining <= 0) {
        _cancelCountdown();
        reconnect();
      } else {
        state = state.copyWith(countdownSec: remaining);
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  /// Manually or automatically triggered reconnect attempt.
  Future<void> reconnect() async {
    if (state.status == ConnectionStatus.checking) return;

    state = state.copyWith(status: ConnectionStatus.checking);

    try {
      await _healthCheck();
      _setConnected();
    } catch (_) {
      if (!mounted) return;
      final newRetryCount = state.retryCount + 1;
      final exhausted = newRetryCount >= maxAutoRetries;

      state = AppConnectionState(
        status: ConnectionStatus.disconnected,
        countdownSec: exhausted ? 0 : reconnectCountdownSec,
        retryCount: newRetryCount,
        autoRetryExhausted: exhausted,
      );

      if (!exhausted) {
        _startCountdown();
      }
    }
  }

  @override
  void dispose() {
    _cancelCountdown();
    _stopHealthPoll();
    super.dispose();
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, AppConnectionState>((ref) {
  return ConnectionNotifier(ref);
});
