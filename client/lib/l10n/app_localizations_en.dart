// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'EyeD - Iris Recognition';

  @override
  String get brandName => 'EyeD';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get devices => 'Devices';

  @override
  String get enrollment => 'Enrollment';

  @override
  String get analysis => 'Analysis';

  @override
  String get history => 'History';

  @override
  String get admin => 'Admin';

  @override
  String get framesProcessed => 'Frames Processed';

  @override
  String get matches => 'Matches';

  @override
  String get errors => 'Errors';

  @override
  String get liveResults => 'Live Results';

  @override
  String get waitingForResults => 'Waiting for results...';

  @override
  String get noDevicesDetected =>
      'No devices detected yet.\nDevices appear automatically when they send frames.';

  @override
  String get frames => 'Frames';

  @override
  String get hd => 'HD';

  @override
  String get latency => 'Latency';

  @override
  String get identityName => 'Identity Name';

  @override
  String get eyeSideLeft => 'Left';

  @override
  String get eyeSideRight => 'Right';

  @override
  String get enroll => 'Enroll';

  @override
  String get selectImageFromBrowser => 'Select an image from the browser';

  @override
  String get gallery => 'Gallery';

  @override
  String get noIdentitiesEnrolled => 'No identities enrolled yet.';

  @override
  String get delete => 'Delete';

  @override
  String duplicateDetected(String duplicateIdentityId) {
    return 'Duplicate detected ($duplicateIdentityId)';
  }

  @override
  String enrolled(String templateId) {
    return 'Enrolled: $templateId';
  }

  @override
  String get analyze => 'Analyze';

  @override
  String get selectImageAndAnalyze => 'Select an image and click Analyze';

  @override
  String get segmentation => 'Segmentation';

  @override
  String get original => 'Original';

  @override
  String get pipelineOutputs => 'Pipeline Outputs';

  @override
  String get normalizedIris => 'Normalized Iris';

  @override
  String get irisCode => 'Iris Code';

  @override
  String get noiseMask => 'Noise Mask';

  @override
  String get qualityMetrics => 'Quality Metrics';

  @override
  String get sharpness => 'Sharpness';

  @override
  String get offgaze => 'Offgaze';

  @override
  String get occlusion90 => 'Occlusion 90';

  @override
  String get occlusion30 => 'Occlusion 30';

  @override
  String get pupilIrisRatio => 'Pupil/Iris Ratio';

  @override
  String get geometry => 'Geometry';

  @override
  String get pupilCenter => 'Pupil Center';

  @override
  String get irisCenter => 'Iris Center';

  @override
  String get pupilRadius => 'Pupil Radius';

  @override
  String get irisRadius => 'Iris Radius';

  @override
  String get eyeOrientation => 'Eye Orientation';

  @override
  String get noGalleryTemplates =>
      'No gallery templates — enroll identities first';

  @override
  String get noMatch => 'No match';

  @override
  String hdValue(String hd) {
    return 'HD: $hd';
  }

  @override
  String matchIdentity(String id) {
    return 'Match ($id)';
  }

  @override
  String get filterAll => 'all';

  @override
  String get filterMatch => 'match';

  @override
  String get filterNoMatch => 'no-match';

  @override
  String get filterError => 'error';

  @override
  String get searchPlaceholder => 'Search device, frame, identity...';

  @override
  String get headerTime => 'Time';

  @override
  String get headerDevice => 'Device';

  @override
  String get headerFrame => 'Frame';

  @override
  String get headerHd => 'HD';

  @override
  String get headerStatus => 'Status';

  @override
  String get headerLatency => 'Latency';

  @override
  String get noResultsMatchFilter => 'No results match the current filter.';

  @override
  String get pollingEvery5s => 'Polling every 5s';

  @override
  String get serviceGateway => 'Gateway';

  @override
  String get serviceIrisEngine => 'Iris Engine';

  @override
  String get serviceNats => 'NATS';

  @override
  String get alive => 'Alive';

  @override
  String get ready => 'Ready';

  @override
  String get nats => 'NATS';

  @override
  String get circuitBreaker => 'Circuit Breaker';

  @override
  String get version => 'Version';

  @override
  String get pipeline => 'Pipeline';

  @override
  String get gallerySize => 'Gallery Size';

  @override
  String get database => 'Database';

  @override
  String get status => 'Status';

  @override
  String get clientPort => 'Client Port';

  @override
  String get monitorPort => 'Monitor Port';

  @override
  String get unreachable => 'Unreachable';

  @override
  String get connected => 'Connected';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get unknown => 'Unknown';

  @override
  String get natsClientPortInfo => '4222 (internal) / 9502 (host)';

  @override
  String get natsMonitorPortInfo => '8222 (internal) / 9501 (host)';

  @override
  String get notFoundCode => '404';

  @override
  String get pageNotFound => 'Page not found';

  @override
  String get statusLive => 'Live';

  @override
  String get statusOffline => 'Offline';

  @override
  String get videoLive => 'LIVE';

  @override
  String get videoConnecting => 'CONNECTING';

  @override
  String get videoWaiting => 'WAITING';

  @override
  String get videoOffline => 'OFFLINE';

  @override
  String get waitingForVideo => 'Waiting for video...';

  @override
  String get noImages => 'No images';

  @override
  String get eyeSideShortLeft => 'L';

  @override
  String get eyeSideShortRight => 'R';

  @override
  String errorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String get noMatchData => 'No match data';

  @override
  String get languageName => 'English';

  @override
  String get datasetPaths => 'Dataset Directories';

  @override
  String get datasetPathsPrimary => 'Primary';

  @override
  String get datasetPathsExtra => 'Extra';

  @override
  String get addDirectory => 'Add Directory';

  @override
  String get remove => 'Remove';

  @override
  String get enterAbsolutePath => 'Enter absolute path (e.g. /data/MyDataset)';

  @override
  String get add => 'Add';

  @override
  String get cancel => 'Cancel';

  @override
  String get pathAlreadyRegistered => 'Path already registered';

  @override
  String datasetsCount(int count) {
    return '$count datasets';
  }

  @override
  String get directoryNotFound => 'Directory not found';

  @override
  String get close => 'Close';

  @override
  String get bulkEnroll => 'Bulk Enroll';

  @override
  String get bulkEnrollStart => 'Start';

  @override
  String get bulkEnrollSubjectFilter =>
      'Filter subjects (comma-separated, e.g. 000,001,002) — leave empty for all';

  @override
  String get bulkEnrolled => 'enrolled';

  @override
  String get bulkDuplicate => 'duplicate';

  @override
  String bulkEnrollComplete(int enrolled, int duplicates, int errors) {
    return 'Complete: $enrolled enrolled, $duplicates duplicates, $errors errors';
  }

  @override
  String get bulkEnrollRunning => 'Enrolling...';

  @override
  String bulkEnrollProgress(int processed) {
    return 'Enrolling $processed';
  }

  @override
  String get refresh => 'Refresh';

  @override
  String get identityDetails => 'Identity Details';

  @override
  String get templateId => 'Template ID';

  @override
  String get eyeSide => 'Eye Side';

  @override
  String get identityId => 'Identity ID';

  @override
  String get templates => 'Templates';

  @override
  String get noTemplates => 'No templates';

  @override
  String get codeSize => 'Code Size';

  @override
  String get scales => 'Scales';

  @override
  String get deviceId => 'Device ID';

  @override
  String get loading => 'Loading...';

  @override
  String get maskCode => 'Mask Code';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get connectionLost => 'Connection Lost';

  @override
  String get connectionLostDesc => 'Unable to reach the backend services.';

  @override
  String get reconnect => 'Reconnect';

  @override
  String get reconnecting => 'Reconnecting...';

  @override
  String reconnectCountdown(int seconds) {
    return 'Reconnect (${seconds}s)';
  }

  @override
  String connectionRetryCount(int current, int max) {
    return 'Attempt $current of $max';
  }

  @override
  String get dbInspector => 'DB Inspector';

  @override
  String get dbSchema => 'Schema';

  @override
  String get dbBrowse => 'Browse';

  @override
  String get dbHeGuide => 'HE Guide';

  @override
  String get dbSelectTable => 'Select table...';

  @override
  String dbRowsTotal(int count) {
    return '$count rows total';
  }

  @override
  String get dbRelationships => 'Relationships';

  @override
  String get dbPrimaryKey => 'PK';

  @override
  String get dbForeignKey => 'FK';

  @override
  String get dbHeEncrypted => 'HE Encrypted';

  @override
  String get dbPlaintextNpz => 'Plaintext NPZ';

  @override
  String get dbSize => 'Size';

  @override
  String get dbFormat => 'Format';

  @override
  String get dbCiphertexts => 'Ciphertexts';

  @override
  String get dbHexPrefix => 'Hex prefix';

  @override
  String get dbRelatedData => 'Related data';

  @override
  String get dbSelectTablePrompt => 'Select a table to browse rows';

  @override
  String get individualEnroll => 'Individual';

  @override
  String get bulkEnrollTab => 'Bulk Enroll';

  @override
  String get galleryTab => 'Gallery';

  @override
  String get leftEye => 'Left Eye';

  @override
  String get rightEye => 'Right Eye';

  @override
  String get loadFromDisk => 'Load from disk';

  @override
  String get notApplicable => 'N/A';

  @override
  String get atLeastOneEyeRequired => 'At least one eye image is required';

  @override
  String get segmentationFailed =>
      'Iris not found. Please select a better quality image.';

  @override
  String duplicateUserDetected(String name) {
    return 'Duplicate detected: already enrolled as $name';
  }

  @override
  String enrollSuccess(int count) {
    return 'Enrolled successfully ($count template(s))';
  }

  @override
  String get selectLocalDirectory => 'Select Directory';

  @override
  String get localBulkEnroll => 'Local Directory';

  @override
  String get serverBulkEnroll => 'Server Dataset';

  @override
  String get scanningDirectory => 'Scanning directory...';

  @override
  String subjectsFound(int count) {
    return '$count subjects found';
  }

  @override
  String enrollingSubject(int current, int total, String name) {
    return 'Enrolling $current of $total: $name';
  }

  @override
  String localBulkComplete(int enrolled, int duplicates, int errors) {
    return 'Complete: $enrolled enrolled, $duplicates duplicates, $errors errors';
  }

  @override
  String get noSubjectsFound => 'No valid subjects found in directory';

  @override
  String get startEnroll => 'Start Enroll';
}
