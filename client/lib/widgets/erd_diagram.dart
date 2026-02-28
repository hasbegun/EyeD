import 'package:flutter/material.dart';

import '../models/db_inspector_models.dart';

class ErdDiagram extends StatelessWidget {
  final DbSchemaResponse schema;
  final DbStatsResponse? stats;

  const ErdDiagram({super.key, required this.schema, this.stats});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Find tables by name for layout
    final tables = {for (final t in schema.tables) t.tableName: t};

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats summary
              if (stats != null) ...[
                _StatsBar(stats: stats!),
                const SizedBox(height: 24),
              ],

              // ERD layout: 3 tables in a row with FK arrows described
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tables.containsKey('identities'))
                    _TableCard(schema: tables['identities']!),
                  const SizedBox(width: 32),
                  if (tables.containsKey('templates'))
                    _TableCard(schema: tables['templates']!),
                  const SizedBox(width: 32),
                  if (tables.containsKey('match_log'))
                    _TableCard(schema: tables['match_log']!),
                ],
              ),

              const SizedBox(height: 24),

              // Relationships legend
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Relationships',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final table in schema.tables)
                      for (final fk in table.foreignKeys)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_forward,
                                  size: 14, color: cs.primary),
                              const SizedBox(width: 6),
                              Text(
                                '${table.tableName}.${fk.column}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                '  references  ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '${fk.referencedTable}.${fk.referencedColumn}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final DbStatsResponse stats;

  const _StatsBar({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _StatChip(
          label: 'Identities',
          value: '${stats.identitiesCount}',
          cs: cs,
        ),
        _StatChip(
          label: 'Templates',
          value: '${stats.templatesCount}',
          cs: cs,
        ),
        _StatChip(
          label: 'Match logs',
          value: '${stats.matchLogCount}',
          cs: cs,
        ),
        _StatChip(
          label: 'HE encrypted',
          value: '${stats.heTemplatesCount}',
          cs: cs,
          highlight: stats.heTemplatesCount > 0,
        ),
        _StatChip(
          label: 'Plain NPZ',
          value: '${stats.npzTemplatesCount}',
          cs: cs,
        ),
        _StatChip(
          label: 'DB size',
          value: stats.humanDbSize,
          cs: cs,
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  final bool highlight;

  const _StatChip({
    required this.label,
    required this.value,
    required this.cs,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? cs.primary.withValues(alpha: 0.1)
            : cs.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: highlight ? cs.primary : cs.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: highlight ? cs.primary : cs.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  final TableSchema schema;

  const _TableCard({required this.schema});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table name header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(5),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.table_chart, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  schema.tableName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${schema.rowCount} rows',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),

          // Column list
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: schema.columns.map((col) {
                final isFk = schema.foreignKeys
                    .any((fk) => fk.column == col.name);
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  child: Row(
                    children: [
                      // PK / FK badge
                      if (col.isPrimaryKey)
                        _Badge(label: 'PK', color: cs.primary)
                      else if (isFk)
                        _Badge(label: 'FK', color: cs.tertiary)
                      else
                        const SizedBox(width: 24),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          col.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: col.isPrimaryKey || isFk
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        col.dataType,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (col.nullable) ...[
                        const SizedBox(width: 4),
                        Text(
                          '?',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
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

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
