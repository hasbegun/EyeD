import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.notFoundCode,
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.pageNotFound,
            style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
