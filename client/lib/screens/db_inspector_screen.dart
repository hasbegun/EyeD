import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/db_inspector_provider.dart';
import '../widgets/erd_diagram.dart';
import '../widgets/he_verification_guide.dart';
import '../widgets/table_browser.dart';

class DbInspectorScreen extends ConsumerStatefulWidget {
  const DbInspectorScreen({super.key});

  @override
  ConsumerState<DbInspectorScreen> createState() => _DbInspectorScreenState();
}

class _DbInspectorScreenState extends ConsumerState<DbInspectorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Tab bar
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(
                  children: [
                    Icon(Icons.storage_outlined, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      l10n.dbInspector,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelStyle: const TextStyle(fontSize: 14),
                  tabs: [
                    Tab(text: l10n.dbSchema),
                    Tab(text: l10n.dbBrowse),
                    Tab(text: l10n.dbHeGuide),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _SchemaTab(),
              _BrowseTab(),
              const HeVerificationGuide(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SchemaTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final schemaAsync = ref.watch(dbSchemaProvider);
    final statsAsync = ref.watch(dbStatsProvider);

    return schemaAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 36, color: cs.error),
            const SizedBox(height: 8),
            Text(
              e.toString(),
              style: TextStyle(color: cs.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              onPressed: () {
                ref.invalidate(dbSchemaProvider);
                ref.invalidate(dbStatsProvider);
              },
            ),
          ],
        ),
      ),
      data: (schema) => ErdDiagram(
        schema: schema,
        stats: statsAsync.valueOrNull,
      ),
    );
  }
}

class _BrowseTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schemaAsync = ref.watch(dbSchemaProvider);

    return schemaAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (schema) => TableBrowser(
        tableNames: schema.tables.map((t) => t.tableName).toList(),
      ),
    );
  }
}
