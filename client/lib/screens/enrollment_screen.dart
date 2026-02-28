import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enrollment.dart';
import '../providers/bulk_enroll_provider.dart';
import '../providers/dataset_provider.dart';
import '../providers/gallery_provider.dart';
import '../providers/gateway_client_provider.dart';
import '../providers/individual_enroll_provider.dart';
import '../providers/local_bulk_enroll_provider.dart';
import '../services/gateway_client.dart';
import '../theme/eyed_theme.dart';
import '../widgets/dataset_browser.dart';

/// Remembers the last directory used by any file picker on this screen.
final _lastPickerDirectoryProvider = StateProvider<String?>((ref) => null);

class EnrollmentScreen extends ConsumerStatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  ConsumerState<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends ConsumerState<EnrollmentScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header bar
        Row(
          children: [
            Icon(Icons.person_add_alt_1, size: 22, color: cs.primary),
            const SizedBox(width: 10),
            Text(
              l10n.enrollment,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: l10n.individualEnroll),
                  Tab(text: l10n.bulkEnrollTab),
                  Tab(text: l10n.galleryTab),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _IndividualEnrollTab(),
              _BulkEnrollTab(),
              _GalleryTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Tab 1: Individual Enroll
// =============================================================================

class _IndividualEnrollTab extends ConsumerStatefulWidget {
  const _IndividualEnrollTab();

  @override
  ConsumerState<_IndividualEnrollTab> createState() =>
      _IndividualEnrollTabState();
}

class _IndividualEnrollTabState extends ConsumerState<_IndividualEnrollTab>
    with AutomaticKeepAliveClientMixin {
  final _nameController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(individualEnrollProvider);
    final notifier = ref.read(individualEnrollProvider.notifier);

    // Keep text controller in sync
    if (_nameController.text != s.identityName) {
      _nameController.text = s.identityName;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eye image pickers
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _EyeImagePicker(
                  label: l10n.leftEye,
                  imageBytes: s.leftImageBytes,
                  imageName: s.leftImageName,
                  isNA: s.leftIsNA,
                  onPick: (bytes, name) => notifier.setLeftImage(bytes, name),
                  onToggleNA: notifier.toggleLeftNA,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _EyeImagePicker(
                  label: l10n.rightEye,
                  imageBytes: s.rightImageBytes,
                  imageName: s.rightImageName,
                  isNA: s.rightIsNA,
                  onPick: (bytes, name) => notifier.setRightImage(bytes, name),
                  onToggleNA: notifier.toggleRightNA,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Identity name
          SizedBox(
            width: 400,
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: l10n.identityName,
                prefixIcon: const Icon(Icons.badge_outlined, size: 18),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: notifier.setIdentityName,
            ),
          ),

          const SizedBox(height: 16),

          // Enroll button
          ElevatedButton.icon(
            onPressed: s.canEnroll ? () => notifier.enroll() : null,
            icon: s.enrolling
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.how_to_reg, size: 18),
            label: Text(l10n.enroll),
          ),

          const SizedBox(height: 16),

          // Results / errors
          for (final result in s.results) ...[
            _IndividualResultMessage(result: result),
            const SizedBox(height: 8),
          ],
          if (s.error != null)
            _ErrorBanner(
              message: s.error!.contains('segmentation') ||
                      s.error!.contains('Segmentation') ||
                      s.error!.contains('no template')
                  ? l10n.segmentationFailed
                  : l10n.errorPrefix(s.error!),
            ),
        ],
      ),
    );
  }
}

class _EyeImagePicker extends ConsumerWidget {
  final String label;
  final dynamic imageBytes; // Uint8List?
  final String? imageName;
  final bool isNA;
  final void Function(dynamic bytes, String name) onPick;
  final void Function(bool) onToggleNA;

  const _EyeImagePicker({
    required this.label,
    required this.imageBytes,
    required this.imageName,
    required this.isNA,
    required this.onPick,
    required this.onToggleNA,
  });

