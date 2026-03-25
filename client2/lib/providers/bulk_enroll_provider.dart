import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'api_client_provider.dart';
import 'gallery_provider.dart';

class BulkPickedFile {
  final String relativePath;
  final Uint8List bytes;

  const BulkPickedFile({required this.relativePath, required this.bytes});
}

class BulkSubject {
  final String name;
  final String? leftPath;
  final String? rightPath;
  final Uint8List? leftBytes;
  final Uint8List? rightBytes;

  const BulkSubject({
    required this.name,
    this.leftPath,
    this.rightPath,
    this.leftBytes,
    this.rightBytes,
  });
}

class BulkEnrollState {
  final bool running;
  final int current;
  final int total;
  final int enrolled;
  final int skipped;
  final int errors;
  final String? selectedDir;
  final List<BulkSubject> subjects;

  const BulkEnrollState({
    this.running = false,
    this.current = 0,
    this.total = 0,
    this.enrolled = 0,
    this.skipped = 0,
    this.errors = 0,
    this.selectedDir,
    this.subjects = const [],
  });

  bool get idle => !running && total == 0;
  bool get done => !running && total > 0 && current >= total;

  BulkEnrollState copyWith({
    bool? running,
    int? current,
    int? total,
    int? enrolled,
    int? skipped,
    int? errors,
    String? selectedDir,
    List<BulkSubject>? subjects,
  }) =>
      BulkEnrollState(
        running: running ?? this.running,
        current: current ?? this.current,
        total: total ?? this.total,
        enrolled: enrolled ?? this.enrolled,
        skipped: skipped ?? this.skipped,
        errors: errors ?? this.errors,
        selectedDir: selectedDir ?? this.selectedDir,
        subjects: subjects ?? this.subjects,
      );
}

class BulkEnrollNotifier extends StateNotifier<BulkEnrollState> {
  final Ref _ref;

  BulkEnrollNotifier(this._ref) : super(const BulkEnrollState());

  /// Scan a directory for subjects with l/ and r/ sub-directories.
  Future<void> scanDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    final subjects = <BulkSubject>[];
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final username = entity.path.split(Platform.pathSeparator).last;

      String? leftPath;
      String? rightPath;

      // Check for left eye images (l/ or L/)
      for (final sub in ['l', 'L']) {
        final subDir = Directory('${entity.path}${Platform.pathSeparator}$sub');
        if (await subDir.exists()) {
          leftPath = await _firstImage(subDir);
          if (leftPath != null) break;
        }
      }

      // Check for right eye images (r/ or R/)
      for (final sub in ['r', 'R']) {
        final subDir = Directory('${entity.path}${Platform.pathSeparator}$sub');
        if (await subDir.exists()) {
          rightPath = await _firstImage(subDir);
          if (rightPath != null) break;
        }
      }

      // Need at least one eye
      if (leftPath != null || rightPath != null) {
        subjects.add(BulkSubject(
          name: username,
          leftPath: leftPath,
          rightPath: rightPath,
        ));
      }
    }

    // Sort by name (case insensitive)
    subjects.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    state = BulkEnrollState(
      selectedDir: dirPath,
      subjects: subjects,
      total: subjects.length,
    );
  }

  /// Scan browser-picked files from a selected directory.
  ///
  /// Expected relative structure: <root>/<subject>/<l|r>/<image-file>
  Future<void> scanPickedFiles(List<BulkPickedFile> pickedFiles,
      {String? selectedLabel}) async {
    final bySubject = <String, _BulkSubjectBuilder>{};

    for (final picked in pickedFiles) {
      final normalized = picked.relativePath.replaceAll('\\', '/');
      if (!_isSupportedImage(normalized)) continue;

      final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.length < 3) continue;

      for (var i = 1; i < parts.length - 1; i++) {
        final side = parts[i].toLowerCase();
        if (side != 'l' && side != 'r') continue;

        final subjectName = parts[i - 1];
        final builder = bySubject.putIfAbsent(
            subjectName, () => _BulkSubjectBuilder(name: subjectName));

        if (side == 'l' && builder.leftBytes == null) {
          builder.leftBytes = picked.bytes;
        } else if (side == 'r' && builder.rightBytes == null) {
          builder.rightBytes = picked.bytes;
        }
        break;
      }
    }

    final subjects = bySubject.values
        .where((s) => s.leftBytes != null || s.rightBytes != null)
        .map((s) => BulkSubject(
              name: s.name,
              leftBytes: s.leftBytes,
              rightBytes: s.rightBytes,
            ))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    state = BulkEnrollState(
      selectedDir: selectedLabel,
      subjects: subjects,
      total: subjects.length,
    );
  }

  bool _isSupportedImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.bmp');
  }

  Future<String?> _firstImage(Directory dir) async {
    final extensions = {'.jpg', '.jpeg', '.png', '.bmp'};
    await for (final entity in dir.list()) {
      if (entity is File) {
        final lower = entity.path.toLowerCase();
        if (extensions.any((ext) => lower.endsWith(ext))) {
          return entity.path;
        }
      }
    }
    return null;
  }

  /// Start bulk enrollment in background.
  Future<void> start() async {
    if (state.running || state.subjects.isEmpty) return;

    state = state.copyWith(running: true, current: 0, enrolled: 0, skipped: 0, errors: 0);

    final client = _ref.read(apiClientProvider);
    const uuid = Uuid();

    for (var i = 0; i < state.subjects.length; i++) {
      if (!state.running) break; // cancelled

      final subject = state.subjects[i];
      final identityId = uuid.v4();
      var subEnrolled = false;

      try {
        var isDuplicate = false;

        // Enroll left
        if (subject.leftPath != null || subject.leftBytes != null) {
          final bytes = subject.leftBytes ?? await File(subject.leftPath!).readAsBytes();
          final resp = await client.enroll(
            jpegB64: base64Encode(bytes),
            eyeSide: 'left',
            identityId: identityId,
            identityName: subject.name,
          );
          if (resp.isDuplicate) {
            isDuplicate = true;
          } else if (resp.error == null) {
            subEnrolled = true;
          }
        }

        // Enroll right (skip if left was duplicate)
        if ((subject.rightPath != null || subject.rightBytes != null) && !isDuplicate) {
          final bytes =
              subject.rightBytes ?? await File(subject.rightPath!).readAsBytes();
          final resp = await client.enroll(
            jpegB64: base64Encode(bytes),
            eyeSide: 'right',
            identityId: identityId,
            identityName: subject.name,
          );
          if (resp.isDuplicate) {
            isDuplicate = true;
          } else if (resp.error == null) {
            subEnrolled = true;
          }
        }

        state = state.copyWith(
          current: i + 1,
          enrolled: subEnrolled && !isDuplicate ? state.enrolled + 1 : state.enrolled,
          skipped: isDuplicate || !subEnrolled ? state.skipped + 1 : state.skipped,
        );
      } catch (_) {
        state = state.copyWith(
          current: i + 1,
          errors: state.errors + 1,
        );
      }
    }

    state = state.copyWith(running: false);

    // Refresh gallery so newly enrolled identities appear
    _ref.read(galleryProvider.notifier).refresh();
  }

  void cancel() {
    state = state.copyWith(running: false);
  }

  void reset() {
    state = const BulkEnrollState();
  }
}

class _BulkSubjectBuilder {
  final String name;
  Uint8List? leftBytes;
  Uint8List? rightBytes;

  _BulkSubjectBuilder({required this.name});
}

final bulkEnrollProvider =
    StateNotifierProvider<BulkEnrollNotifier, BulkEnrollState>((ref) {
  return BulkEnrollNotifier(ref);
});
