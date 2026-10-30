// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Photo Frame';

  @override
  String get setup => 'Setup';

  @override
  String get settings => 'Settings';

  @override
  String get connection => 'Connection';

  @override
  String get albums => 'Albums';

  @override
  String get retry => 'Retry';

  @override
  String get show => 'Show';

  @override
  String get hide => 'Hide';

  @override
  String get permissions => 'Permissions';

  @override
  String get videosUnavailable =>
      'Videos are unavailable because this API key cannot download originals.';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get apiKey => 'API key';

  @override
  String get signIn => 'Sign in with Immich';

  @override
  String get connect => 'Connect';

  @override
  String get continueLabel => 'Continue to albums';

  @override
  String get granted => 'Granted';

  @override
  String get denied => 'Denied';

  @override
  String get notTested => 'Not tested';

  @override
  String get errorLabel => 'Error';
}
