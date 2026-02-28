import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/enrollment.dart';
import 'gallery_provider.dart';
import 'gateway_client_provider.dart';

class LocalSubject {
  final String name;
  final String? leftImagePath;
  final String? rightImagePath;

  const LocalSubject({
    required this.name,
    this.leftImagePath,
    this.rightImagePath,
  });

  bool get hasImages => leftImagePath != null || rightImagePath != null;
}

class LocalBulkResult {
  final String subjectName;
  final String eyeSide;
  final String status; // 'enrolled', 'duplicate', 'error'
  final String? detail;

  const LocalBulkResult({
    required this.subjectName,
    required this.eyeSide,
    required this.status,
    this.detail,
  });
}

class LocalBulkEnrollState {
  final bool scanning;
  final bool enrolling;
  final bool cancelled;
  final String? directoryPath;
  final List<LocalSubject> subjects;
  final int currentIndex;
  final int enrolled;
  final int duplicates;
  final int errors;
  final List<LocalBulkResult> reportEntries;
  final String? error;

  const LocalBulkEnrollState({
    this.scanning = false,
    this.enrolling = false,
    this.cancelled = false,
    this.directoryPath,
    this.subjects = const [],
    this.currentIndex = 0,
    this.enrolled = 0,
    this.duplicates = 0,
    this.errors = 0,
    this.reportEntries = const [],
    this.error,
  });

  bool get idle => !scanning && !enrolling && !done;
  bool get done =>
      !enrolling &&
      !scanning &&
      subjects.isNotEmpty &&
      (currentIndex >= subjects.length || cancelled);
  int get processed => currentIndex;

  LocalBulkEnrollState copyWith({
    bool? scanning,
    bool? enrolling,
    bool? cancelled,
    String? Function()? directoryPath,
    List<LocalSubject>? subjects,
    int? currentIndex,
    int? enrolled,
    int? duplicates,
    int? errors,
    List<LocalBulkResult>? reportEntries,
    String? Function()? error,
  }) {
    return LocalBulkEnrollState(
      scanning: scanning ?? this.scanning,
      enrolling: enrolling ?? this.enrolling,
      cancelled: cancelled ?? this.cancelled,
      directoryPath:
          directoryPath != null ? directoryPath() : this.directoryPath,
      subjects: subjects ?? this.subjects,
      currentIndex: currentIndex ?? this.currentIndex,
      enrolled: enrolled ?? this.enrolled,
      duplicates: duplicates ?? this.duplicates,
      errors: errors ?? this.errors,
      reportEntries: reportEntries ?? this.reportEntries,
      error: error != null ? error() : this.error,
    );
  }
}

const _imageExtensions = {'.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.tif'};

class LocalBulkEnrollNotifier extends StateNotifier<LocalBulkEnrollState> {
  final Ref _ref;

  LocalBulkEnrollNotifier(this._ref) : super(const LocalBulkEnrollState());

  Future<void> scanDirectory(String path) async {
    state = LocalBulkEnrollState(scanning: true, directoryPath: path);

    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        state = state.copyWith(
          scanning: false,
          error: () => 'Directory not found',
        );
        return;
      }

      final subjects = <LocalSubject>[];
      final children = await dir.list().toList();
      children.sort((a, b) => a.path.compareTo(b.path));

      for (final entity in children) {
        if (entity is! Directory) continue;
        final name = entity.path.split(Platform.pathSeparator).last;

        String? leftImage;
        String? rightImage;

        // Find L/R subdirectories (case-insensitive)
        final subDirs = await entity.list().toList();
        for (final sub in subDirs) {
          if (sub is! Directory) continue;
          final subName =
              sub.path.split(Platform.pathSeparator).last.toLowerCase();

          if (subName == 'l' || subName == 'left') {
            leftImage = await _findFirstImage(sub);
          } else if (subName == 'r' || subName == 'right') {
            rightImage = await _findFirstImage(sub);
          }
        }

        subjects.add(LocalSubject(
          name: name,
          leftImagePath: leftImage,
          rightImagePath: rightImage,
        ));
      }

