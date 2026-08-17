import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ms.dart';

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
    Locale('ms'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Industrial Hub'**
  String get appTitle;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Innovation Platform'**
  String get tagline;

  /// No description provided for @tabHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get tabHome;

  /// No description provided for @tabCapacity.
  ///
  /// In en, this message translates to:
  /// **'Capacity'**
  String get tabCapacity;

  /// No description provided for @tabStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get tabStock;

  /// No description provided for @tabSupply.
  ///
  /// In en, this message translates to:
  /// **'Supply'**
  String get tabSupply;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get actionCreate;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get actionRename;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @actionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// No description provided for @commonLoadingFailed.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get commonLoadingFailed;

  /// No description provided for @commonNoData.
  ///
  /// In en, this message translates to:
  /// **'No data yet.'**
  String get commonNoData;

  /// No description provided for @authEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authLogIn.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get authLogIn;

  /// No description provided for @authEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get authEmailRequired;

  /// No description provided for @authEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get authEmailInvalid;

  /// No description provided for @authPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get authPasswordRequired;

  /// No description provided for @authRememberMe.
  ///
  /// In en, this message translates to:
  /// **'Remember me for 30 days'**
  String get authRememberMe;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// No description provided for @authOr.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get authOr;

  /// No description provided for @authContinueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authContinueWithGoogle;

  /// No description provided for @authNoAccount.
  ///
  /// In en, this message translates to:
  /// **'No account? '**
  String get authNoAccount;

  /// No description provided for @authSignUp.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get authSignUp;

  /// No description provided for @authAdminLogin.
  ///
  /// In en, this message translates to:
  /// **'Admin login'**
  String get authAdminLogin;

  /// No description provided for @homeSwitchFactory.
  ///
  /// In en, this message translates to:
  /// **'Switch factory'**
  String get homeSwitchFactory;

  /// No description provided for @homeAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get homeAbout;

  /// No description provided for @homeSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get homeSignOut;

  /// No description provided for @homeShareReport.
  ///
  /// In en, this message translates to:
  /// **'Share report'**
  String get homeShareReport;

  /// No description provided for @homeNewFactory.
  ///
  /// In en, this message translates to:
  /// **'New factory'**
  String get homeNewFactory;

  /// No description provided for @homeLoadDemoData.
  ///
  /// In en, this message translates to:
  /// **'Load demo data'**
  String get homeLoadDemoData;

  /// No description provided for @homeFactoryName.
  ///
  /// In en, this message translates to:
  /// **'Factory name'**
  String get homeFactoryName;

  /// No description provided for @homeNoFactory.
  ///
  /// In en, this message translates to:
  /// **'No factory set up yet.'**
  String get homeNoFactory;

  /// No description provided for @homeCreateFactory.
  ///
  /// In en, this message translates to:
  /// **'Create factory'**
  String get homeCreateFactory;

  /// No description provided for @homeDeleteFactoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete factory?'**
  String get homeDeleteFactoryTitle;

  /// No description provided for @homeRenameFactoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename factory'**
  String get homeRenameFactoryTitle;

  /// No description provided for @capacityDailyCeiling.
  ///
  /// In en, this message translates to:
  /// **'Daily production ceiling'**
  String get capacityDailyCeiling;

  /// No description provided for @capacityMachines.
  ///
  /// In en, this message translates to:
  /// **'Machines'**
  String get capacityMachines;

  /// No description provided for @capacityManpower.
  ///
  /// In en, this message translates to:
  /// **'Manpower'**
  String get capacityManpower;

  /// No description provided for @capacitySimulator.
  ///
  /// In en, this message translates to:
  /// **'Open what-if simulator'**
  String get capacitySimulator;

  /// No description provided for @capacityBenchmark.
  ///
  /// In en, this message translates to:
  /// **'Benchmark vs Malaysia'**
  String get capacityBenchmark;

  /// No description provided for @capacityProductionTrend.
  ///
  /// In en, this message translates to:
  /// **'Production trend'**
  String get capacityProductionTrend;

  /// No description provided for @stockDaysOfCover.
  ///
  /// In en, this message translates to:
  /// **'Days of cover'**
  String get stockDaysOfCover;

  /// No description provided for @stockProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get stockProducts;

  /// No description provided for @stockLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get stockLowStock;

  /// No description provided for @stockOverstocked.
  ///
  /// In en, this message translates to:
  /// **'Overstocked'**
  String get stockOverstocked;

  /// No description provided for @stockDemandForecast.
  ///
  /// In en, this message translates to:
  /// **'Demand forecast'**
  String get stockDemandForecast;

  /// No description provided for @supplyMaterials.
  ///
  /// In en, this message translates to:
  /// **'Materials'**
  String get supplyMaterials;

  /// No description provided for @supplyReorderNow.
  ///
  /// In en, this message translates to:
  /// **'Reorder now'**
  String get supplyReorderNow;

  /// No description provided for @supplyWatch.
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get supplyWatch;

  /// No description provided for @supplySuppliers.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get supplySuppliers;

  /// No description provided for @supplyPurchaseOrders.
  ///
  /// In en, this message translates to:
  /// **'Purchase orders'**
  String get supplyPurchaseOrders;

  /// No description provided for @supplyRawMaterials.
  ///
  /// In en, this message translates to:
  /// **'Raw materials'**
  String get supplyRawMaterials;

  /// No description provided for @aiGetExplanation.
  ///
  /// In en, this message translates to:
  /// **'Get an AI-generated explanation'**
  String get aiGetExplanation;

  /// No description provided for @aiGenerateInsight.
  ///
  /// In en, this message translates to:
  /// **'Generate insight'**
  String get aiGenerateInsight;

  /// No description provided for @aiGenerating.
  ///
  /// In en, this message translates to:
  /// **'Generating insight…'**
  String get aiGenerating;

  /// No description provided for @aiGenerated.
  ///
  /// In en, this message translates to:
  /// **'AI-generated'**
  String get aiGenerated;

  /// No description provided for @aiUnavailable.
  ///
  /// In en, this message translates to:
  /// **'AI insight unavailable'**
  String get aiUnavailable;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageMalay.
  ///
  /// In en, this message translates to:
  /// **'Bahasa Melayu'**
  String get languageMalay;
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
      <String>['en', 'ms'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ms':
      return AppLocalizationsMs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
