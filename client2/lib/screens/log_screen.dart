import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/log_provider.dart';

class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  String _filter = 'all';
  String _search = '';

  List<LogEntry> _applyFilters(List<LogEntry> entries) {
    var filtered = entries;

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

    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      filtered = filtered.where((e) {
        final r = e.result;
        return (e.fileName?.toLowerCase().contains(q) ?? false) ||
            (r.match?.matchedIdentityId?.toLowerCase().contains(q) ?? false) ||
            (r.match?.matchedIdentityName?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final log = ref.watch(logProvider);
    final filtered = _applyFilters(log);
    final cs = Theme.of(context).colorScheme;

    final filterLabels = {
      'all': l.logFilterAll,
      'match': l.logFilterMatch,
      'no-match': l.logFilterNoMatch,
      'error': l.logFilterError,
    };

    final headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: cs.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                      hintText: l.logSearchPlaceholder,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${filtered.length} / ${log.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: l.logClear,
                onPressed: log.isEmpty
                    ? null
                    : () => ref.read(logProvider.notifier).clear(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(6)),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                SizedBox(width: 60, child: Text(l.logHeaderTime, style: headerStyle)),
                SizedBox(width: 80, child: Text(l.logHeaderHd, style: headerStyle)),
                Expanded(child: Text(l.logHeaderStatus, style: headerStyle)),
                SizedBox(
                  width: 70,
                  child: Text(l.logHeaderLatency,
                      style: headerStyle, textAlign: TextAlign.end),
                ),
              ],
            ),
          ),

          // Results
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: cs.outlineVariant),
                  right: BorderSide(color: cs.outlineVariant),
                  bottom: BorderSide(color: cs.outlineVariant),
                ),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(6)),
              ),
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        l.logEmpty,
                        style:
                            TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: cs.outlineVariant),
                      itemBuilder: (context, index) {
                        return _LogRow(entry: filtered[index]);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final LogEntry entry;

  const _LogRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = entry.result;
    final ts = entry.timestamp;
    final time =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';

    final Color borderColor;
    final String statusText;
    String hdText = '-';

    if (r.error != null) {
      borderColor = cs.error;
      statusText = 'Error: ${r.error}';
    } else if (r.match == null) {
      borderColor = Colors.orange;
      statusText = 'No match data';
    } else {
      hdText = r.match!.hammingDistance.toStringAsFixed(4);
      if (r.match!.isMatch) {
        borderColor = Colors.green;
        final name = r.match!.matchedIdentityName ?? r.match!.matchedIdentityId ?? '?';
        statusText = 'Match: $name';
      } else {
        borderColor = Colors.orange;
        statusText = 'No match';
      }
    }

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
          SizedBox(width: 60, child: Text(time, style: mono)),
          SizedBox(width: 80, child: Text(hdText, style: mono)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  statusText,
                  style: TextStyle(fontSize: 13, color: borderColor),
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.fileName != null)
                  Text(
                    entry.fileName!,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '${r.latencyMs.round()}ms',
              style: mono,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
