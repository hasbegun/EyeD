import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

import '../models/analyze_result.dart';
import '../theme/eyed_theme.dart';

class ResultRow extends StatelessWidget {
  final AnalyzeResult result;
  final String? timeLabel;

  const ResultRow({super.key, required this.result, this.timeLabel});

  String _statusText(AppLocalizations l10n) {
    if (result.error != null) return l10n.errorPrefix(result.error!);
    if (result.match == null) return l10n.noMatchData;
    if (result.match!.isMatch) {
      return l10n.matchIdentity(result.match!.matchedIdentityId ?? "?");
    }
    return l10n.noMatch;
  }

  String get _hdText {
    if (result.match == null) return '-';
    return result.match!.hammingDistance.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;

    final borderColor = result.error != null
        ? cs.error
        : result.match?.isMatch == true
            ? semantic.success
            : semantic.warning;

    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      color: cs.onSurfaceVariant,
    );

    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: borderColor, width: 3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (timeLabel != null)
            SizedBox(width: 60, child: Text(timeLabel!, style: mono)),
          SizedBox(
            width: 100,
            child: Text(
              result.deviceId,
              style: mono,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(result.frameId, style: mono, overflow: TextOverflow.ellipsis),
          ),
          SizedBox(width: 80, child: Text(_hdText, style: mono)),
          Expanded(
            child: Text(
              _statusText(l10n),
              style: TextStyle(
                fontSize: 13,
                color: borderColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '${result.latencyMs.round()}ms',
              style: mono,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
