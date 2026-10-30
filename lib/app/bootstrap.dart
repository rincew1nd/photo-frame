import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:photoframe/core/failures.dart';
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/core/logging/crash_handler.dart';
import 'package:photoframe/data/cache/app_database.dart';
import 'package:photoframe/data/secure/secure_store.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/platform/paths.dart';
import 'package:photoframe/platform/services.dart';
import 'package:flutter/widgets.dart';

class Bootstrap {
  Bootstrap({
    required this.paths,
    required this.logger,
    required this.settings,
    required this.secure,
    required this.database,
    required this.platform,
    this.hasStoredSession = false,
    this.startAtSlideshow = false,
  });

  final AppPaths paths;
  final AppLogger logger;
  final SettingsRepository settings;
  final SecureStore secure;
  final AppDatabase database;
  final PlatformServices platform;
  final bool hasStoredSession;
  final bool startAtSlideshow;

  static Future<Bootstrap> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();

    final paths = FileSystemAppPaths();
    final logger = AppLogger();
    await logger.init(paths);
    CrashHandler.install(logger);

    final settings = FileSettingsRepository(paths);
    final secure = FlutterSecureStore();

    final support = await paths.support();
    final database = await AppDatabase.open(
      File(p.join(support.path, 'photo_frame.db')),
    );
    await database.migrate();

    final loadedSettings = await settings.load();

    final platform = PlatformServices.create(paths);
    final acquired = await platform.singleInstance.acquire();
    if (!acquired) {
      await database.close();
      throw const AppFailure(
        FailureKind.storage,
        'Another Photo Frame instance is already running.',
      );
    }

    final apiKey = await secure.read(SecretKeys.immichApiKey);
    if (apiKey != null) {
      logger.registerSecret(apiKey);
    }
    final accessToken = await secure.read(SecretKeys.immichAccessToken);
    if (accessToken != null) {
      logger.registerSecret(accessToken);
    }

    logger.info('Bootstrap complete');
    final hasStoredSession =
        (apiKey != null && apiKey.isNotEmpty) ||
        (accessToken != null && accessToken.isNotEmpty);
    return Bootstrap(
      paths: paths,
      logger: logger,
      settings: settings,
      secure: secure,
      database: database,
      platform: platform,
      hasStoredSession: hasStoredSession,
      startAtSlideshow:
          hasStoredSession &&
          (loadedSettings.connection.serverUrl ?? '').trim().isNotEmpty &&
          loadedSettings.connection.albumIds.isNotEmpty,
    );
  }

  Future<void> dispose() async {
    await platform.singleInstance.release();
    await database.close();
    await logger.flush();
  }
}
