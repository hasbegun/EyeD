import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/bulk_enroll_provider.dart';
import '../services/bulk_directory_picker.dart';

class BulkTab extends ConsumerWidget {
  const BulkTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final st = ref.watch(bulkEnrollProvider);
    final notifier = ref.read(bulkEnrollProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Directory picker
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: st.running
                        ? null
                        : () async {
                            if (kIsWeb) {
                              final pickedFiles = await pickBulkDirectoryFiles();
                              if (pickedFiles.isNotEmpty) {
                                final root = pickedFiles.first.relativePath.split('/').first;
                                await notifier.scanPickedFiles(
                                  pickedFiles,
                                  selectedLabel: root,
                                );
                              }
                            } else {
                              final dir =
                                  await FilePicker.platform.getDirectoryPath();
                              if (dir != null) {
                                await notifier.scanDirectory(dir);
                              }
                            }
                          },
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: Text(l.bulkSelectDir),
                  ),
                  const SizedBox(width: 12),
                  if (st.selectedDir != null)
                    Expanded(
                      child: Text(
                        st.selectedDir!,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Subject count
              if (st.subjects.isNotEmpty && !st.running && st.idle)
                Text(
                  '${st.subjects.length} subjects found',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              if (st.selectedDir != null && st.subjects.isEmpty && !st.running)
                Text(
                  l.bulkNoSubjects,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.orange),
                ),

              const SizedBox(height: 16),

              // Start / Cancel button
              SizedBox(
                height: 48,
                child: st.running
                    ? FilledButton(
                        onPressed: notifier.cancel,
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700),
                        child: const Text('Cancel'),
                      )
                    : FilledButton(
                        onPressed: st.subjects.isNotEmpty && !st.done
                            ? () => notifier.start()
                            : null,
                        child: Text(l.bulkStart),
                      ),
              ),
              const SizedBox(height: 24),

              // Progress
              if (st.running || st.done) ...[
                if (st.running)
                  LinearProgressIndicator(
                    value: st.total > 0 ? st.current / st.total : null,
                  ),
                const SizedBox(height: 12),
                if (st.running)
                  Text(
                    l.bulkRunning(st.current, st.total),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                if (st.done)
                  Text(
                    l.bulkComplete(st.enrolled, st.total, st.skipped, st.errors),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                  ),
                const SizedBox(height: 8),
                _StatRow('Enrolled', st.enrolled, Colors.green),
                _StatRow('Skipped', st.skipped, Colors.orange),
                _StatRow('Errors', st.errors, Colors.red),
              ],

              if (st.idle && st.selectedDir == null)
                Expanded(
                  child: Center(
                    child: Text(
                      l.bulkIdle,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ),
                ),

              // Reset if done
              if (st.done) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: notifier.reset,
                  child: const Text('Reset'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text('$label: $value'),
        ],
      ),
    );
  }
}
