import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dataset.dart';
import '../services/gateway_client.dart';
import 'gateway_client_provider.dart';

const _pageSize = 100;

class DatasetBrowserState {
  final List<DatasetInfo> datasets;
  final String selectedDataset;
  final List<SubjectInfo> subjects;
  final String? selectedSubject;
  final List<DatasetImage> images;
  final DatasetImage? selectedImage;
  final bool loading;
  final bool loadingImages;
  final bool hasMoreImages;
  final int imageOffset;

  const DatasetBrowserState({
    this.datasets = const [],
    this.selectedDataset = '',
    this.subjects = const [],
    this.selectedSubject,
    this.images = const [],
    this.selectedImage,
    this.loading = false,
    this.loadingImages = false,
    this.hasMoreImages = false,
    this.imageOffset = 0,
  });

  List<DatasetImage> get filteredImages {
    if (selectedSubject == null) return images;
    return images
        .where((img) => img.subjectId == selectedSubject)
        .toList();
  }

  DatasetBrowserState copyWith({
    List<DatasetInfo>? datasets,
    String? selectedDataset,
    List<SubjectInfo>? subjects,
    String? Function()? selectedSubject,
    List<DatasetImage>? images,
    DatasetImage? Function()? selectedImage,
    bool? loading,
    bool? loadingImages,
    bool? hasMoreImages,
    int? imageOffset,
  }) {
    return DatasetBrowserState(
      datasets: datasets ?? this.datasets,
      selectedDataset: selectedDataset ?? this.selectedDataset,
      subjects: subjects ?? this.subjects,
      selectedSubject:
          selectedSubject != null ? selectedSubject() : this.selectedSubject,
      images: images ?? this.images,
      selectedImage:
          selectedImage != null ? selectedImage() : this.selectedImage,
      loading: loading ?? this.loading,
      loadingImages: loadingImages ?? this.loadingImages,
      hasMoreImages: hasMoreImages ?? this.hasMoreImages,
      imageOffset: imageOffset ?? this.imageOffset,
    );
  }
}

class DatasetBrowserNotifier extends StateNotifier<DatasetBrowserState> {
  final GatewayClient _client;

  DatasetBrowserNotifier(this._client)
      : super(const DatasetBrowserState()) {
    _loadDatasets();
  }

  Future<void> _loadDatasets() async {
    state = state.copyWith(loading: true);
    try {
      final datasets = await _client.listDatasets();
      state = state.copyWith(datasets: datasets, loading: false);
      if (datasets.isNotEmpty) {
        await selectDataset(datasets.first.name);
      }
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  Future<void> selectDataset(String name) async {
    state = state.copyWith(
      selectedDataset: name,
      subjects: [],
      selectedSubject: () => null,
      images: [],
      selectedImage: () => null,
      loading: true,
      hasMoreImages: false,
      imageOffset: 0,
    );
    try {
      final subjects = await _client.listDatasetSubjects(name);
      state = state.copyWith(subjects: subjects, loading: false);
      // Load first page of images (no subject filter)
      await _loadImages(reset: true);
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  Future<void> selectSubject(String? subject) async {
    state = state.copyWith(
      selectedSubject: () => subject,
      selectedImage: () => null,
      images: [],
      hasMoreImages: false,
      imageOffset: 0,
    );
    await _loadImages(reset: true);
  }

  Future<void> _loadImages({bool reset = false}) async {
    if (state.selectedDataset.isEmpty) return;
    if (state.loadingImages) return;

    final offset = reset ? 0 : state.imageOffset;
    state = state.copyWith(loadingImages: true);
    try {
      final page = await _client.listDatasetImages(
        state.selectedDataset,
        subject: state.selectedSubject,
        offset: offset,
        limit: _pageSize,
      );
      final merged = reset ? page : [...state.images, ...page];
      state = state.copyWith(
        images: merged,
        loadingImages: false,
        hasMoreImages: page.length >= _pageSize,
        imageOffset: offset + page.length,
      );
    } catch (_) {
      state = state.copyWith(loadingImages: false);
    }
  }

  Future<void> loadMoreImages() async {
    if (!state.hasMoreImages || state.loadingImages) return;
    await _loadImages();
  }

  void selectImage(DatasetImage? image) {
    state = state.copyWith(selectedImage: () => image);
  }

  /// Reload datasets and current selection from the server.
  Future<void> refresh() async {
    final currentDataset = state.selectedDataset;
    await _loadDatasets();
    // Re-select the previous dataset if it still exists
    if (currentDataset.isNotEmpty &&
        state.datasets.any((d) => d.name == currentDataset)) {
      await selectDataset(currentDataset);
    }
  }
}

final enrollmentBrowserProvider =
    StateNotifierProvider<DatasetBrowserNotifier, DatasetBrowserState>((ref) {
  return DatasetBrowserNotifier(ref.read(gatewayClientProvider));
});

final analysisBrowserProvider =
    StateNotifierProvider<DatasetBrowserNotifier, DatasetBrowserState>((ref) {
  return DatasetBrowserNotifier(ref.read(gatewayClientProvider));
});
