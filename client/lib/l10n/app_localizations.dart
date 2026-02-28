import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'EyeD - Iris Recognition'**
  String get appTitle;

  /// No description provided for @brandName.
  ///
  /// In en, this message translates to:
  /// **'EyeD'**
  String get brandName;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devices;

  /// No description provided for @enrollment.
  ///
  /// In en, this message translates to:
  /// **'Enrollment'**
  String get enrollment;

  /// No description provided for @analysis.
  ///
  /// In en, this message translates to:
  /// **'Analysis'**
  String get analysis;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @framesProcessed.
  ///
  /// In en, this message translates to:
  /// **'Frames Processed'**
  String get framesProcessed;

  /// No description provided for @matches.
  ///
  /// In en, this message translates to:
  /// **'Matches'**
  String get matches;

  /// No description provided for @errors.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get errors;

  /// No description provided for @liveResults.
  ///
  /// In en, this message translates to:
  /// **'Live Results'**
  String get liveResults;

  /// No description provided for @waitingForResults.
  ///
  /// In en, this message translates to:
  /// **'Waiting for results...'**
  String get waitingForResults;

  /// No description provided for @noDevicesDetected.
  ///
  /// In en, this message translates to:
  /// **'No devices detected yet.\nDevices appear automatically when they send frames.'**
  String get noDevicesDetected;

  /// No description provided for @frames.
  ///
  /// In en, this message translates to:
  /// **'Frames'**
  String get frames;

  /// No description provided for @hd.
  ///
  /// In en, this message translates to:
  /// **'HD'**
  String get hd;

  /// No description provided for @latency.
  ///
  /// In en, this message translates to:
  /// **'Latency'**
  String get latency;

  /// No description provided for @identityName.
  ///
  /// In en, this message translates to:
  /// **'Identity Name'**
  String get identityName;

  /// No description provided for @eyeSideLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get eyeSideLeft;

  /// No description provided for @eyeSideRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get eyeSideRight;

  /// No description provided for @enroll.
  ///
  /// In en, this message translates to:
  /// **'Enroll'**
  String get enroll;

  /// No description provided for @selectImageFromBrowser.
  ///
  /// In en, this message translates to:
  /// **'Select an image from the browser'**
  String get selectImageFromBrowser;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @noIdentitiesEnrolled.
  ///
  /// In en, this message translates to:
  /// **'No identities enrolled yet.'**
  String get noIdentitiesEnrolled;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @duplicateDetected.
  ///
  /// In en, this message translates to:
  /// **'Duplicate detected ({duplicateIdentityId})'**
  String duplicateDetected(String duplicateIdentityId);

  /// No description provided for @enrolled.
  ///
  /// In en, this message translates to:
  /// **'Enrolled: {templateId}'**
  String enrolled(String templateId);

  /// No description provided for @analyze.
  ///
  /// In en, this message translates to:
  /// **'Analyze'**
  String get analyze;

  /// No description provided for @selectImageAndAnalyze.
  ///
  /// In en, this message translates to:
  /// **'Select an image and click Analyze'**
  String get selectImageAndAnalyze;

  /// No description provided for @segmentation.
  ///
  /// In en, this message translates to:
  /// **'Segmentation'**
  String get segmentation;

  /// No description provided for @original.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get original;

  /// No description provided for @pipelineOutputs.
  ///
  /// In en, this message translates to:
  /// **'Pipeline Outputs'**
  String get pipelineOutputs;

  /// No description provided for @normalizedIris.
  ///
  /// In en, this message translates to:
  /// **'Normalized Iris'**
  String get normalizedIris;

  /// No description provided for @irisCode.
  ///
  /// In en, this message translates to:
  /// **'Iris Code'**
  String get irisCode;

  /// No description provided for @noiseMask.
  ///
  /// In en, this message translates to:
  /// **'Noise Mask'**
  String get noiseMask;

  /// No description provided for @qualityMetrics.
  ///
  /// In en, this message translates to:
  /// **'Quality Metrics'**
  String get qualityMetrics;

  /// No description provided for @sharpness.
  ///
  /// In en, this message translates to:
  /// **'Sharpness'**
  String get sharpness;

  /// No description provided for @offgaze.
  ///
  /// In en, this message translates to:
  /// **'Offgaze'**
  String get offgaze;

  /// No description provided for @occlusion90.
  ///
  /// In en, this message translates to:
  /// **'Occlusion 90'**
  String get occlusion90;

  /// No description provided for @occlusion30.
  ///
  /// In en, this message translates to:
  /// **'Occlusion 30'**
  String get occlusion30;

  /// No description provided for @pupilIrisRatio.
  ///
  /// In en, this message translates to:
  /// **'Pupil/Iris Ratio'**
  String get pupilIrisRatio;

  /// No description provided for @geometry.
  ///
  /// In en, this message translates to:
  /// **'Geometry'**
  String get geometry;

  /// No description provided for @pupilCenter.
  ///
  /// In en, this message translates to:
  /// **'Pupil Center'**
  String get pupilCenter;

  /// No description provided for @irisCenter.
  ///
  /// In en, this message translates to:
  /// **'Iris Center'**
  String get irisCenter;

  /// No description provided for @pupilRadius.
  ///
  /// In en, this message translates to:
  /// **'Pupil Radius'**
  String get pupilRadius;

  /// No description provided for @irisRadius.
  ///
  /// In en, this message translates to:
  /// **'Iris Radius'**
  String get irisRadius;

  /// No description provided for @eyeOrientation.
  ///
  /// In en, this message translates to:
  /// **'Eye Orientation'**
  String get eyeOrientation;

  /// No description provided for @noGalleryTemplates.
  ///
  /// In en, this message translates to:
  /// **'No gallery templates — enroll identities first'**
  String get noGalleryTemplates;

  /// No description provided for @noMatch.
  ///
  /// In en, this message translates to:
  /// **'No match'**
  String get noMatch;

  /// No description provided for @hdValue.
  ///
  /// In en, this message translates to:
  /// **'HD: {hd}'**
  String hdValue(String hd);

  /// No description provided for @matchIdentity.
  ///
  /// In en, this message translates to:
  /// **'Match ({id})'**
  String matchIdentity(String id);

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'all'**
  String get filterAll;

  /// No description provided for @filterMatch.
  ///
  /// In en, this message translates to:
  /// **'match'**
  String get filterMatch;

  /// No description provided for @filterNoMatch.
  ///
  /// In en, this message translates to:
  /// **'no-match'**
  String get filterNoMatch;

  /// No description provided for @filterError.
  ///
  /// In en, this message translates to:
  /// **'error'**
  String get filterError;

  /// No description provided for @searchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search device, frame, identity...'**
  String get searchPlaceholder;

  /// No description provided for @headerTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get headerTime;

  /// No description provided for @headerDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get headerDevice;

  /// No description provided for @headerFrame.
  ///
  /// In en, this message translates to:
  /// **'Frame'**
  String get headerFrame;

  /// No description provided for @headerHd.
  ///
  /// In en, this message translates to:
  /// **'HD'**
  String get headerHd;

  /// No description provided for @headerStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get headerStatus;

  /// No description provided for @headerLatency.
  ///
  /// In en, this message translates to:
  /// **'Latency'**
  String get headerLatency;

  /// No description provided for @noResultsMatchFilter.
  ///
  /// In en, this message translates to:
  /// **'No results match the current filter.'**
  String get noResultsMatchFilter;

  /// No description provided for @pollingEvery5s.
  ///
  /// In en, this message translates to:
  /// **'Polling every 5s'**
  String get pollingEvery5s;

  /// No description provided for @serviceGateway.
  ///
  /// In en, this message translates to:
  /// **'Gateway'**
  String get serviceGateway;

  /// No description provided for @serviceIrisEngine.
  ///
  /// In en, this message translates to:
  /// **'Iris Engine'**
  String get serviceIrisEngine;

  /// No description provided for @serviceNats.
  ///
  /// In en, this message translates to:
  /// **'NATS'**
  String get serviceNats;

  /// No description provided for @alive.
  ///
  /// In en, this message translates to:
  /// **'Alive'**
  String get alive;

  /// No description provided for @ready.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get ready;

  /// No description provided for @nats.
  ///
  /// In en, this message translates to:
  /// **'NATS'**
  String get nats;

  /// No description provided for @circuitBreaker.
  ///
  /// In en, this message translates to:
  /// **'Circuit Breaker'**
  String get circuitBreaker;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @pipeline.
  ///
  /// In en, this message translates to:
  /// **'Pipeline'**
  String get pipeline;

  /// No description provided for @gallerySize.
  ///
  /// In en, this message translates to:
  /// **'Gallery Size'**
  String get gallerySize;

  /// No description provided for @database.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get database;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @clientPort.
  ///
  /// In en, this message translates to:
  /// **'Client Port'**
  String get clientPort;

  /// No description provided for @monitorPort.
  ///
  /// In en, this message translates to:
  /// **'Monitor Port'**
  String get monitorPort;

  /// No description provided for @unreachable.
  ///
  /// In en, this message translates to:
  /// **'Unreachable'**
  String get unreachable;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @natsClientPortInfo.
  ///
  /// In en, this message translates to:
  /// **'4222 (internal) / 9502 (host)'**
  String get natsClientPortInfo;

  /// No description provided for @natsMonitorPortInfo.
  ///
  /// In en, this message translates to:
  /// **'8222 (internal) / 9501 (host)'**
  String get natsMonitorPortInfo;

  /// No description provided for @notFoundCode.
  ///
  /// In en, this message translates to:
  /// **'404'**
  String get notFoundCode;

  /// No description provided for @pageNotFound.
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get pageNotFound;

  /// No description provided for @statusLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get statusLive;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get statusOffline;

  /// No description provided for @videoLive.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get videoLive;

  /// No description provided for @videoConnecting.
  ///
  /// In en, this message translates to:
  /// **'CONNECTING'**
  String get videoConnecting;

  /// No description provided for @videoWaiting.
  ///
  /// In en, this message translates to:
  /// **'WAITING'**
  String get videoWaiting;

  /// No description provided for @videoOffline.
  ///
  /// In en, this message translates to:
  /// **'OFFLINE'**
  String get videoOffline;

  /// No description provided for @waitingForVideo.
  ///
  /// In en, this message translates to:
  /// **'Waiting for video...'**
  String get waitingForVideo;

  /// No description provided for @noImages.
  ///
  /// In en, this message translates to:
  /// **'No images'**
  String get noImages;

  /// No description provided for @eyeSideShortLeft.
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get eyeSideShortLeft;

  /// No description provided for @eyeSideShortRight.
  ///
  /// In en, this message translates to:
  /// **'R'**
  String get eyeSideShortRight;

  /// No description provided for @errorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorPrefix(String error);

  /// No description provided for @noMatchData.
  ///
  /// In en, this message translates to:
  /// **'No match data'**
  String get noMatchData;

  /// No description provided for @languageName.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageName;

  /// No description provided for @datasetPaths.
  ///
  /// In en, this message translates to:
  /// **'Dataset Directories'**
  String get datasetPaths;

  /// No description provided for @datasetPathsPrimary.
  ///
  /// In en, this message translates to:
  /// **'Primary'**
  String get datasetPathsPrimary;

  /// No description provided for @datasetPathsExtra.
  ///
  /// In en, this message translates to:
  /// **'Extra'**
  String get datasetPathsExtra;

  /// No description provided for @addDirectory.
  ///
  /// In en, this message translates to:
  /// **'Add Directory'**
  String get addDirectory;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @enterAbsolutePath.
  ///
  /// In en, this message translates to:
  /// **'Enter absolute path (e.g. /data/MyDataset)'**
  String get enterAbsolutePath;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @pathAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'Path already registered'**
  String get pathAlreadyRegistered;

  /// No description provided for @datasetsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} datasets'**
  String datasetsCount(int count);

  /// No description provided for @directoryNotFound.
  ///
  /// In en, this message translates to:
  /// **'Directory not found'**
  String get directoryNotFound;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @bulkEnroll.
  ///
  /// In en, this message translates to:
  /// **'Bulk Enroll'**
  String get bulkEnroll;

  /// No description provided for @bulkEnrollStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get bulkEnrollStart;

  /// No description provided for @bulkEnrollSubjectFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter subjects (comma-separated, e.g. 000,001,002) — leave empty for all'**
  String get bulkEnrollSubjectFilter;

  /// No description provided for @bulkEnrolled.
  ///
  /// In en, this message translates to:
  /// **'enrolled'**
  String get bulkEnrolled;

  /// No description provided for @bulkDuplicate.
  ///
  /// In en, this message translates to:
  /// **'duplicate'**
  String get bulkDuplicate;

  /// No description provided for @bulkEnrollComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete: {enrolled} enrolled, {duplicates} duplicates, {errors} errors'**
  String bulkEnrollComplete(int enrolled, int duplicates, int errors);

  /// No description provided for @bulkEnrollRunning.
  ///
  /// In en, this message translates to:
  /// **'Enrolling...'**
  String get bulkEnrollRunning;

  /// No description provided for @bulkEnrollProgress.
  ///
  /// In en, this message translates to:
  /// **'Enrolling {processed}'**
  String bulkEnrollProgress(int processed);

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @identityDetails.
  ///
  /// In en, this message translates to:
  /// **'Identity Details'**
  String get identityDetails;

  /// No description provided for @templateId.
  ///
  /// In en, this message translates to:
  /// **'Template ID'**
  String get templateId;

  /// No description provided for @eyeSide.
  ///
  /// In en, this message translates to:
  /// **'Eye Side'**
  String get eyeSide;

  /// No description provided for @identityId.
  ///
  /// In en, this message translates to:
  /// **'Identity ID'**
  String get identityId;

  /// No description provided for @templates.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get templates;

  /// No description provided for @noTemplates.
  ///
  /// In en, this message translates to:
  /// **'No templates'**
  String get noTemplates;

  /// No description provided for @codeSize.
  ///
  /// In en, this message translates to:
  /// **'Code Size'**
  String get codeSize;

  /// No description provided for @scales.
  ///
  /// In en, this message translates to:
  /// **'Scales'**
  String get scales;

  /// No description provided for @deviceId.
  ///
  /// In en, this message translates to:
  /// **'Device ID'**
  String get deviceId;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @maskCode.
  ///
  /// In en, this message translates to:
  /// **'Mask Code'**
  String get maskCode;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @connectionLost.
  ///
  /// In en, this message translates to:
  /// **'Connection Lost'**
  String get connectionLost;

  /// No description provided for @connectionLostDesc.
  ///
  /// In en, this message translates to:
  /// **'Unable to reach the backend services.'**
  String get connectionLostDesc;

  /// No description provided for @reconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnect;

  /// No description provided for @reconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting...'**
  String get reconnecting;

  /// No description provided for @reconnectCountdown.
  ///
  /// In en, this message translates to:
  /// **'Reconnect ({seconds}s)'**
  String reconnectCountdown(int seconds);

  /// No description provided for @connectionRetryCount.
  ///
  /// In en, this message translates to:
  /// **'Attempt {current} of {max}'**
  String connectionRetryCount(int current, int max);

  /// No description provided for @dbInspector.
  ///
  /// In en, this message translates to:
  /// **'DB Inspector'**
  String get dbInspector;

  /// No description provided for @dbSchema.
  ///
  /// In en, this message translates to:
  /// **'Schema'**
  String get dbSchema;

  /// No description provided for @dbBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get dbBrowse;

  /// No description provided for @dbHeGuide.
  ///
  /// In en, this message translates to:
  /// **'HE Guide'**
  String get dbHeGuide;

  /// No description provided for @dbSelectTable.
  ///
  /// In en, this message translates to:
  /// **'Select table...'**
  String get dbSelectTable;

  /// No description provided for @dbRowsTotal.
  ///
  /// In en, this message translates to:
  /// **'{count} rows total'**
  String dbRowsTotal(int count);

  /// No description provided for @dbRelationships.
  ///
  /// In en, this message translates to:
  /// **'Relationships'**
  String get dbRelationships;

  /// No description provided for @dbPrimaryKey.
  ///
  /// In en, this message translates to:
  /// **'PK'**
  String get dbPrimaryKey;

  /// No description provided for @dbForeignKey.
  ///
  /// In en, this message translates to:
  /// **'FK'**
  String get dbForeignKey;

  /// No description provided for @dbHeEncrypted.
  ///
  /// In en, this message translates to:
  /// **'HE Encrypted'**
  String get dbHeEncrypted;

  /// No description provided for @dbPlaintextNpz.
  ///
  /// In en, this message translates to:
  /// **'Plaintext NPZ'**
  String get dbPlaintextNpz;

  /// No description provided for @dbSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get dbSize;

  /// No description provided for @dbFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get dbFormat;

  /// No description provided for @dbCiphertexts.
  ///
  /// In en, this message translates to:
  /// **'Ciphertexts'**
  String get dbCiphertexts;

  /// No description provided for @dbHexPrefix.
  ///
  /// In en, this message translates to:
  /// **'Hex prefix'**
  String get dbHexPrefix;

  /// No description provided for @dbRelatedData.
  ///
  /// In en, this message translates to:
  /// **'Related data'**
  String get dbRelatedData;

  /// No description provided for @dbSelectTablePrompt.
  ///
  /// In en, this message translates to:
  /// **'Select a table to browse rows'**
  String get dbSelectTablePrompt;

  /// No description provided for @individualEnroll.
  ///
  /// In en, this message translates to:
  /// **'Individual'**
  String get individualEnroll;

  /// No description provided for @bulkEnrollTab.
  ///
  /// In en, this message translates to:
  /// **'Bulk Enroll'**
  String get bulkEnrollTab;

  /// No description provided for @galleryTab.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get galleryTab;

  /// No description provided for @leftEye.
  ///
  /// In en, this message translates to:
  /// **'Left Eye'**
  String get leftEye;

  /// No description provided for @rightEye.
  ///
  /// In en, this message translates to:
  /// **'Right Eye'**
  String get rightEye;

  /// No description provided for @loadFromDisk.
  ///
  /// In en, this message translates to:
  /// **'Load from disk'**
  String get loadFromDisk;

  /// No description provided for @notApplicable.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get notApplicable;

  /// No description provided for @atLeastOneEyeRequired.
  ///
  /// In en, this message translates to:
  /// **'At least one eye image is required'**
  String get atLeastOneEyeRequired;

  /// No description provided for @segmentationFailed.
  ///
  /// In en, this message translates to:
  /// **'Iris not found. Please select a better quality image.'**
  String get segmentationFailed;

  /// No description provided for @duplicateUserDetected.
  ///
  /// In en, this message translates to:
  /// **'Duplicate detected: already enrolled as {name}'**
  String duplicateUserDetected(String name);

  /// No description provided for @enrollSuccess.
  ///
  /// In en, this message translates to:
  /// **'Enrolled successfully ({count} template(s))'**
  String enrollSuccess(int count);

  /// No description provided for @selectLocalDirectory.
  ///
  /// In en, this message translates to:
  /// **'Select Directory'**
  String get selectLocalDirectory;

  /// No description provided for @localBulkEnroll.
  ///
  /// In en, this message translates to:
  /// **'Local Directory'**
  String get localBulkEnroll;

  /// No description provided for @serverBulkEnroll.
  ///
  /// In en, this message translates to:
  /// **'Server Dataset'**
  String get serverBulkEnroll;

  /// No description provided for @scanningDirectory.
  ///
  /// In en, this message translates to:
  /// **'Scanning directory...'**
  String get scanningDirectory;

  /// No description provided for @subjectsFound.
  ///
  /// In en, this message translates to:
  /// **'{count} subjects found'**
  String subjectsFound(int count);

  /// No description provided for @enrollingSubject.
  ///
  /// In en, this message translates to:
  /// **'Enrolling {current} of {total}: {name}'**
  String enrollingSubject(int current, int total, String name);

  /// No description provided for @localBulkComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete: {enrolled} enrolled, {duplicates} duplicates, {errors} errors'**
  String localBulkComplete(int enrolled, int duplicates, int errors);

  /// No description provided for @noSubjectsFound.
  ///
  /// In en, this message translates to:
  /// **'No valid subjects found in directory'**
  String get noSubjectsFound;

  /// No description provided for @startEnroll.
  ///
  /// In en, this message translates to:
  /// **'Start Enroll'**
  String get startEnroll;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
