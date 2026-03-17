import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dataset.dart';
import '../providers/gateway_client_provider.dart';
import '../providers/health_provider.dart';
import '../theme/eyed_theme.dart';
import '../widgets/status_indicator.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final gatewayAsync = ref.watch(gatewayHealthProvider);
    final engineAsync = ref.watch(engineHealthProvider);
    final gateway = gatewayAsync.valueOrNull;
    final engine = engineAsync.valueOrNull;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.admin,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.pollingEvery5s,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),

        Expanded(
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              // Gateway card
              _ServiceCard(
                title: l10n.serviceGateway,
                connected: gateway != null,
                error: gateway == null ? l10n.unreachable : null,
                rows: gateway != null
                    ? [
                        _Row(l10n.alive, gateway.alive),
                        _Row(l10n.ready, gateway.ready),
                        _Row(l10n.nats, gateway.natsConnected),
                        _Row(
                          l10n.circuitBreaker,
                          gateway.circuitBreaker,
                          colorKey: gateway.circuitBreaker,
                        ),
                        _Row(l10n.version, gateway.version),
                      ]
                    : [],
              ),

              // Iris Engine card
              _ServiceCard(
                title: l10n.serviceIrisEngine,
                connected: engine != null,
                error: engine == null ? l10n.unreachable : null,
                rows: engine != null
                    ? [
                        _Row(l10n.alive, engine.alive),
                        _Row(l10n.ready, engine.ready),
                        _Row(l10n.pipeline, engine.pipelineLoaded),
                        _Row(l10n.nats, engine.natsConnected),
                        _Row(l10n.gallerySize, engine.gallerySize),
                        _Row(l10n.database, engine.dbConnected),
                        _Row(l10n.version, engine.version),
                      ]
                    : [],
              ),

              // NATS card
              _ServiceCard(
                title: l10n.serviceNats,
                connected: gateway?.natsConnected ?? false,
                rows: [
                  _Row(l10n.status,
                      gateway?.natsConnected == true ? l10n.connected : l10n.unknown),
                  _Row(l10n.clientPort, l10n.natsClientPortInfo),
                  _Row(l10n.monitorPort, l10n.natsMonitorPortInfo),
                ],
              ),

              // Dataset paths card
              const _DatasetPathsCard(),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row {
  final String label;
  final dynamic value;
  final String? colorKey;

  const _Row(this.label, this.value, {this.colorKey});
}

class _ServiceCard extends StatelessWidget {
  final String title;
  final bool connected;
  final String? error;
  final List<_Row> rows;

  const _ServiceCard({
    required this.title,
    required this.connected,
    this.error,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;

    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                StatusIndicator(connected: connected),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),

          // Error
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error!,
                style: TextStyle(color: cs.error, fontSize: 13),
              ),
            ),

          // Rows
          if (rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(1.5),
                },
                children: rows.map((row) {
                  final valueStr = row.value is bool
                      ? (row.value as bool ? 'true' : 'false')
                      : row.value.toString();

                  Color valueColor;
                  if (row.colorKey != null) {
                    valueColor = switch (row.colorKey) {
                      'closed' => semantic.success,
                      'open' => cs.error,
                      _ => semantic.warning,
                    };
                  } else if (row.value is bool) {
                    valueColor =
                        row.value as bool ? semantic.success : cs.error;
                  } else {
                    valueColor = cs.onSurface;
                  }

                  return TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          row.label,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          valueStr,
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                            color: valueColor,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _DatasetPathsCard extends ConsumerStatefulWidget {
  const _DatasetPathsCard();

  @override
  ConsumerState<_DatasetPathsCard> createState() => _DatasetPathsCardState();
}

class _DatasetPathsCardState extends ConsumerState<_DatasetPathsCard> {
  List<DatasetPathInfo>? _paths;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPaths();
  }

  Future<void> _loadPaths() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(gatewayClientProvider);
      final paths = await client.listDatasetPaths();
      setState(() {
        _paths = paths;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addPath(String path) async {
    try {
      final client = ref.read(gatewayClientProvider);
      await client.addDatasetPath(path);
      await _loadPaths();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _removePath(String path) async {
    try {
      final client = ref.read(gatewayClientProvider);
      await client.removeDatasetPath(path);
      await _loadPaths();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _showAddDialog() {
    final controller = TextEditingController();
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.addDirectory),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
          ),
          decoration: InputDecoration(
            hintText: l10n.enterAbsolutePath,
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(ctx).pop();
              _addPath(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.of(ctx).pop();
                _addPath(value);
              }
            },
            child: Text(l10n.add),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.datasetPaths,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.add, size: 18, color: cs.onSurface),
                  onPressed: _showAddDialog,
                  tooltip: l10n.addDirectory,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(Icons.refresh,
                      size: 18, color: cs.onSurface),
                  onPressed: _loadPaths,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: cs.error, fontSize: 13),
              ),
            ),

          if (_paths != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: _paths!.asMap().entries.map((entry) {
                  final i = entry.key;
                  final p = entry.value;
                  final isPrimary = i == 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: isPrimary
                                ? cs.primary.withValues(alpha: 0.2)
                                : cs.onSurfaceVariant.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            isPrimary
                                ? l10n.datasetPathsPrimary
                                : l10n.datasetPathsExtra,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isPrimary
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.path,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p.exists
                                    ? l10n.datasetsCount(p.datasetCount)
                                    : l10n.directoryNotFound,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: p.exists
                                      ? cs.onSurfaceVariant
                                      : cs.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isPrimary)
                          IconButton(
                            icon: Icon(Icons.close,
                                size: 14, color: cs.onSurfaceVariant),
                            onPressed: () => _removePath(p.path),
                            tooltip: l10n.remove,
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
