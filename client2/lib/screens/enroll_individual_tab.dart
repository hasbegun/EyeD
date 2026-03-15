import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import '../providers/api_client_provider.dart';
import '../providers/gallery_provider.dart';

class IndividualTab extends ConsumerStatefulWidget {
  const IndividualTab({super.key});

  @override
  ConsumerState<IndividualTab> createState() => _IndividualTabState();
}

class _IndividualTabState extends ConsumerState<IndividualTab>
    with AutomaticKeepAliveClientMixin {
  final _nameController = TextEditingController();

  Uint8List? _leftBytes;
  String? _leftFileName;
  bool _leftNA = false;

  Uint8List? _rightBytes;
  String? _rightFileName;
  bool _rightNA = false;

  bool _enrolling = false;
  String? _lastDir; // remember last picked directory

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canEnroll {
    if (_nameController.text.trim().isEmpty) return false;
    if (_enrolling) return false;
    final hasLeft = _leftBytes != null && !_leftNA;
    final hasRight = _rightBytes != null && !_rightNA;
    return hasLeft || hasRight;
  }

  Future<void> _pickImage({required bool isLeft}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp'],
      initialDirectory: _lastDir,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    // Remember directory for next pick
    if (file.path != null) {
      _lastDir = file.path!.substring(0, file.path!.lastIndexOf('/'));
    }

    setState(() {
      if (isLeft) {
        _leftBytes = file.bytes;
        _leftFileName = file.name;
        _leftNA = false;
      } else {
        _rightBytes = file.bytes;
        _rightFileName = file.name;
        _rightNA = false;
      }
    });
  }

  Future<void> _enroll() async {
    setState(() => _enrolling = true);

    final client = ref.read(apiClientProvider);
    final name = _nameController.text.trim();
    final identityId = const Uuid().v4();
    final messages = <String>[];

    bool? isEncrypted;

    try {
      // Enroll left eye
      if (_leftBytes != null && !_leftNA) {
        final resp = await client.enroll(
          jpegB64: base64Encode(_leftBytes!),
          eyeSide: 'left',
          identityId: identityId,
          identityName: name,
        );
        if (resp.error != null) {
          messages.add('L: ${resp.error}');
        } else if (resp.isDuplicate) {
          messages.add('L: dup (${resp.duplicateIdentityName ?? "?"})');
        } else {
          isEncrypted = resp.isEncrypted;
        }
      }

      // Enroll right eye
      if (_rightBytes != null && !_rightNA) {
        final resp = await client.enroll(
          jpegB64: base64Encode(_rightBytes!),
          eyeSide: 'right',
          identityId: identityId,
          identityName: name,
        );
        if (resp.error != null) {
          messages.add('R: ${resp.error}');
        } else if (resp.isDuplicate) {
          messages.add('R: dup (${resp.duplicateIdentityName ?? "?"})');
        } else {
          isEncrypted ??= resp.isEncrypted;
        }
      }

      // Refresh gallery so the new identity appears immediately
      ref.read(galleryProvider.notifier).refresh();

      if (!mounted) return;
      final l = AppLocalizations.of(context);

      if (messages.isEmpty) {
        // Show encryption status in success message
        final successMsg = isEncrypted == true
            ? l.enrollSuccessEncrypted
            : isEncrypted == false
                ? l.enrollSuccessPlain
                : l.enrollSuccess;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMsg),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(messages.join('; '))),
        );
      }

      // Clear inputs but keep _lastDir
      setState(() {
        _nameController.clear();
        _leftBytes = null;
        _leftFileName = null;
        _leftNA = false;
        _rightBytes = null;
        _rightFileName = null;
        _rightNA = false;
      });
    } catch (e) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.enrollError(_friendlyError(e))),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
  }

  String _friendlyError(Object e) {
    if (e.toString().contains('connection')) return 'Connection error';
    return 'Server error';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Name
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l.nameLabel,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),

              // Left eye
              _EyeInput(
                label: l.leftEye,
                fileName: _leftFileName,
                imageBytes: _leftBytes,
                isNA: _leftNA,
                onPick: () => _pickImage(isLeft: true),
                onNAChanged: (v) => setState(() => _leftNA = v),
                loadLabel: l.loadImage,
                naLabel: l.notAvailable,
              ),
              const SizedBox(height: 16),

              // Right eye
              _EyeInput(
                label: l.rightEye,
                fileName: _rightFileName,
                imageBytes: _rightBytes,
                isNA: _rightNA,
                onPick: () => _pickImage(isLeft: false),
                onNAChanged: (v) => setState(() => _rightNA = v),
                loadLabel: l.loadImage,
                naLabel: l.notAvailable,
              ),
              const SizedBox(height: 24),

              // Enroll button
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _canEnroll ? _enroll : null,
                  child: _enrolling
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l.enroll),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EyeInput extends StatelessWidget {
  final String label;
  final String? fileName;
  final Uint8List? imageBytes;
  final bool isNA;
  final VoidCallback onPick;
  final ValueChanged<bool> onNAChanged;
  final String loadLabel;
  final String naLabel;

  const _EyeInput({
    required this.label,
    required this.fileName,
    required this.imageBytes,
    required this.isNA,
    required this.onPick,
    required this.onNAChanged,
    required this.loadLabel,
    required this.naLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: theme.textTheme.titleSmall),
            const Spacer(),
            Text(naLabel, style: theme.textTheme.bodySmall),
            Switch(
              value: isNA,
              onChanged: onNAChanged,
            ),
          ],
        ),
        if (!isNA) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.image, size: 18),
                label: Text(loadLabel),
              ),
              const SizedBox(width: 12),
              if (fileName != null)
                Expanded(
                  child: Text(
                    fileName!,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
          if (imageBytes != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                imageBytes!,
                height: 120,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ] else ...[
          const SizedBox(height: 8),
          Container(
            height: 60,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(naLabel,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ),
        ],
      ],
    );
  }
}
