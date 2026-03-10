import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/analyze_result.dart';
import '../providers/api_client_provider.dart';
import '../providers/log_provider.dart';

class DetectScreen extends ConsumerStatefulWidget {
  const DetectScreen({super.key});

  @override
  ConsumerState<DetectScreen> createState() => _DetectScreenState();
}

class _DetectScreenState extends ConsumerState<DetectScreen> {
  Uint8List? _imageBytes;
  String? _fileName;
  bool _detecting = false;
  AnalyzeResponse? _result;
  String? _error;
  String? _lastDir;

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp'],
      initialDirectory: _lastDir,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    if (file.path != null) {
      _lastDir = file.path!.substring(0, file.path!.lastIndexOf('/'));
    }

    setState(() {
      _imageBytes = file.bytes;
      _fileName = file.name;
      _result = null;
      _error = null;
    });
  }

  Future<void> _detect() async {
    if (_imageBytes == null) return;
    setState(() {
      _detecting = true;
      _result = null;
      _error = null;
    });

    try {
      final client = ref.read(apiClientProvider);
      // Try left eye first — the analyze endpoint doesn't require a specific side
      final resp = await client.analyzeImage(_imageBytes!, 'left');
      ref.read(logProvider.notifier).add(resp, fileName: _fileName);
      if (mounted) setState(() => _result = resp);
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        setState(() {
          _error = e.toString().contains('connection')
              ? l.connectionError
              : l.serverError;
        });
      }
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Load image
              OutlinedButton.icon(
                onPressed: _detecting ? null : _pickImage,
                icon: const Icon(Icons.image_search, size: 20),
                label: Text(l.detectLoadImage),
              ),
              if (_fileName != null) ...[
                const SizedBox(height: 4),
                Text(_fileName!,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center),
              ],

              // Show image
              if (_imageBytes != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _imageBytes!,
                    height: 200,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 20),

                // Detect button
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _detecting ? null : _detect,
                    child: _detecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(l.detectButton),
                  ),
                ),
              ],

              // Result
              if (_result != null) ...[
                const SizedBox(height: 24),
                _ResultCard(result: _result!),
              ],

              // Error
              if (_error != null) ...[
                const SizedBox(height: 24),
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final AnalyzeResponse result;

  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (result.error != null) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l.detectError(result.error!),
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final match = result.match;
    if (match == null || !match.isMatch) {
      return Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.cancel_outlined, color: Colors.red.shade700, size: 48),
              const SizedBox(height: 8),
              Text(
                l.detectNoMatch,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (match != null) ...[
                const SizedBox(height: 4),
                Text(
                  'HD: ${match.hammingDistance.toStringAsFixed(4)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.red.shade400,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Match found
    final hd = match.hammingDistance.toStringAsFixed(4);
    final name = match.matchedIdentityName ?? match.matchedIdentityId ?? '?';

    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.check_circle_outline,
                color: Colors.green.shade700, size: 48),
            const SizedBox(height: 8),
            Text(
              l.detectMatch(name, hd),
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.green.shade700,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