      state = state.copyWith(
        scanning: false,
        subjects: subjects,
      );
    } catch (e) {
      state = state.copyWith(
        scanning: false,
        error: () => e.toString(),
      );
    }
  }

  Future<String?> _findFirstImage(Directory dir) async {
    final files = <FileSystemEntity>[];
    await for (final f in dir.list()) {
      if (f is File) {
        final ext = f.path.split('.').last.toLowerCase();
        if (_imageExtensions.contains('.$ext')) {
          files.add(f);
        }
      }
    }
    if (files.isEmpty) return null;
    files.sort((a, b) => a.path.compareTo(b.path));
    return files.first.path;
  }

  Future<void> startEnroll() async {
    if (state.subjects.isEmpty) return;

    state = state.copyWith(
      enrolling: true,
      cancelled: false,
      currentIndex: 0,
      enrolled: 0,
      duplicates: 0,
      errors: 0,
      reportEntries: [],
      error: () => null,
    );

    final client = _ref.read(gatewayClientProvider);

    for (var i = 0; i < state.subjects.length; i++) {
      if (!mounted || state.cancelled) break;

      final subject = state.subjects[i];
      state = state.copyWith(currentIndex: i);

      if (!subject.hasImages) {
        state = state.copyWith(
          errors: state.errors + 1,
          reportEntries: [
            ...state.reportEntries,
            LocalBulkResult(
              subjectName: subject.name,
              eyeSide: '-',
              status: 'error',
              detail: 'No images found',
            ),
          ],
        );
        continue;
      }

      final identityId = const Uuid().v4();

      // Enroll left eye
      if (subject.leftImagePath != null) {
        await _enrollEye(
          client: client,
          imagePath: subject.leftImagePath!,
          eyeSide: 'left',
          identityId: identityId,
          identityName: subject.name,
          subjectName: subject.name,
        );
      }

      if (!mounted || state.cancelled) break;

      // Enroll right eye
      if (subject.rightImagePath != null) {
        await _enrollEye(
          client: client,
          imagePath: subject.rightImagePath!,
          eyeSide: 'right',
          identityId: identityId,
          identityName: subject.name,
          subjectName: subject.name,
        );
      }
    }

    if (mounted) {
      state = state.copyWith(
        enrolling: false,
        currentIndex: state.cancelled ? state.currentIndex : state.subjects.length,
      );
      _ref.read(galleryProvider.notifier).refresh();
    }
  }

  Future<void> _enrollEye({
    required dynamic client,
    required String imagePath,
    required String eyeSide,
    required String identityId,
    required String identityName,
    required String subjectName,
  }) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final b64 = base64Encode(bytes);

      final result = await client.enroll(
        jpegB64: b64,
        eyeSide: eyeSide,
        identityId: identityId,
        identityName: identityName,
      ) as EnrollResponse;

      if (!mounted) return;

      if (result.error != null) {
        state = state.copyWith(
          errors: state.errors + 1,
          reportEntries: [
            ...state.reportEntries,
            LocalBulkResult(
              subjectName: subjectName,
              eyeSide: eyeSide,
              status: 'error',
              detail: result.error,
            ),
          ],
        );
      } else if (result.isDuplicate) {
        state = state.copyWith(
          duplicates: state.duplicates + 1,
          reportEntries: [
            ...state.reportEntries,
            LocalBulkResult(
              subjectName: subjectName,
              eyeSide: eyeSide,
              status: 'duplicate',
              detail: result.duplicateIdentityName ?? result.duplicateIdentityId,
            ),
          ],
        );
      } else {
        state = state.copyWith(enrolled: state.enrolled + 1);
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        errors: state.errors + 1,
        reportEntries: [
          ...state.reportEntries,
          LocalBulkResult(
            subjectName: subjectName,
            eyeSide: eyeSide,
            status: 'error',
            detail: e.toString(),
          ),
        ],
      );
    }
  }

  void cancel() {
    state = state.copyWith(cancelled: true);
  }

  void reset() {
    state = const LocalBulkEnrollState();
  }
}

final localBulkEnrollProvider =
    StateNotifierProvider<LocalBulkEnrollNotifier, LocalBulkEnrollState>((ref) {
  return LocalBulkEnrollNotifier(ref);
});
