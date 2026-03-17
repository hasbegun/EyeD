import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dataset.dart';
import '../providers/dataset_provider.dart';
import '../services/gateway_client.dart';
import '../providers/gateway_client_provider.dart';
import '../theme/eyed_theme.dart';

enum BrowserMode { list, thumbnailGrid }

class DatasetBrowser extends ConsumerWidget {
  final StateNotifierProvider<DatasetBrowserNotifier, DatasetBrowserState>
      provider;
  final BrowserMode mode;

  const DatasetBrowser({
    super.key,
    required this.provider,
    this.mode = BrowserMode.list,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final client = ref.read(gatewayClientProvider);
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(right: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dataset tabs
          if (state.datasets.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: cs.outlineVariant)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: state.datasets.map((ds) {
                    final selected = ds.name == state.selectedDataset;
                    final label = ds.count >= 0
                        ? '${ds.name} (${ds.count})'
                        : ds.name;
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: selected,
                        onSelected: (_) => notifier.selectDataset(ds.name),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          // Subject chips — Flexible so it shrinks in tight layouts
          if (state.subjects.isNotEmpty)
            Flexible(
              child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: cs.outlineVariant)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: state.subjects.map((sub) {
                    final selected = sub.subjectId == state.selectedSubject;
                    return InkWell(
                      onTap: () => notifier.selectSubject(
                        selected ? null : sub.subjectId,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? cs.primaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: selected
                                ? cs.primary
                                : cs.outlineVariant,
                          ),
                        ),
                        child: Text(
                          '${sub.subjectId} (${sub.imageCount})',
                          style: TextStyle(
                            fontSize: 12,
                            color: selected
                                ? cs.onSurface
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            ),

          // Loading indicator
          if (state.loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),

          // Image list/grid — higher flex so grid gets more space than chips
          if (!state.loading)
            Expanded(
              flex: 3,
              child: mode == BrowserMode.thumbnailGrid
                  ? _ThumbnailGrid(
                      images: state.filteredImages,
                      selected: state.selectedImage,
                      client: client,
                      datasetName: state.selectedDataset,
                      onSelect: notifier.selectImage,
                      hasMore: state.hasMoreImages,
                      loadingMore: state.loadingImages,
                      onLoadMore: notifier.loadMoreImages,
                    )
                  : _ImageList(
                      images: state.filteredImages,
                      selected: state.selectedImage,
                      onSelect: notifier.selectImage,
                      hasMore: state.hasMoreImages,
                      loadingMore: state.loadingImages,
                      onLoadMore: notifier.loadMoreImages,
                    ),
            ),
        ],
      ),
    );
  }
}

class _ImageList extends StatelessWidget {
  final List<DatasetImage> images;
  final DatasetImage? selected;
  final ValueChanged<DatasetImage?> onSelect;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;

  const _ImageList({
    required this.images,
    required this.selected,
    required this.onSelect,
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;

    if (images.isEmpty && !loadingMore) {
      return Center(
        child: Text(
          l10n.noImages,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
      );
    }

    // +1 for the "load more" sentinel when there are more pages
    final itemCount = images.length + (hasMore ? 1 : 0);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (hasMore &&
            !loadingMore &&
            notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 200) {
          onLoadMore();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index >= images.length) {
            // Loading more indicator
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final img = images[index];
          final isSelected = selected?.path == img.path;
          return InkWell(
            onTap: () => onSelect(img),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? cs.surfaceContainerHighest : Colors.transparent,
                border: Border(
                  left: BorderSide(
                    color:
                        isSelected ? cs.primary : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: img.eyeSide == 'left'
                          ? cs.primary.withValues(alpha: 0.2)
                          : semantic.success.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      img.eyeSide == 'left' ? l10n.eyeSideShortLeft : l10n.eyeSideShortRight,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: img.eyeSide == 'left'
                            ? cs.primary
                            : semantic.success,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      img.filename,
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ThumbnailGrid extends StatelessWidget {
  final List<DatasetImage> images;
  final DatasetImage? selected;
  final GatewayClient client;
  final String datasetName;
  final ValueChanged<DatasetImage?> onSelect;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;

  const _ThumbnailGrid({
    required this.images,
    required this.selected,
    required this.client,
    required this.datasetName,
    required this.onSelect,
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;

    if (images.isEmpty && !loadingMore) {
      return Center(
        child: Text(
          l10n.noImages,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (hasMore &&
            !loadingMore &&
            notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 200) {
          onLoadMore();
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 70,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: images.length,
        itemBuilder: (context, index) {
          final img = images[index];
          final isSelected = selected?.path == img.path;
          final url = client.getDatasetImageUrl(datasetName, img.path);

          return InkWell(
            key: ValueKey(img.path),
            onTap: () => onSelect(img),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected ? cs.primary : cs.outlineVariant,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => Center(
                        child: Icon(Icons.broken_image,
                            size: 16, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        img.eyeSide == 'left' ? l10n.eyeSideShortLeft : l10n.eyeSideShortRight,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: img.eyeSide == 'left'
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
        },
      ),
    );
  }
}
