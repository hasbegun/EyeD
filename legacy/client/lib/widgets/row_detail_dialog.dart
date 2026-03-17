import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/db_inspector_models.dart';
import '../providers/gateway_client_provider.dart';
import 'bytea_info_card.dart';

class RowDetailDialog extends ConsumerStatefulWidget {
  final String tableName;
  final String rowId;

  const RowDetailDialog({
    super.key,
    required this.tableName,
    required this.rowId,
  });

  @override
  ConsumerState<RowDetailDialog> createState() => _RowDetailDialogState();
}

class _RowDetailDialogState extends ConsumerState<RowDetailDialog> {
  RowDetailResponse? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await ref
          .read(gatewayClientProvider)
          .getRowDetail(widget.tableName, widget.rowId);
      if (mounted) setState(() { _detail = detail; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.tableName} / ${widget.rowId}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),

            // Body
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: TextStyle(color: cs.error)),
              )
            else if (_detail != null)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildDetail(context, _detail!),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetail(BuildContext context, RowDetailResponse detail) {
    final cs = Theme.of(context).colorScheme;
    final fields = <Widget>[];

    for (final entry in detail.row.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is Map<String, dynamic> && value.containsKey('size_bytes')) {
        // This is a ByteaInfo
        final info = ByteaInfo.fromJson(value);
        fields.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ByteaInfoCard(columnName: key, info: info),
        ));
      } else {
        fields.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: Text(
                  key,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: value != null
                      ? () {
                          Clipboard.setData(
                              ClipboardData(text: value.toString()));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Copied $key'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        }
                      : null,
                  child: Text(
                    value?.toString() ?? 'NULL',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: value == null
                          ? cs.onSurfaceVariant
                          : cs.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ));
      }
    }

    // Related data
    if (detail.related != null && detail.related!.isNotEmpty) {
      fields.add(const SizedBox(height: 12));
      fields.add(Text(
        'Related data',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
      ));
      fields.add(const SizedBox(height: 8));

      for (final relEntry in detail.related!.entries) {
        final relData = relEntry.value as Map<String, dynamic>;
        fields.add(Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                relEntry.key,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 6),
              for (final field in relData.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          field.key,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          field.value?.toString() ?? 'NULL',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fields,
    );
  }
}
