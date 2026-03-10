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
    final eyes = <String>[];
    for (final t in identity.templates) {
      if (t.eyeSide == 'left' && !eyes.contains('L')) eyes.add('L');
      if (t.eyeSide == 'right' && !eyes.contains('R')) eyes.add('R');
    }

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
          _EyeBadge('L', eyes.contains('L')),
          const SizedBox(width: 4),
          _EyeBadge('R', eyes.contains('R')),
        ],
      ),
      onTap: () => _showDetail(context, ref),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _IdentityDetailDialog(identity: identity, ref: ref),
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

class _IdentityDetailDialog extends StatefulWidget {
  final GalleryIdentity identity;
  final WidgetRef ref;

  const _IdentityDetailDialog({required this.identity, required this.ref});

  @override
  State<_IdentityDetailDialog> createState() => _IdentityDetailDialogState();
}

class _IdentityDetailDialogState extends State<_IdentityDetailDialog> {
  TemplateDetail? _selectedDetail;
  bool _loadingDetail = false;
  String? _detailError;

  @override
  void initState() {
    super.initState();
    // Auto-load if single template
    if (widget.identity.templates.length == 1) {
      _loadTemplate(widget.identity.templates.first.templateId);
    }
  }

  Future<void> _loadTemplate(String templateId) async {
    setState(() {
      _loadingDetail = true;
      _detailError = null;
      _selectedDetail = null;
    });
    try {
      final detail =
          await widget.ref.read(apiClientProvider).getTemplateDetail(templateId);
      if (mounted) setState(() => _selectedDetail = detail);
    } catch (e) {
      if (mounted) setState(() => _detailError = 'Failed to load template');
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final id = widget.identity;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l.identityDetail),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _InfoRow('Name', id.name),
              _InfoRow('ID', id.identityId),
              const SizedBox(height: 16),
              Text('Templates', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ...id.templates.map((t) => Card(
                    child: ListTile(
                      leading: _EyeBadge(
                          t.eyeSide == 'left' ? 'L' : 'R', true),
                      title: Text(t.templateId,
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis),
                      onTap: () => _loadTemplate(t.templateId),
                    ),
                  )),
              if (_loadingDetail) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
              if (_detailError != null) ...[
                const SizedBox(height: 16),
                Text(_detailError!,
                    style: TextStyle(color: theme.colorScheme.error)),
              ],
              if (_selectedDetail != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                Text(l.templateDetail, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                _InfoRow(l.eyeSide, _selectedDetail!.eyeSide),
                _InfoRow(l.qualityScore,
                    _selectedDetail!.qualityScore.toStringAsFixed(3)),
                _InfoRow(l.deviceId, _selectedDetail!.deviceId),
                _InfoRow(l.dimensions,
                    '${_selectedDetail!.width} x ${_selectedDetail!.height} x ${_selectedDetail!.nScales}'),
                if (_selectedDetail!.irisCodeB64 != null) ...[
                  const SizedBox(height: 12),
                  Text(l.irisCode, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Image.memory(
                        base64Decode(_selectedDetail!.irisCodeB64!),
                        fit: BoxFit.fitWidth,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ],
                if (_selectedDetail!.maskCodeB64 != null) ...[
                  const SizedBox(height: 12),
                  Text(l.maskCode, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Image.memory(
                        base64Decode(_selectedDetail!.maskCodeB64!),
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
              await widget.ref
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
