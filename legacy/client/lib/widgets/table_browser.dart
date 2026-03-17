import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/db_inspector_models.dart';
import '../providers/db_inspector_provider.dart';
import 'bytea_info_card.dart';
import 'row_detail_dialog.dart';

class TableBrowser extends ConsumerWidget {
  final List<String> tableNames;

  const TableBrowser({super.key, required this.tableNames});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final state = ref.watch(tableBrowserProvider);
    final notifier = ref.read(tableBrowserProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar: table selector + refresh
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Table dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: state.selectedTable,
                    hint: Text(
                      'Select table...',
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    items: tableNames.map((t) {
                      return DropdownMenuItem(
                        value: t,
                        child: Text(
                          t,
                          style: TextStyle(
                            fontSize: 14,
                            fontFamily: 'monospace',
                            color: cs.onSurface,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) notifier.selectTable(v);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (state.selectedTable != null)
                IconButton(
                  icon: Icon(Icons.refresh, size: 18, color: cs.onSurfaceVariant),
                  onPressed: () => notifier.refresh(),
                  tooltip: 'Refresh',
                ),
              const Spacer(),
              if (state.response != null)
                Text(
                  '${state.response!.totalCount} rows total',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),

        // Content
        if (state.loading)
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.error != null)
          Expanded(
            child: Center(
              child: Text(state.error!, style: TextStyle(color: cs.error)),
            ),
          )
        else if (state.response != null)
          Expanded(
            child: _DataTableView(
              response: state.response!,
              offset: state.offset,
              onRowTap: (rowId) => _showRowDetail(context, state.selectedTable!, rowId),
              onPageChange: (offset) => notifier.goToPage(offset),
            ),
          )
        else
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.table_chart_outlined, size: 48, color: cs.outlineVariant),
                  const SizedBox(height: 12),
                  Text(
                    'Select a table to browse rows',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showRowDetail(BuildContext context, String tableName, String rowId) {
    showDialog(
      context: context,
      builder: (_) => RowDetailDialog(tableName: tableName, rowId: rowId),
    );
  }
}

class _DataTableView extends StatelessWidget {
  final TableRowsResponse response;
  final int offset;
  final void Function(String rowId) onRowTap;
  final void Function(int offset) onPageChange;

  const _DataTableView({
    required this.response,
    required this.offset,
    required this.onRowTap,
    required this.onPageChange,
  });

  /// Determine the primary key column for this table to use as row ID.
  String _pkColumn(String tableName) {
    switch (tableName) {
      case 'identities':
        return 'identity_id';
      case 'templates':
        return 'template_id';
      case 'match_log':
        return 'log_id';
      default:
        return response.columns.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pkCol = _pkColumn(response.tableName);
    const pageSize = 50;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  cs.surfaceContainer,
                ),
                dataRowMinHeight: 36,
                dataRowMaxHeight: 48,
                columnSpacing: 24,
                horizontalMargin: 16,
                columns: response.columns.map((col) {
                  return DataColumn(
                    label: Text(
                      col,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  );
                }).toList(),
                rows: response.rows.map((row) {
                  final rowId = row[pkCol]?.toString() ?? '';
                  return DataRow(
                    onSelectChanged: (_) => onRowTap(rowId),
                    cells: response.columns.map((col) {
                      final value = row[col];
                      return DataCell(_cellWidget(value, cs));
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
          ),
        ),

        // Pagination bar
        Divider(height: 1, color: cs.outlineVariant),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                'Showing ${offset + 1}–${offset + response.rows.length} of ${response.totalCount}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 18),
                onPressed: offset > 0
                    ? () => onPageChange((offset - pageSize).clamp(0, response.totalCount))
                    : null,
                tooltip: 'Previous',
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 18),
                onPressed: response.hasMore
                    ? () => onPageChange(offset + pageSize)
                    : null,
                tooltip: 'Next',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cellWidget(dynamic value, ColorScheme cs) {
    if (value == null) {
      return Text(
        'NULL',
        style: TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          fontStyle: FontStyle.italic,
          color: cs.onSurfaceVariant,
        ),
      );
    }

    // BYTEA metadata rendered as a chip
    if (value is Map<String, dynamic> && value.containsKey('size_bytes')) {
      return ByteaChip(info: ByteaInfo.fromJson(value));
    }

    final text = value.toString();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          color: cs.onSurface,
        ),
      ),
    );
  }
}
