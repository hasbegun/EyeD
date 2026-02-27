import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/dashboard_provider.dart';
import '../theme/eyed_theme.dart';
import '../widgets/result_row.dart';
import '../widgets/stat_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final stats = ref.watch(dashboardStatsProvider);
    final results = ref.watch(dashboardResultsProvider);
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.dashboard,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 20),

        // Stat cards
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: l10n.framesProcessed,
                value: stats.total.toString(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: l10n.matches,
                value: stats.matches.toString(),
                valueColor: semantic.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: l10n.errors,
                value: stats.errors.toString(),
                valueColor: cs.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Live results heading
        Text(
          l10n.liveResults,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),

        // Results feed
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: results.isEmpty
                ? Center(
                    child: Text(
                      l10n.waitingForResults,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: results.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: cs.outlineVariant),
                    itemBuilder: (context, index) {
                      return ResultRow(result: results[index]);
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