  Future<void> _pickImage(WidgetRef ref) async {
    final initialDir = ref.read(_lastPickerDirectoryProvider);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      initialDirectory: initialDir,
    );
    if (result != null && result.files.single.bytes != null) {
      final picked = result.files.single;
      // Remember the parent directory for next time
      if (picked.path != null) {
        final dir = picked.path!.substring(0, picked.path!.lastIndexOf('/'));
        ref.read(_lastPickerDirectoryProvider.notifier).state = dir;
      }
      onPick(picked.bytes!, picked.name);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),

        // Image area
        Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            color: isNA
                ? cs.surfaceContainerHighest.withValues(alpha: 0.5)
                : cs.surfaceContainer,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: isNA
              ? Center(
                  child: Text(
                    l10n.notApplicable,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 16,
                    ),
                  ),
                )
              : imageBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.memory(
                        imageBytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    )
                  : Center(
                      child: Icon(
                        Icons.visibility_outlined,
                        size: 48,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                    ),
        ),
        const SizedBox(height: 8),

        if (imageName != null && !isNA)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              imageName!,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),

        // Controls
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: isNA ? null : () => _pickImage(ref),
              icon: const Icon(Icons.folder_open, size: 16),
              label: Text(l10n.loadFromDisk),
            ),
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 20,
                  width: 20,
                  child: Checkbox(
                    value: isNA,
                    onChanged: (v) => onToggleNA(v ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.notApplicable,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _IndividualResultMessage extends StatelessWidget {
  final EnrollResponse result;

  const _IndividualResultMessage({required this.result});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;
    final cs = Theme.of(context).colorScheme;

    if (result.error != null) {
      final msg = result.error!.contains('segmentation') ||
              result.error!.contains('Segmentation') ||
              result.error!.contains('no template')
          ? l10n.segmentationFailed
          : l10n.errorPrefix(result.error!);
      return _StatusBanner(color: cs.error, text: msg);
    }

    if (result.isDuplicate) {
      final name =
          result.duplicateIdentityName ?? result.duplicateIdentityId ?? '?';
      return _StatusBanner(
        color: semantic.warning,
        text: l10n.duplicateUserDetected(name),
      );
    }

    return _StatusBanner(
      color: semantic.success,
      text: l10n.enrollSuccess(1),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final Color color;
  final String text;

  const _StatusBanner({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 13),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _StatusBanner(color: cs.error, text: message);
  }
}

// =============================================================================
// Tab 2: Bulk Enroll
// =============================================================================

class _BulkEnrollTab extends ConsumerStatefulWidget {
  const _BulkEnrollTab();

  @override
  ConsumerState<_BulkEnrollTab> createState() => _BulkEnrollTabState();
}

class _BulkEnrollTabState extends ConsumerState<_BulkEnrollTab>
    with AutomaticKeepAliveClientMixin {
  final _bulkSubjectController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _bulkSubjectController.dispose();
    super.dispose();
  }

  void _startBulkEnroll(String dataset) {
    final subjectText = _bulkSubjectController.text.trim();
    List<String>? subjects;
    if (subjectText.isNotEmpty) {
      subjects = subjectText
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    ref.read(bulkEnrollProvider.notifier).start(
          dataset: dataset,
          subjects: subjects,
        );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section A: Local directory bulk
          _LocalBulkSection(),

          const SizedBox(height: 24),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: 16),

          // Section B: Server-side bulk (existing)
          Text(
            l10n.serverBulkEnroll,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),

          Consumer(
            builder: (context, ref, _) {
              final browser = ref.watch(enrollmentBrowserProvider);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 280,
                    child:
                        DatasetBrowser(provider: enrollmentBrowserProvider),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _BulkEnrollPanel(
                      dataset: browser.selectedDataset,
                      subjectController: _bulkSubjectController,
                      onStart: browser.selectedDataset.isNotEmpty
                          ? () => _startBulkEnroll(browser.selectedDataset)
                          : null,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LocalBulkSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;
    final s = ref.watch(localBulkEnrollProvider);
    final notifier = ref.read(localBulkEnrollProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Text(
          l10n.localBulkEnroll,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),

        // Select directory
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: s.enrolling
                  ? null
                  : () async {
                      final initialDir = ref.read(_lastPickerDirectoryProvider);
                      final path =
                          await FilePicker.platform.getDirectoryPath(
                        initialDirectory: initialDir,
                      );
                      if (path != null) {
                        ref.read(_lastPickerDirectoryProvider.notifier).state = path;
                        notifier.scanDirectory(path);
                      }
                    },
              icon: const Icon(Icons.folder_open, size: 16),
              label: Text(l10n.selectLocalDirectory),
            ),
            if (s.directoryPath != null) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  s.directoryPath!,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: cs.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),

        if (s.scanning) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(l10n.scanningDirectory,
                  style:
                      TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ],
          ),
        ],

        // Subject preview
        if (s.subjects.isNotEmpty && !s.scanning) ...[
          const SizedBox(height: 12),
          Text(
            l10n.subjectsFound(s.subjects.length),
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(6),
              itemCount: s.subjects.length,
              itemBuilder: (_, i) {
                final sub = s.subjects[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text(
                          sub.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: cs.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (sub.leftImagePath != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: cs.primary.withValues(alpha: 0.2),
                          ),
                          child: Text(l10n.eyeSideShortLeft,
                              style: TextStyle(
                                  fontSize: 10, color: cs.primary)),
                        ),
                      const SizedBox(width: 4),
                      if (sub.rightImagePath != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color:
                                semantic.success.withValues(alpha: 0.2),
                          ),
                          child: Text(l10n.eyeSideShortRight,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: semantic.success)),
                        ),
                      if (!sub.hasImages)
                        Text(
                          l10n.noImages,
                          style:
                              TextStyle(fontSize: 10, color: cs.error),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Start button
          if (!s.enrolling && !s.done)
            ElevatedButton.icon(
              onPressed:
                  s.subjects.where((s) => s.hasImages).isEmpty
                      ? null
                      : () => notifier.startEnroll(),
              icon: const Icon(Icons.play_arrow, size: 16),
              label: Text(l10n.startEnroll),
            ),
        ],

        // Enrolling progress
        if (s.enrolling) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: s.subjects.isNotEmpty
                ? s.currentIndex / s.subjects.length
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.enrollingSubject(
              s.currentIndex + 1,
              s.subjects.length,
              s.currentIndex < s.subjects.length
                  ? s.subjects[s.currentIndex].name
                  : '',
            ),
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          _BulkCounters(
            enrolled: s.enrolled,
            duplicates: s.duplicates,
            errors: s.errors,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => notifier.cancel(),
            child: Text(l10n.cancel),
          ),
        ],

        // Done summary
        if (s.done) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: cs.primary),
            ),
            child: Text(
              l10n.localBulkComplete(
                  s.enrolled, s.duplicates, s.errors),
              style: TextStyle(color: cs.onSurface, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          _BulkCounters(
            enrolled: s.enrolled,
            duplicates: s.duplicates,
            errors: s.errors,
          ),
        ],

        // Report entries (dups + errors)
        if (s.reportEntries.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(8),
              itemCount: s.reportEntries.length,
              itemBuilder: (_, i) {
                final r = s.reportEntries[i];
                final isErr = r.status == 'error';
                final color = isErr ? cs.error : semantic.warning;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    '${r.subjectName}/${r.eyeSide}: ${r.status}${r.detail != null ? ' (${r.detail})' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: color,
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        // Reset after done
        if (s.done) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => notifier.reset(),
            child: Text(l10n.close),
          ),
        ],

        // Error
        if (s.error != null && !s.scanning) ...[
          const SizedBox(height: 8),
          _ErrorBanner(message: s.error!),
        ],

        // No subjects found
        if (!s.scanning &&
            s.directoryPath != null &&
            s.subjects.isEmpty &&
            s.error == null &&
            !s.enrolling)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.noSubjectsFound,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _BulkCounters extends StatelessWidget {
  final int enrolled;
  final int duplicates;
  final int errors;

  const _BulkCounters({
    required this.enrolled,
    required this.duplicates,
    required this.errors,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;

    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        _CounterChip(
          label: '$enrolled ${l10n.bulkEnrolled}',
          color: semantic.success,
          bg: semantic.success.withValues(alpha: 0.1),
        ),
        if (duplicates > 0)
          _CounterChip(
            label: '$duplicates ${l10n.bulkDuplicate}',
            color: semantic.warning,
            bg: semantic.warning.withValues(alpha: 0.1),
          ),
        if (errors > 0)
          _CounterChip(
            label: '$errors ${l10n.errors.toLowerCase()}',
            color: cs.error,
            bg: cs.error.withValues(alpha: 0.1),
          ),
      ],
    );
  }
}

// =============================================================================
// Server-side Bulk Enroll Panel (existing logic preserved)
// =============================================================================

class _BulkEnrollPanel extends ConsumerWidget {
  final String dataset;
  final TextEditingController subjectController;
  final VoidCallback? onStart;

  const _BulkEnrollPanel({
    required this.dataset,
    required this.subjectController,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;
    final s = ref.watch(bulkEnrollProvider);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header bar
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(5)),
            ),
            child: Row(
              children: [
                Icon(Icons.upload_file,
                    size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  l10n.bulkEnroll,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                if (s.dataset != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    s.dataset!,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
                const Spacer(),
                if (s.running)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: cs.primary),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Idle: subject filter + start
                if (s.idle) ...[
                  TextField(
                    controller: subjectController,
                    decoration: InputDecoration(
                      hintText: l10n.bulkEnrollSubjectFilter,
                      hintStyle: const TextStyle(fontSize: 13),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: Text(l10n.bulkEnrollStart),
                  ),
                ],

                // Running / Done: live counters
                if (!s.idle) ...[
                  if (s.running) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 10),
                  ],

                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      _CounterChip(
                        label: l10n.bulkEnrollProgress(s.processed),
                        color: cs.onSurface,
                        bg: cs.surfaceContainerHighest,
                      ),
                      _CounterChip(
                        label: '${s.enrolled} ${l10n.bulkEnrolled}',
                        color: semantic.success,
                        bg: semantic.success.withValues(alpha: 0.1),
                      ),
                      if (s.duplicates > 0)
                        _CounterChip(
                          label:
                              '${s.duplicates} ${l10n.bulkDuplicate}',
                          color: semantic.warning,
                          bg: semantic.warning.withValues(alpha: 0.1),
                        ),
                      if (s.errors > 0)
                        _CounterChip(
                          label:
                              '${s.errors} ${l10n.errors.toLowerCase()}',
                          color: cs.error,
                          bg: cs.error.withValues(alpha: 0.1),
                        ),
                    ],
                  ),
                ],

                // Summary banner
                if (s.summary != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: cs.primary),
                    ),
                    child: Text(
                      l10n.bulkEnrollComplete(
                        s.summary!.enrolled,
                        s.summary!.duplicates,
                        s.summary!.errors,
                      ),
                      style:
                          TextStyle(color: cs.onSurface, fontSize: 13),
                    ),
                  ),
                ],

                // Report: dup & error entries
                if (s.reportEntries.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(8),
                      itemCount: s.reportEntries.length,
                      itemBuilder: (_, i) {
                        final r = s.reportEntries[i];
                        final isErr = r.error != null;
                        final color =
                            isErr ? cs.error : semantic.warning;
                        final status = isErr
                            ? r.error!
                            : '${l10n.bulkDuplicate} (${r.duplicateIdentityId ?? "?"})';
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 1),
                          child: Text(
                            '${r.subjectId}/${r.eyeSide}: $status',
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: color,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                // Connection error
                if (s.connectionError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    s.connectionError!,
                    style: TextStyle(color: cs.error, fontSize: 13),
                  ),
                ],

                // Cancel / Close
                if (s.running || s.done) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (s.running)
                        TextButton(
                          onPressed: () => ref
                              .read(bulkEnrollProvider.notifier)
                              .cancel(),
                          child: Text(l10n.cancel),
                        ),
                      if (s.done)
                        TextButton(
                          onPressed: () => ref
                              .read(bulkEnrollProvider.notifier)
                              .dismiss(),
                          child: Text(l10n.close),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Tab 3: Gallery
// =============================================================================

class _GalleryTab extends ConsumerWidget {
  const _GalleryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final galleryAsync = ref.watch(galleryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.gallery,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: l10n.refresh,
              onPressed: () =>
                  ref.read(galleryProvider.notifier).refresh(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 12),
            galleryAsync.whenOrNull(
                  data: (list) => Text(
                    '${list.length}',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ) ??
                const SizedBox.shrink(),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: galleryAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style: TextStyle(color: cs.error)),
              ),
              data: (gallery) => gallery.isEmpty
                  ? Center(
                      child: Text(
                        l10n.noIdentitiesEnrolled,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: gallery.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1, color: cs.outlineVariant),
                      itemBuilder: (context, index) {
                        final identity = gallery[index];
                        return _GalleryRow(
                          identity: identity,
                          client:
                              ref.read(gatewayClientProvider),
                          onDelete: () => ref
                              .read(galleryProvider.notifier)
                              .deleteIdentity(
                                  identity.identityId),
                        );
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Shared widgets
// =============================================================================

class _CounterChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;

  const _CounterChip({
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _GalleryRow extends StatelessWidget {
  final GalleryIdentity identity;
  final GatewayClient client;
  final VoidCallback onDelete;

  const _GalleryRow({
    required this.identity,
    required this.client,
    required this.onDelete,
  });

  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _IdentityDetailDialog(
        identity: identity,
        client: client,
        onDelete: onDelete,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;

    return InkWell(
      onTap: () => _showDetails(context),
      borderRadius: BorderRadius.circular(4),
      hoverColor: cs.surfaceContainerHighest,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                identity.name,
                style:
                    TextStyle(fontSize: 13, color: cs.onSurface),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                identity.identityId,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: cs.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Wrap(
                spacing: 4,
                children: identity.templates.map((t) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: t.eyeSide == 'left'
                          ? cs.primary.withValues(alpha: 0.2)
                          : semantic.success
                              .withValues(alpha: 0.2),
                    ),
                    child: Text(
                      t.eyeSide,
                      style: TextStyle(
                        fontSize: 11,
                        color: t.eyeSide == 'left'
                            ? cs.primary
                            : semantic.success,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            OutlinedButton(
              onPressed: onDelete,
              child: Text(l10n.delete,
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityDetailDialog extends StatefulWidget {
  final GalleryIdentity identity;
  final GatewayClient client;
  final VoidCallback onDelete;

  const _IdentityDetailDialog({
    required this.identity,
    required this.client,
    required this.onDelete,
  });

  @override
  State<_IdentityDetailDialog> createState() =>
      _IdentityDetailDialogState();
}

class _IdentityDetailDialogState extends State<_IdentityDetailDialog> {
  TemplateDetail? _selectedDetail;
  bool _loadingDetail = false;
  String? _detailError;

  Future<void> _loadTemplateDetail(String templateId) async {
    setState(() {
      _loadingDetail = true;
      _selectedDetail = null;
      _detailError = null;
    });
    try {
      final detail =
          await widget.client.getTemplateDetail(templateId);
      setState(() {
        _selectedDetail = detail;
        _loadingDetail = false;
      });
    } catch (e) {
      setState(() {
        _detailError = e.toString();
        _loadingDetail = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.identity.templates.length == 1) {
      _loadTemplateDetail(
          widget.identity.templates.first.templateId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final semantic =
        Theme.of(context).extension<EyedSemanticColors>()!;

    return AlertDialog(
      title: Text(
        l10n.identityDetails,
        style: const TextStyle(fontSize: 18),
      ),
      content: SizedBox(
        width: 600,
        height: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(
                label: l10n.identityName,
                value: widget.identity.name.isNotEmpty
                    ? widget.identity.name
                    : '\u2014',
              ),
              const SizedBox(height: 8),
              _DetailRow(
                label: l10n.identityId,
                value: widget.identity.identityId,
                mono: true,
              ),
              const SizedBox(height: 16),
              Text(
                '${l10n.templates} (${widget.identity.templates.length})',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              if (widget.identity.templates.isEmpty)
                Text(
                  l10n.noTemplates,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                l10n.templateId,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                l10n.eyeSide,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(
                          height: 1, color: cs.outlineVariant),
                      ...widget.identity.templates.map((t) {
                        final isSelected =
                            _selectedDetail?.templateId ==
                                t.templateId;
                        return InkWell(
                          onTap: () => _loadTemplateDetail(
                              t.templateId),
                          child: Container(
                            color: isSelected
                                ? cs.primary
                                    .withValues(alpha: 0.1)
                                : null,
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    t.templateId,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: isSelected
                                          ? cs.primary
                                          : cs.onSurface,
                                    ),
                                    overflow:
                                        TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Container(
                                    padding: const EdgeInsets
                                        .symmetric(
                                        horizontal: 6,
                                        vertical: 2),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(
                                              3),
                                      color: t.eyeSide ==
                                              'left'
                                          ? cs.primary
                                              .withValues(
                                                  alpha: 0.2)
                                          : semantic.success
                                              .withValues(
                                                  alpha: 0.2),
                                    ),
                                    child: Text(
                                      t.eyeSide == 'left'
                                          ? l10n.eyeSideLeft
                                          : l10n.eyeSideRight,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            t.eyeSide == 'left'
                                                ? cs.primary
                                                : semantic
                                                    .success,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),

              // Template detail
              if (_loadingDetail) ...[
                const SizedBox(height: 16),
                const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2),
                  ),
                ),
              ],
              if (_detailError != null) ...[
                const SizedBox(height: 16),
                Text(
                  _detailError!,
                  style: TextStyle(
                      color: cs.error, fontSize: 12),
                ),
              ],
              if (_selectedDetail != null &&
                  !_loadingDetail) ...[
                const SizedBox(height: 16),
                Divider(color: cs.outlineVariant),
                const SizedBox(height: 12),
                _TemplateDetailView(
                    detail: _selectedDetail!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () {
            Navigator.of(context).pop();
            widget.onDelete();
          },
          child: Text(l10n.delete),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

class _TemplateDetailView extends StatelessWidget {
  final TemplateDetail detail;

  const _TemplateDetailView({required this.detail});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _DetailRow(
                label: l10n.qualityMetrics,
                value:
                    detail.qualityScore.toStringAsFixed(3),
              ),
            ),
            Expanded(
              child: _DetailRow(
                label: l10n.codeSize,
                value:
                    '${detail.width} x ${detail.height}',
              ),
            ),
            Expanded(
              child: _DetailRow(
                label: l10n.scales,
                value: '${detail.nScales}',
              ),
            ),
          ],
        ),
        if (detail.deviceId.isNotEmpty) ...[
          const SizedBox(height: 4),
          _DetailRow(
              label: l10n.deviceId,
              value: detail.deviceId,
              mono: true),
        ],
        const SizedBox(height: 12),
        if (detail.irisCodeB64 != null) ...[
          Text(
            l10n.irisCode,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              border:
                  Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Image.memory(
                base64Decode(detail.irisCodeB64!),
                fit: BoxFit.fitWidth,
                gaplessPlayback: true,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (detail.maskCodeB64 != null) ...[
          Text(
            l10n.maskCode,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              border:
                  Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Image.memory(
                base64Decode(detail.maskCodeB64!),
                fit: BoxFit.fitWidth,
                gaplessPlayback: true,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 13,
              fontFamily: mono ? 'monospace' : null,
              color: cs.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
