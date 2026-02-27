import 'dart:convert';

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/enrollment.dart';
import '../providers/bulk_enroll_provider.dart';
import '../providers/dataset_provider.dart';
import '../providers/gallery_provider.dart';
import '../providers/gateway_client_provider.dart';
import '../services/gateway_client.dart';
import '../theme/eyed_theme.dart';
import '../widgets/dataset_browser.dart';

class EnrollmentScreen extends ConsumerStatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  ConsumerState<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends ConsumerState<EnrollmentScreen> {
  final _nameController = TextEditingController();
  String _eyeSide = 'left';
  bool _enrolling = false;
  EnrollResponse? _enrollResult;
  String? _enrollError;

  @override
  void dispose() {
    _nameController.dispose();
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

  final _bulkSubjectController = TextEditingController();

  Future<void> _enroll() async {
    final browser = ref.read(enrollmentBrowserProvider);
    final image = browser.selectedImage;
    if (image == null || _nameController.text.isEmpty) return;

    setState(() {
      _enrolling = true;
      _enrollResult = null;
      _enrollError = null;
    });

    try {
      final client = ref.read(gatewayClientProvider);
      final b64 = await client.fetchDatasetImageAsBase64(
        browser.selectedDataset,
        image.path,
      );

      final result = await client.enroll(
        jpegB64: b64,
        eyeSide: _eyeSide,
        identityId: const Uuid().v4(),
        identityName: _nameController.text,
      );

      setState(() {
        _enrollResult = result;
        _enrolling = false;
      });

      // Refresh gallery
      ref.read(galleryProvider.notifier).refresh();
    } catch (e) {
      setState(() {
        _enrollError = e.toString();
        _enrolling = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.enrollment,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 20),

        // Main 2-column layout
        Expanded(
          flex: 3,
          child: Consumer(
            builder: (context, ref, _) {
              final l10n = AppLocalizations.of(context);
              final cs = Theme.of(context).colorScheme;
              final browser = ref.watch(enrollmentBrowserProvider);
              final client = ref.read(gatewayClientProvider);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: dataset browser
                  SizedBox(
                    width: 280,
                    child: DatasetBrowser(
                        provider: enrollmentBrowserProvider),
                  ),

                  // Right: preview + form
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Image preview
                            if (browser.selectedImage != null) ...[
                              Container(
                                constraints:
                                    const BoxConstraints(maxWidth: 320),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: cs.outlineVariant),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: Image.network(
                                    client.getDatasetImageUrl(
                                      browser.selectedDataset,
                                      browser.selectedImage!.path,
                                    ),
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                    errorBuilder: (_, __, ___) =>
                                        SizedBox(
                                      height: 200,
                                      child: Center(
                                        child: Icon(Icons.broken_image,
                                            color: cs.onSurfaceVariant),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${browser.selectedImage!.filename} | ${browser.selectedImage!.eyeSide} | Subject: ${browser.selectedImage!.subjectId}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ] else
                              Container(
                                height: 200,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: cs.outlineVariant),
                                ),
                                child: Center(
                                  child: Text(
                                    l10n.selectImageFromBrowser,
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 16),

                            // Enrollment form
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 36,
                                    child: TextField(
                                      controller: _nameController,
                                      decoration: InputDecoration(
                                        hintText: l10n.identityName,
                                      ),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  height: 36,
                                  child: DropdownButton<String>(
                                    value: _eyeSide,
                                    onChanged: (v) {
                                      if (v != null) {
                                        setState(() => _eyeSide = v);
                                      }
                                    },
                                    items: [
                                      DropdownMenuItem(
                                          value: 'left',
                                          child: Text(l10n.eyeSideLeft)),
                                      DropdownMenuItem(
                                          value: 'right',
                                          child: Text(l10n.eyeSideRight)),
                                    ],
                                    underline: const SizedBox(),
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: cs.onSurface),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed:
                                      browser.selectedImage != null &&
                                              _nameController
                                                  .text.isNotEmpty &&
                                              !_enrolling
                                          ? _enroll
                                          : null,
                                  child: _enrolling
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child:
                                              CircularProgressIndicator(
                                                  strokeWidth: 2),
                                        )
                                      : Text(l10n.enroll),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () => ref
                                      .read(enrollmentBrowserProvider
                                          .notifier)
                                      .refresh(),
                                  icon: const Icon(Icons.refresh, size: 18),
                                  tooltip: l10n.refresh,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Result message
                            if (_enrollResult != null)
                              _ResultMessage(result: _enrollResult!),
                            if (_enrollError != null)
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: cs.error
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: cs.error),
                                ),
                                child: Text(
                                  _enrollError!,
                                  style: TextStyle(
                                      color: cs.error,
                                      fontSize: 13),
                                ),
                              ),

                            const SizedBox(height: 16),

                            // Bulk enroll panel
                            _BulkEnrollPanel(
                              dataset: browser.selectedDataset,
                              subjectController: _bulkSubjectController,
                              onStart: browser.selectedDataset.isNotEmpty
                                  ? () => _startBulkEnroll(
                                      browser.selectedDataset)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 16),
        Divider(color: Theme.of(context).colorScheme.outlineVariant),
        const SizedBox(height: 8),

        // Gallery table
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
              onPressed: () => ref.read(galleryProvider.notifier).refresh(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 8),

        Expanded(
          flex: 2,
          child: Consumer(
            builder: (context, ref, _) {
              final l10n = AppLocalizations.of(context);
              final cs = Theme.of(context).colorScheme;
              final galleryAsync = ref.watch(galleryProvider);
              return Container(
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
                              client: ref.read(gatewayClientProvider),
                              onDelete: () => ref
                                  .read(galleryProvider.notifier)
                                  .deleteIdentity(identity.identityId),
                            );
                          },
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ResultMessage extends StatelessWidget {
  final EnrollResponse result;

  const _ResultMessage({required this.result});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;
    final isDup = result.isDuplicate;
    final color = isDup ? semantic.warning : semantic.success;
    final text = isDup
        ? l10n.duplicateDetected(result.duplicateIdentityId ?? "?")
        : l10n.enrolled(result.templateId);

    return Container(
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(5)),
            ),
            child: Row(
              children: [
                Icon(Icons.upload_file, size: 16, color: cs.onSurfaceVariant),
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
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
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
                // --- Idle: subject filter + start ---
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

                // --- Running / Done: live counters ---
                if (!s.idle) ...[
                  if (s.running) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 10),
                  ],

                  // Counter chips
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
                          label: '${s.duplicates} ${l10n.bulkDuplicate}',
                          color: semantic.warning,
                          bg: semantic.warning.withValues(alpha: 0.1),
                        ),
                      if (s.errors > 0)
                        _CounterChip(
                          label: '${s.errors} ${l10n.errors.toLowerCase()}',
                          color: cs.error,
                          bg: cs.error.withValues(alpha: 0.1),
                        ),
                    ],
                  ),
                ],

                // --- Summary banner ---
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
                      style: TextStyle(color: cs.onSurface, fontSize: 13),
                    ),
                  ),
                ],

                // --- Report: dup & error entries only ---
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
                          padding: const EdgeInsets.symmetric(vertical: 1),
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

                // --- Connection error ---
                if (s.connectionError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    s.connectionError!,
                    style: TextStyle(color: cs.error, fontSize: 13),
                  ),
                ],

                // --- Cancel / Close ---
                if (s.running || s.done) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (s.running)
                        TextButton(
                          onPressed: () =>
                              ref.read(bulkEnrollProvider.notifier).cancel(),
                          child: Text(l10n.cancel),
                        ),
                      if (s.done)
                        TextButton(
                          onPressed: () =>
                              ref.read(bulkEnrollProvider.notifier).dismiss(),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                identity.name,
                style: TextStyle(fontSize: 13, color: cs.onSurface),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: t.eyeSide == 'left'
                          ? cs.primary.withValues(alpha: 0.2)
                          : semantic.success.withValues(alpha: 0.2),
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
              child: Text(l10n.delete, style: const TextStyle(fontSize: 12)),
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
  State<_IdentityDetailDialog> createState() => _IdentityDetailDialogState();
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
      final detail = await widget.client.getTemplateDetail(templateId);
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
      _loadTemplateDetail(widget.identity.templates.first.templateId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;

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
              // Identity name
              _DetailRow(
                label: l10n.identityName,
                value: widget.identity.name.isNotEmpty
                    ? widget.identity.name
                    : '\u2014',
              ),
              const SizedBox(height: 8),

              // Identity ID
              _DetailRow(
                label: l10n.identityId,
                value: widget.identity.identityId,
                mono: true,
              ),
              const SizedBox(height: 16),

              // Templates header
              Text(
                '${l10n.templates} (${widget.identity.templates.length})',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),

              // Templates list
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
                      // Table header
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
                      Divider(height: 1, color: cs.outlineVariant),
                      // Template rows
                      ...widget.identity.templates.map((t) {
                        final isSelected =
                            _selectedDetail?.templateId == t.templateId;
                        return InkWell(
                          onTap: () => _loadTemplateDetail(t.templateId),
                          child: Container(
                            color: isSelected
                                ? cs.primary.withValues(alpha: 0.1)
                                : null,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
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
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(3),
                                      color: t.eyeSide == 'left'
                                          ? cs.primary
                                              .withValues(alpha: 0.2)
                                          : semantic.success
                                              .withValues(alpha: 0.2),
                                    ),
                                    child: Text(
                                      t.eyeSide == 'left'
                                          ? l10n.eyeSideLeft
                                          : l10n.eyeSideRight,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: t.eyeSide == 'left'
                                            ? cs.primary
                                            : semantic.success,
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

              // Template detail section
              if (_loadingDetail) ...[
                const SizedBox(height: 16),
                const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
              if (_detailError != null) ...[
                const SizedBox(height: 16),
                Text(
                  _detailError!,
                  style: TextStyle(color: cs.error, fontSize: 12),
                ),
              ],
              if (_selectedDetail != null && !_loadingDetail) ...[
                const SizedBox(height: 16),
                Divider(color: cs.outlineVariant),
                const SizedBox(height: 12),
                _TemplateDetailView(detail: _selectedDetail!),
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
        // Metadata row
        Row(
          children: [
            Expanded(
              child: _DetailRow(
                label: l10n.qualityMetrics,
                value: detail.qualityScore.toStringAsFixed(3),
              ),
            ),
            Expanded(
              child: _DetailRow(
                label: l10n.codeSize,
                value: '${detail.width} x ${detail.height}',
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
          _DetailRow(label: l10n.deviceId, value: detail.deviceId, mono: true),
        ],
        const SizedBox(height: 12),

        // Iris code visualization
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
              border: Border.all(color: cs.outlineVariant),
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

        // Mask code visualization
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
              border: Border.all(color: cs.outlineVariant),
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
