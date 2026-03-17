import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/enrollment.dart';
import 'gallery_provider.dart';
import 'gateway_client_provider.dart';

class IndividualEnrollState {
  final Uint8List? leftImageBytes;
  final String? leftImageName;
  final bool leftIsNA;

  final Uint8List? rightImageBytes;
  final String? rightImageName;
  final bool rightIsNA;

  final String identityName;
  final bool enrolling;
  final List<EnrollResponse> results;
  final String? error;

  const IndividualEnrollState({
    this.leftImageBytes,
    this.leftImageName,
    this.leftIsNA = false,
    this.rightImageBytes,
    this.rightImageName,
    this.rightIsNA = false,
    this.identityName = '',
    this.enrolling = false,
    this.results = const [],
    this.error,
  });

  bool get canEnroll =>
      identityName.trim().isNotEmpty &&
      !enrolling &&
      ((leftImageBytes != null && !leftIsNA) ||
          (rightImageBytes != null && !rightIsNA));

  IndividualEnrollState copyWith({
    Uint8List? Function()? leftImageBytes,
    String? Function()? leftImageName,
    bool? leftIsNA,
    Uint8List? Function()? rightImageBytes,
    String? Function()? rightImageName,
    bool? rightIsNA,
    String? identityName,
    bool? enrolling,
    List<EnrollResponse>? results,
    String? Function()? error,
  }) {
    return IndividualEnrollState(
      leftImageBytes:
          leftImageBytes != null ? leftImageBytes() : this.leftImageBytes,
      leftImageName:
          leftImageName != null ? leftImageName() : this.leftImageName,
      leftIsNA: leftIsNA ?? this.leftIsNA,
      rightImageBytes:
          rightImageBytes != null ? rightImageBytes() : this.rightImageBytes,
      rightImageName:
          rightImageName != null ? rightImageName() : this.rightImageName,
      rightIsNA: rightIsNA ?? this.rightIsNA,
      identityName: identityName ?? this.identityName,
      enrolling: enrolling ?? this.enrolling,
      results: results ?? this.results,
      error: error != null ? error() : this.error,
    );
  }
}

class IndividualEnrollNotifier extends StateNotifier<IndividualEnrollState> {
  final Ref _ref;

  IndividualEnrollNotifier(this._ref) : super(const IndividualEnrollState());

  void setLeftImage(Uint8List bytes, String filename) {
    state = state.copyWith(
      leftImageBytes: () => bytes,
      leftImageName: () => filename,
      leftIsNA: false,
      error: () => null,
    );
  }

  void setRightImage(Uint8List bytes, String filename) {
    state = state.copyWith(
      rightImageBytes: () => bytes,
      rightImageName: () => filename,
      rightIsNA: false,
      error: () => null,
    );
  }

  void toggleLeftNA(bool isNA) {
    state = state.copyWith(
      leftIsNA: isNA,
      leftImageBytes: isNA ? () => null : null,
      leftImageName: isNA ? () => null : null,
      error: () => null,
    );
  }

  void toggleRightNA(bool isNA) {
    state = state.copyWith(
      rightIsNA: isNA,
      rightImageBytes: isNA ? () => null : null,
      rightImageName: isNA ? () => null : null,
      error: () => null,
    );
  }

  void setIdentityName(String name) {
    state = state.copyWith(identityName: name);
  }

  Future<void> enroll() async {
    if (!state.canEnroll) return;

    state = state.copyWith(
      enrolling: true,
      results: [],
      error: () => null,
    );

    final client = _ref.read(gatewayClientProvider);
    final identityId = const Uuid().v4();
    final results = <EnrollResponse>[];

    try {
      // Enroll left eye if available and not N/A
      if (state.leftImageBytes != null && !state.leftIsNA) {
        final b64 = base64Encode(state.leftImageBytes!);
        final result = await client.enroll(
          jpegB64: b64,
          eyeSide: 'left',
          identityId: identityId,
          identityName: state.identityName.trim(),
        );
        results.add(result);

        if (result.error != null) {
          state = state.copyWith(
            enrolling: false,
            results: results,
            error: () => result.error,
          );
          return;
        }
        if (result.isDuplicate) {
          state = state.copyWith(
            enrolling: false,
            results: results,
          );
          return;
        }
      }

      // Enroll right eye if available and not N/A
      if (state.rightImageBytes != null && !state.rightIsNA) {
        final b64 = base64Encode(state.rightImageBytes!);
        final result = await client.enroll(
          jpegB64: b64,
          eyeSide: 'right',
          identityId: identityId,
          identityName: state.identityName.trim(),
        );
        results.add(result);

        if (result.error != null) {
          state = state.copyWith(
            enrolling: false,
            results: results,
            error: () => result.error,
          );
          return;
        }
        if (result.isDuplicate) {
          state = state.copyWith(
            enrolling: false,
            results: results,
          );
          return;
        }
      }

      // Success — clear form but keep results visible
      state = IndividualEnrollState(
        enrolling: false,
        results: results,
      );

      _ref.read(galleryProvider.notifier).refresh();
    } catch (e) {
      state = state.copyWith(
        enrolling: false,
        results: results,
        error: () => e.toString(),
      );
    }
  }

  void reset() {
    state = const IndividualEnrollState();
  }
}

final individualEnrollProvider =
    StateNotifierProvider<IndividualEnrollNotifier, IndividualEnrollState>(
        (ref) {
  return IndividualEnrollNotifier(ref);
});
