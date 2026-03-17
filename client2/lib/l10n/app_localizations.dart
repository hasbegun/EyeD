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

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'EyeD'**
  String get appTitle;

  /// No description provided for @enrollPage.
  ///
  /// In en, this message translates to:
  /// **'Enroll'**
  String get enrollPage;

  /// No description provided for @detectPage.
  ///
  /// In en, this message translates to:
  /// **'Detect'**
  String get detectPage;

  /// No description provided for @tabIndividual.
  ///
  /// In en, this message translates to:
  /// **'Individual'**
  String get tabIndividual;

  /// No description provided for @tabBulk.
  ///
  /// In en, this message translates to:
  /// **'Bulk'**
  String get tabBulk;

  /// No description provided for @tabGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get tabGallery;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameRequired;

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

  /// No description provided for @loadImage.
  ///
  /// In en, this message translates to:
  /// **'Load Image'**
  String get loadImage;

  /// No description provided for @notAvailable.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get notAvailable;

  /// No description provided for @enroll.
  ///
  /// In en, this message translates to:
  /// **'Enroll'**
  String get enroll;

  /// No description provided for @enrolling.
  ///
  /// In en, this message translates to:
  /// **'Enrolling...'**
  String get enrolling;

  /// No description provided for @enrollSuccess.
  ///
  /// In en, this message translates to:
  /// **'Enrolled successfully'**
  String get enrollSuccess;

  /// No description provided for @enrollSuccessEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Enrolled — template encrypted 🔒'**
  String get enrollSuccessEncrypted;

  /// No description provided for @enrollSuccessPlain.
  ///
  /// In en, this message translates to:
  /// **'Enrolled — template plaintext'**
  String get enrollSuccessPlain;

  /// No description provided for @enrollDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate: matches {name}'**
  String enrollDuplicate(String name);

  /// No description provided for @enrollError.
  ///
  /// In en, this message translates to:
  /// **'Enrollment failed: {error}'**
  String enrollError(String error);

  /// No description provided for @eyeRequired.
  ///
  /// In en, this message translates to:
  /// **'At least one eye image is required'**
  String get eyeRequired;

  /// No description provided for @bulkSelectDir.
  ///
  /// In en, this message translates to:
  /// **'Select Directory'**
  String get bulkSelectDir;

  /// No description provided for @bulkStart.
  ///
  /// In en, this message translates to:
  /// **'Start Bulk Enroll'**
  String get bulkStart;

  /// No description provided for @bulkRunning.
  ///
  /// In en, this message translates to:
  /// **'Enrolling... {current}/{total}'**
  String bulkRunning(int current, int total);

  /// No description provided for @bulkComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete: {enrolled}/{total} enrolled, {skipped} skipped, {errors} errors'**
  String bulkComplete(int enrolled, int total, int skipped, int errors);

  /// No description provided for @bulkIdle.
  ///
  /// In en, this message translates to:
  /// **'Select a directory to begin'**
  String get bulkIdle;

  /// No description provided for @bulkNoSubjects.
  ///
  /// In en, this message translates to:
  /// **'No valid subjects found in directory'**
  String get bulkNoSubjects;

  /// No description provided for @galleryRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get galleryRefresh;

  /// No description provided for @galleryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No enrolled identities'**
  String get galleryEmpty;

  /// No description provided for @galleryCount.
  ///
  /// In en, this message translates to:
  /// **'{count} identities'**
  String galleryCount(int count);

  /// No description provided for @identityDetail.
  ///
  /// In en, this message translates to:
  /// **'Identity Detail'**
  String get identityDetail;

  /// No description provided for @templateDetail.
  ///
  /// In en, this message translates to:
  /// **'Template Detail'**
  String get templateDetail;

  /// No description provided for @eyeSide.
  ///
  /// In en, this message translates to:
  /// **'Eye'**
  String get eyeSide;

  /// No description provided for @qualityScore.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get qualityScore;

  /// No description provided for @deviceId.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get deviceId;

  /// No description provided for @dimensions.
  ///
  /// In en, this message translates to:
  /// **'Dimensions'**
  String get dimensions;

  /// No description provided for @irisCode.
  ///
  /// In en, this message translates to:
  /// **'Iris Code'**
  String get irisCode;

  /// No description provided for @maskCode.
  ///
  /// In en, this message translates to:
  /// **'Mask Code'**
  String get maskCode;

  /// No description provided for @templateEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Encrypted (FHE)'**
  String get templateEncrypted;

  /// No description provided for @templatePlaintext.
  ///
  /// In en, this message translates to:
  /// **'Plaintext'**
  String get templatePlaintext;

  /// No description provided for @encryptedNoPreview.
  ///
  /// In en, this message translates to:
  /// **'Template is FHE-encrypted — iris code not available for preview'**
  String get encryptedNoPreview;

  /// No description provided for @deleteIdentity.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteIdentity;

  /// No description provided for @deleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete identity \"{name}\"?'**
  String deleteConfirm(String name);

  /// No description provided for @deleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This will permanently remove this identity and all associated templates.'**
  String get deleteConfirmBody;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @detectLoadImage.
  ///
  /// In en, this message translates to:
  /// **'Load Iris Image'**
  String get detectLoadImage;

  /// No description provided for @detectButton.
  ///
  /// In en, this message translates to:
  /// **'Detect'**
  String get detectButton;

  /// No description provided for @detecting.
  ///
  /// In en, this message translates to:
  /// **'Detecting...'**
  String get detecting;

  /// No description provided for @detectMatch.
  ///
  /// In en, this message translates to:
  /// **'Match: {name} (HD: {hd})'**
  String detectMatch(String name, String hd);

  /// No description provided for @detectNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No match found'**
  String get detectNoMatch;

  /// No description provided for @detectError.
  ///
  /// In en, this message translates to:
  /// **'Detection failed: {error}'**
  String detectError(String error);

  /// No description provided for @connectionError.
  ///
  /// In en, this message translates to:
  /// **'Cannot connect to server'**
  String get connectionError;

  /// No description provided for @serverError.
  ///
  /// In en, this message translates to:
  /// **'Server error'**
  String get serverError;

  /// No description provided for @logPage.
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get logPage;

  /// No description provided for @logFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get logFilterAll;

  /// No description provided for @logFilterMatch.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get logFilterMatch;

  /// No description provided for @logFilterNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No match'**
  String get logFilterNoMatch;

  /// No description provided for @logFilterError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get logFilterError;

  /// No description provided for @logSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search identity...'**
  String get logSearchPlaceholder;

  /// No description provided for @logHeaderTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get logHeaderTime;

  /// No description provided for @logHeaderHd.
  ///
  /// In en, this message translates to:
  /// **'HD'**
  String get logHeaderHd;

  /// No description provided for @logHeaderStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get logHeaderStatus;

  /// No description provided for @logHeaderLatency.
  ///
  /// In en, this message translates to:
  /// **'Latency'**
  String get logHeaderLatency;

  /// No description provided for @logEmpty.
  ///
  /// In en, this message translates to:
  /// **'No detection results yet.'**
  String get logEmpty;

  /// No description provided for @logClear.
  ///
  /// In en, this message translates to:
  /// **'Clear log'**
  String get logClear;

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
