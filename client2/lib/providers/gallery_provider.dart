import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enrollment.dart';
import 'api_client_provider.dart';

class GalleryNotifier extends StateNotifier<AsyncValue<List<GalleryIdentity>>> {
  final Ref _ref;

  GalleryNotifier(this._ref) : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    if (!state.hasValue) {
      state = const AsyncValue.loading();
    }
    try {
      final list = await _ref.read(apiClientProvider).listGallery();
      state = AsyncValue.data(list);
    } catch (e, st) {
      if (!state.hasValue) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> deleteIdentity(String identityId) async {
    try {
      await _ref.read(apiClientProvider).deleteIdentity(identityId);
      await refresh();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final galleryProvider =
    StateNotifierProvider<GalleryNotifier, AsyncValue<List<GalleryIdentity>>>(
        (ref) {
  return GalleryNotifier(ref);
});
