import 'dart:convert';

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/detailed_result.dart';
import '../providers/dataset_provider.dart';
import '../providers/gateway_client_provider.dart';
import '../providers/history_provider.dart';
import '../theme/eyed_theme.dart';
import '../widgets/dataset_browser.dart';
import '../widgets/metric_tile.dart';
import '../widgets/section_card.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  DetailedResult? _result;
  bool _analyzing = false;
  String? _error;

  Future<void> _analyze() async {
    final browser = ref.read(analysisBrowserProvider);
    final image = browser.selectedImage;
    if (image == null) return;

    setState(() {
      _analyzing = true;
      _result = null;
      _error = null;
    });

    try {
      final client = ref.read(gatewayClientProvider);
      final result = await client.analyzeDetailed(
        browser.selectedDataset,
        image.path,
        image.eyeSide,
      );
      ref.read(historyProvider.notifier).onResult(result.toAnalyzeResult());
      setState(() {
        _result = result;
        _analyzing = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _analyzing = false;
      });
    }
  }

  Widget _buildBrowser(BuildContext context, double width) {
    return Consumer(
      builder: (context, ref, _) {
        final l10n = AppLocalizations.of(context);
        final cs = Theme.of(context).colorScheme;
        final browser = ref.watch(analysisBrowserProvider);
        return Column(
          children: [
            Expanded(
              child: SizedBox(
                width: width,
                child: DatasetBrowser(
                  provider: analysisBrowserProvider,
                  mode: BrowserMode.thumbnailGrid,
                ),
              ),
            ),
            // Action bar
            Container(
              width: width,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                border: Border(
                  right: BorderSide(color: cs.outlineVariant),
                  top: BorderSide(color: cs.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          browser.selectedImage != null && !_analyzing
                              ? _analyze
                              : null,
                      child: _analyzing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : Text(l10n.analyze),
                    ),
                  ),
                  if (_result != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${_result!.latencyMs.round()}ms',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResults(AppLocalizations l10n, ColorScheme cs) {
    if (_analyzing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_result == null && _error == null) {
      return Center(
        child: Text(
          l10n.selectImageAndAnalyze,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: _ResultsPanel(result: _result, error: _error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.analysis,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 480;

              if (wide) {
                // Side-by-side: browser left, results right.
                final browserW = constraints.maxWidth < 600
                    ? 220.0
                    : constraints.maxWidth < 700
                        ? 240.0
                        : 280.0;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: browserW,
                      child: _buildBrowser(context, browserW),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 20),
                        child: _buildResults(l10n, cs),
                      ),
                    ),
                  ],
                );
              }

              // Narrow: stacked vertically, both sections scrollable.
              final browserH =
                  (constraints.maxHeight * 0.55).clamp(260.0, 400.0);
              return Column(
                children: [
                  SizedBox(
                    height: browserH,
                    width: double.infinity,
                    child: _buildBrowser(context, constraints.maxWidth),
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: _buildResults(l10n, cs)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ResultsPanel extends StatelessWidget {
  final DetailedResult? result;
  final String? error;

  const _ResultsPanel({this.result, this.error});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;

    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: cs.error),
        ),
        child: Text(error!, style: TextStyle(color: cs.error)),
      );
    }

    final r = result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Error/warning banner
        if (r.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: semantic.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: semantic.warning),
              ),
              child: Text(
                r.error!,
                style: TextStyle(
                    color: semantic.warning, fontSize: 13),
              ),
            ),
          ),

        // Segmentation
        if (r.originalImageB64 != null || r.segmentationOverlayB64 != null)
          SectionCard(
            title: l10n.segmentation,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final hasBoth = r.originalImageB64 != null &&
                    r.segmentationOverlayB64 != null;
                final useColumn = hasBoth && constraints.maxWidth < 300;

                if (useColumn) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (r.originalImageB64 != null)
                        _B64Image(
                          data: r.originalImageB64!,
                          label: l10n.original,
                        ),
                      if (hasBoth) const SizedBox(height: 8),
                      if (r.segmentationOverlayB64 != null)
                        _B64Image(
                          data: r.segmentationOverlayB64!,
                          label: l10n.segmentation,
                        ),
                    ],
                  );
                }

                final halfWidth = (constraints.maxWidth - 12) / 2;
                return Row(
                  children: [
                    if (r.originalImageB64 != null)
                      _B64Image(
                        data: r.originalImageB64!,
                        width: halfWidth,
                        label: l10n.original,
                      ),
                    if (hasBoth) const SizedBox(width: 12),
                    if (r.segmentationOverlayB64 != null)
                      _B64Image(
                        data: r.segmentationOverlayB64!,
                        width: halfWidth,
                        label: l10n.segmentation,
                      ),
                  ],
                );
              },
            ),
          ),

        const SizedBox(height: 12),

        // Pipeline outputs
        if (r.normalizedIrisB64 != null || r.irisCodeB64 != null)
          SectionCard(
            title: l10n.pipelineOutputs,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.normalizedIrisB64 != null)
                  _B64Image(
                    data: r.normalizedIrisB64!,
                    label: l10n.normalizedIris,
                  ),
                if (r.irisCodeB64 != null) ...[
                  const SizedBox(height: 8),
                  _B64Image(data: r.irisCodeB64!, label: l10n.irisCode),
                ],
                if (r.noiseMaskB64 != null) ...[
                  const SizedBox(height: 8),
                  _B64Image(data: r.noiseMaskB64!, label: l10n.noiseMask),
                ],
              ],
            ),
          ),

        const SizedBox(height: 12),

        // Quality metrics
        if (r.quality != null)
          SectionCard(
            title: l10n.qualityMetrics,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MetricTile(
                  label: l10n.sharpness,
                  value: r.quality!.sharpness.toStringAsFixed(3),
                ),
                MetricTile(
                  label: l10n.offgaze,
                  value: r.quality!.offgazeScore.toStringAsFixed(3),
                ),
                MetricTile(
                  label: l10n.occlusion90,
                  value: r.quality!.occlusion90.toStringAsFixed(3),
                ),
                MetricTile(
                  label: l10n.occlusion30,
                  value: r.quality!.occlusion30.toStringAsFixed(3),
                ),
                MetricTile(
                  label: l10n.pupilIrisRatio,
                  value: r.quality!.pupilIrisRatio.toStringAsFixed(3),
                ),
              ],
            ),
          ),

        const SizedBox(height: 12),

        // Geometry
        if (r.geometry != null)
          SectionCard(
            title: l10n.geometry,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MetricTile(
                  label: l10n.pupilCenter,
                  value:
                      '(${r.geometry!.pupilCenter[0].toStringAsFixed(1)}, ${r.geometry!.pupilCenter[1].toStringAsFixed(1)})',
                ),
                MetricTile(
                  label: l10n.irisCenter,
                  value:
                      '(${r.geometry!.irisCenter[0].toStringAsFixed(1)}, ${r.geometry!.irisCenter[1].toStringAsFixed(1)})',
                ),
                MetricTile(
                  label: l10n.pupilRadius,
                  value: r.geometry!.pupilRadius.toStringAsFixed(1),
                ),
                MetricTile(
                  label: l10n.irisRadius,
                  value: r.geometry!.irisRadius.toStringAsFixed(1),
                ),
                MetricTile(
                  label: l10n.eyeOrientation,
                  value:
                      '${(r.geometry!.eyeOrientation * 180 / 3.14159).toStringAsFixed(1)}°',
                ),
              ],
            ),
          ),

        const SizedBox(height: 12),

        // Match result
        _MatchResult(match: r.match),
      ],
    );
  }
}

class _B64Image extends StatelessWidget {
  final String data;
  final double? width;
  final String? label;

  const _B64Image({required this.data, this.width, this.label});

  @override
  Widget build(BuildContext context) {
    final bytes = base64Decode(data);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              label!,
              style: TextStyle(
                  fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        Container(
          width: width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _MatchResult extends StatelessWidget {
  final dynamic match;

  const _MatchResult({this.match});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;

    if (match == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.onSurfaceVariant.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Text(
          l10n.noGalleryTemplates,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
      );
    }

    final m = match!;
    final isMatch = m.isMatch as bool;
    final hd = m.hammingDistance as double;
    final color = isMatch ? semantic.success : semantic.warning;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Text(
            l10n.hdValue(hd.toStringAsFixed(4)),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMatch && m.matchedIdentityName != null && (m.matchedIdentityName as String).isNotEmpty)
                  Text(
                    m.matchedIdentityName as String,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  isMatch
                      ? l10n.matchIdentity(m.matchedIdentityId ?? '?')
                      : l10n.noMatch,
                  style: TextStyle(color: color, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
