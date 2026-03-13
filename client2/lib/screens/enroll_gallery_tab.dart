import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/enrollment.dart';
import '../providers/api_client_provider.dart';
import '../providers/gallery_provider.dart';

class GalleryTab extends ConsumerWidget {
  const GalleryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final gallery = ref.watch(galleryProvider);

    return Column(
      children: [
        // Toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              gallery.whenOrNull(
                    data: (list) => Text(
                      l.galleryCount(list.length),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ) ??
                  const SizedBox.shrink(),
              const Spacer(),
              TextButton.icon(
                onPressed: () => ref.read(galleryProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l.galleryRefresh),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // List
        Expanded(
          child: gallery.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(l.connectionError,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            data: (list) {
              if (list.isEmpty) {
                return Center(
                  child: Text(l.galleryEmpty,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                );
              }
              return ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) =>
                    _IdentityTile(identity: list[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _IdentityTile extends ConsumerWidget {
  final GalleryIdentity identity;

  const _IdentityTile({required this.identity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Find first template for each eye side
    final leftTemplate = identity.templates
        .where((t) => t.eyeSide == 'left')
        .firstOrNull;
    final rightTemplate = identity.templates
        .where((t) => t.eyeSide == 'right')
        .firstOrNull;

    return ListTile(
      title: Text(identity.name.isNotEmpty ? identity.name : '(unnamed)'),
      subtitle: Text(
        identity.identityId,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // L badge — tappable if enrolled; opens dialog pre-loading left eye
          GestureDetector(
            onTap: leftTemplate != null
                ? () => _showDetail(context, leftTemplate.templateId)
                : null,
            child: _EyeBadge('L', leftTemplate != null),
          ),
          const SizedBox(width: 4),
          // R badge — tappable if enrolled; opens dialog pre-loading right eye
          GestureDetector(
            onTap: rightTemplate != null
                ? () => _showDetail(context, rightTemplate.templateId)
                : null,
            child: _EyeBadge('R', rightTemplate != null),
          ),
        ],
      ),
      onTap: () => _showDetail(context, null),
    );
  }

  void _showDetail(BuildContext context, String? initialTemplateId) {
    showDialog(
      context: context,
      builder: (_) => _IdentityDetailDialog(
        identity: identity,
        initialTemplateId: initialTemplateId,
      ),
    );
  }
}

class _EyeBadge extends StatelessWidget {
  final String label;
  final bool active;

  const _EyeBadge(this.label, this.active);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: active
            ? (label == 'L' ? Colors.blue : Colors.teal)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _IdentityDetailDialog extends ConsumerStatefulWidget {
  final GalleryIdentity identity;
  // When opened via L/R badge tap, highlight this template first
  final String? initialTemplateId;

  const _IdentityDetailDialog({
    required this.identity,
    this.initialTemplateId,
  });

  @override
  ConsumerState<_IdentityDetailDialog> createState() =>
      _IdentityDetailDialogState();
}

class _IdentityDetailDialogState
    extends ConsumerState<_IdentityDetailDialog> {
  // Per-template loading state
  final Map<String, TemplateDetail?> _details = {};
  final Map<String, bool> _loading = {};
  final Map<String, String?> _errors = {};

  @override
  void initState() {
    super.initState();
    // Load ALL templates in parallel on open — no tap required
    for (final t in widget.identity.templates) {
      _loadTemplate(t.templateId);
    }
  }

  Future<void> _loadTemplate(String templateId) async {
    setState(() {
      _loading[templateId] = true;
      _errors[templateId] = null;
    });
    try {
      final detail =
          await ref.read(apiClientProvider).getTemplateDetail(templateId);
      if (mounted) setState(() => _details[templateId] = detail);
    } catch (e) {
      if (mounted) setState(() => _errors[templateId] = 'Failed to load');
    } finally {
      if (mounted) setState(() => _loading[templateId] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final id = widget.identity;
    final theme = Theme.of(context);

    // Sort: initialTemplateId first, then left before right
    final sorted = [...id.templates]..sort((a, b) {
        if (a.templateId == widget.initialTemplateId) return -1;
        if (b.templateId == widget.initialTemplateId) return 1;
        return a.eyeSide.compareTo(b.eyeSide); // 'left' < 'right'
      });

    return AlertDialog(
      title: Text(l.identityDetail),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _InfoRow('Name', id.name),
              _InfoRow('ID', id.identityId),
              const SizedBox(height: 16),
              // Render each template as its own inline section
              ...sorted.map((t) => _TemplateSection(
                    templateInfo: t,
                    detail: _details[t.templateId],
                    isLoading: _loading[t.templateId] ?? false,
                    error: _errors[t.templateId],
                    isHighlighted: t.templateId == widget.initialTemplateId,
                  )),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l.deleteConfirm(id.name)),
                content: Text(l.deleteConfirmBody),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(l.cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.red),
                    child: Text(l.delete),
                  ),
                ],
              ),
            );
            if (confirmed == true && context.mounted) {
              await ref
                  .read(galleryProvider.notifier)
                  .deleteIdentity(id.identityId);
              if (context.mounted) Navigator.pop(context);
            }
          },
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(l.deleteIdentity),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
          ),
          Expanded(
            child: SelectableText(value,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

// Displays one template's full detail inline (auto-loaded, no tap needed).
class _TemplateSection extends StatelessWidget {
  final TemplateInfo templateInfo;
  final TemplateDetail? detail;
  final bool isLoading;
  final String? error;
  final bool isHighlighted;

  const _TemplateSection({
    required this.templateInfo,
    required this.detail,
    required this.isLoading,
    required this.error,
    required this.isHighlighted,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final eyeLabel = templateInfo.eyeSide == 'left' ? 'L' : 'R';
    final isEncrypted = detail?.isEncrypted ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: isHighlighted
              ? theme.colorScheme.primary.withOpacity(0.5)
              : theme.colorScheme.outlineVariant,
          width: isHighlighted ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isHighlighted
            ? theme.colorScheme.primaryContainer.withOpacity(0.15)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: eye badge + template ID + encryption badge
            Row(
              children: [
                _EyeBadge(eyeLabel, true),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    templateInfo.templateId,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(width: 8),
                  _EncryptionBadge(
                      isEncrypted: isEncrypted,
                      encryptedLabel: l.templateEncrypted,
                      plaintextLabel: l.templatePlaintext),
                ],
              ],
            ),

            // Loading spinner
            if (isLoading) ...[
              const SizedBox(height: 12),
              const Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ],

            // Error
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!,
                  style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 12)),
            ],

            // Detail: metrics + images
            if (detail != null) ...[
              const SizedBox(height: 8),
              _InfoRow(l.qualityScore,
                  detail!.qualityScore.toStringAsFixed(3)),
              _InfoRow(l.dimensions,
                  '${detail!.width} x ${detail!.height} x ${detail!.nScales}'),
              _InfoRow(l.deviceId, detail!.deviceId),

              // Encrypted: no-preview notice
              if (isEncrypted) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: Colors.orange.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l.encryptedNoPreview,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.orange.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Iris code image
              if (!isEncrypted && detail!.irisCodeB64 != null) ...[
                const SizedBox(height: 10),
                Text(l.irisCode, style: theme.textTheme.labelSmall),
                const SizedBox(height: 4),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Image.memory(
                      base64Decode(detail!.irisCodeB64!),
                      fit: BoxFit.fitWidth,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ],

              // Mask code image
              if (!isEncrypted && detail!.maskCodeB64 != null) ...[
                const SizedBox(height: 8),
                Text(l.maskCode, style: theme.textTheme.labelSmall),
                const SizedBox(height: 4),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Image.memory(
                      base64Decode(detail!.maskCodeB64!),
                      fit: BoxFit.fitWidth,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _EncryptionBadge extends StatelessWidget {
  final bool isEncrypted;
  final String encryptedLabel;
  final String plaintextLabel;

  const _EncryptionBadge({
    required this.isEncrypted,
    required this.encryptedLabel,
    required this.plaintextLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isEncrypted ? Colors.orange.shade100 : Colors.green.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isEncrypted ? Colors.orange.shade400 : Colors.green.shade400,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isEncrypted ? Icons.lock : Icons.lock_open,
            size: 11,
            color: isEncrypted
                ? Colors.orange.shade800
                : Colors.green.shade800,
          ),
          const SizedBox(width: 3),
          Text(
            isEncrypted ? encryptedLabel : plaintextLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isEncrypted
                  ? Colors.orange.shade800
                  : Colors.green.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
