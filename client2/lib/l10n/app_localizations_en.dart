// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'EyeD';

  @override
  String get enrollPage => 'Enroll';

  @override
  String get detectPage => 'Detect';

  @override
  String get tabIndividual => 'Individual';

  @override
  String get tabBulk => 'Bulk';

  @override
  String get tabGallery => 'Gallery';

  @override
  String get nameLabel => 'Name';

  @override
  String get nameRequired => 'Name is required';

  @override
  String get leftEye => 'Left Eye';

  @override
  String get rightEye => 'Right Eye';

  @override
  String get loadImage => 'Load Image';

  @override
  String get notAvailable => 'N/A';

  @override
  String get enroll => 'Enroll';

  @override
  String get enrolling => 'Enrolling...';

  @override
  String get enrollSuccess => 'Enrolled successfully';

  @override
  String get enrollSuccessEncrypted => 'Enrolled — template encrypted 🔒';

  @override
  String get enrollSuccessPlain => 'Enrolled — template plaintext';

  @override
  String enrollDuplicate(String name) {
    return 'Duplicate: matches $name';
  }

  @override
  String enrollError(String error) {
    return 'Enrollment failed: $error';
  }

  @override
  String get eyeRequired => 'At least one eye image is required';

  @override
  String get bulkSelectDir => 'Select Directory';

  @override
  String get bulkStart => 'Start Bulk Enroll';

  @override
  String bulkRunning(int current, int total) {
    return 'Enrolling... $current/$total';
  }

  @override
  String bulkComplete(int enrolled, int total, int skipped, int errors) {
    return 'Complete: $enrolled/$total enrolled, $skipped skipped, $errors errors';
  }

  @override
  String get bulkIdle => 'Select a directory to begin';

  @override
  String get bulkNoSubjects => 'No valid subjects found in directory';

  @override
  String get galleryRefresh => 'Refresh';

  @override
  String get galleryEmpty => 'No enrolled identities';

  @override
  String galleryCount(int count) {
    return '$count identities';
  }

  @override
  String get identityDetail => 'Identity Detail';

  @override
  String get templateDetail => 'Template Detail';

  @override
  String get eyeSide => 'Eye';

  @override
  String get qualityScore => 'Quality';

  @override
  String get deviceId => 'Device';

  @override
  String get dimensions => 'Dimensions';

  @override
  String get irisCode => 'Iris Code';

  @override
  String get maskCode => 'Mask Code';

  @override
  String get templateEncrypted => 'Encrypted (FHE)';

  @override
  String get templatePlaintext => 'Plaintext';

  @override
  String get encryptedNoPreview =>
      'Template is FHE-encrypted — iris code not available for preview';

  @override
  String get deleteIdentity => 'Delete';

  @override
  String deleteConfirm(String name) {
    return 'Delete identity \"$name\"?';
  }

  @override
  String get deleteConfirmBody =>
      'This will permanently remove this identity and all associated templates.';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get detectLoadImage => 'Load Iris Image';

  @override
  String get detectButton => 'Detect';

  @override
  String get detecting => 'Detecting...';

  @override
  String detectMatch(String name, String hd) {
    return 'Match: $name (HD: $hd)';
  }

  @override
  String get detectNoMatch => 'No match found';

  @override
  String detectError(String error) {
    return 'Detection failed: $error';
  }

  @override
  String get connectionError => 'Cannot connect to server';

  @override
  String get serverError => 'Server error';

  @override
  String get logPage => 'Log';

  @override
  String get logFilterAll => 'All';

  @override
  String get logFilterMatch => 'Match';

  @override
  String get logFilterNoMatch => 'No match';

  @override
  String get logFilterError => 'Error';

  @override
  String get logSearchPlaceholder => 'Search identity...';

  @override
  String get logHeaderTime => 'Time';

  @override
  String get logHeaderHd => 'HD';

  @override
  String get logHeaderStatus => 'Status';

  @override
  String get logHeaderLatency => 'Latency';

  @override
  String get logEmpty => 'No detection results yet.';

  @override
  String get logClear => 'Clear log';

  @override
  String get engine1Label => 'Engine 1';

  @override
  String get engine2Label => 'Engine 2';
}
