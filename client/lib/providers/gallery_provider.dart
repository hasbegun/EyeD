import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enrollment.dart';
import 'gateway_client_provider.dart';

class GalleryNotifier extends StateNotifier<AsyncValue<List<GalleryIdentity>>> {
  final Ref _ref;

  GalleryNotifier(this._ref) : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final list = await _ref.read(gatewayClientProvider).listGallery();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteIdentity(String identityId) async {
    try {
      await _ref.read(gatewayClientProvider).deleteIdentity(identityId);
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
