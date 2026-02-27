import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_provider.dart';

class ConnectionOverlay extends ConsumerWidget {
  const ConnectionOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);

    if (conn.status == ConnectionStatus.connected) {
      return const SizedBox.shrink();
    }

    // Show overlay for disconnected and initial checking states.
    // But skip for checking state on first load (retryCount == 0 and status == checking).
    if (conn.status == ConnectionStatus.checking && conn.retryCount == 0) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isChecking = conn.status == ConnectionStatus.checking;

    return Container(
      color: cs.scrim.withValues(alpha: 0.5),
      child: Center(
        child: Card(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: 48,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.connectionLost,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.connectionLostDesc,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 200,
                  child: ElevatedButton.icon(
                    onPressed: isChecking
                        ? null
                        : () => ref
                            .read(connectionProvider.notifier)
                            .reconnect(),
                    icon: isChecking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(_buttonLabel(l10n, conn, isChecking)),
                  ),
                ),
                if (conn.retryCount > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.connectionRetryCount(
                      conn.retryCount,
                      maxAutoRetries,
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buttonLabel(
    AppLocalizations l10n,
    AppConnectionState conn,
    bool isChecking,
  ) {
    if (isChecking) return l10n.reconnecting;
    if (conn.autoRetryExhausted) return l10n.reconnect;
    if (conn.countdownSec > 0) {
      return l10n.reconnectCountdown(conn.countdownSec);
    }
    return l10n.reconnect;
  }
}
