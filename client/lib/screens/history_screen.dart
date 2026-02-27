import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/history_provider.dart';
import '../widgets/result_row.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _filter = 'all';
  String _search = '';

  List<HistoryEntry> _applyFilters(List<HistoryEntry> entries) {
    var filtered = entries;

    // Status filter
    if (_filter == 'match') {
      filtered =
          filtered.where((e) => e.result.match?.isMatch == true).toList();
    } else if (_filter == 'no-match') {
      filtered = filtered
          .where((e) =>
              e.result.error == null && e.result.match?.isMatch != true)
          .toList();
    } else if (_filter == 'error') {
      filtered = filtered.where((e) => e.result.error != null).toList();
    }

    // Search
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      filtered = filtered.where((e) {
        final r = e.result;
        return r.deviceId.toLowerCase().contains(q) ||
            r.frameId.toLowerCase().contains(q) ||
            (r.match?.matchedIdentityId?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(historyProvider);
    final filtered = _applyFilters(history);
    final cs = Theme.of(context).colorScheme;

    final filterLabels = {
      'all': l10n.filterAll,
      'match': l10n.filterMatch,
      'no-match': l10n.filterNoMatch,
      'error': l10n.filterError,
    };

    final headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: cs.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.history,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 20),

        // Toolbar
        Row(
          children: [
            for (final f in filterLabels.keys)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(filterLabels[f]!),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 36,
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: l10n.searchPlaceholder,
                    prefixIcon: const Icon(Icons.search, size: 18),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${filtered.length} / ${history.length}',
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(6)),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              SizedBox(
                  width: 60,
                  child: Text(l10n.headerTime,
                      style: headerStyle)),
              SizedBox(
                  width: 100,
                  child: Text(l10n.headerDevice,
                      style: headerStyle)),
              SizedBox(
                  width: 80,
                  child: Text(l10n.headerFrame,
                      style: headerStyle)),
              SizedBox(
                  width: 80,
                  child: Text(l10n.headerHd,
                      style: headerStyle)),
              Expanded(
                  child: Text(l10n.headerStatus,
                      style: headerStyle)),
              SizedBox(
                  width: 70,
                  child: Text(l10n.headerLatency,
                      style: headerStyle,
                      textAlign: TextAlign.end)),
            ],
          ),
        ),

        // Results
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(6)),
              border: Border(
                left: BorderSide(color: cs.outlineVariant),
                right: BorderSide(color: cs.outlineVariant),
                bottom: BorderSide(color: cs.outlineVariant),
              ),
            ),
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      l10n.noResultsMatchFilter,
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 14),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: cs.outlineVariant),
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      final time =
                          '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}';
                      return ResultRow(
                          result: entry.result, timeLabel: time);
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
