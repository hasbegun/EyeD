import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

import '../theme/eyed_theme.dart';

class StatusIndicator extends StatelessWidget {
  final bool connected;
  final String? label;

  const StatusIndicator({super.key, required this.connected, this.label});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: connected ? semantic.success : cs.error,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label ?? (connected ? l10n.connected : l10n.disconnected),
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
