import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/core/logging/crash_handler.dart';
import 'package:photoframe/data/cache/app_database.dart';
import 'package:photoframe/data/plugins/bundled_examples.dart';
import 'package:photoframe/data/plugins/plugin_seeder.dart';
import 'package:photoframe/data/plugins/plugin_store.dart';
import 'package:photoframe/data/secure/secure_store.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/platform/paths.dart';
import 'package:photoframe/platform/services.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
    await _seedAndMigratePlugins(
      paths: paths,
      database: database,
      logger: logger,
    );

    final platform = PlatformServices.create(paths);
    final acquired = await platform.singleInstance.acquire();
    if (!acquired) {
      await database.close();
      exit(0);
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

  static Future<void> _seedAndMigratePlugins({
    required AppPaths paths,
    required AppDatabase database,
    required AppLogger logger,
  }) async {
    try {
      final store = PluginStore(database, paths);
      await store.init();
      final seededVersion = await store.seededVersion();
      final alreadySeeded = await store.isSeeded() || seededVersion > 0;
      if (seededVersion < bundledExamplesVersion) {
        final sources = await loadBundledExampleSources();
        final version = await PackageInfo.fromPlatform();
        final result = await PluginSeeder(
          hostAppVersion: version.version,
        ).seed(
          store: store,
          sources: sources,
          alreadySeeded: alreadySeeded,
          installMissing: !alreadySeeded,
          updateExisting: alreadySeeded,
          markSeeded: () => store.markSeededVersion(bundledExamplesVersion),
        );
        logger.info(
          'Bundled plugins: ${result.installed} installed, '
          '${result.updated} updated, ${result.skipped} skipped, '
          '${result.failed} failed',
        );
      }
    } on Object catch (error) {
      logger.warning('Bundled plugin setup failed', error: error);
    }
  }

  Future<void> dispose() async {
    await platform.singleInstance.release();
    await database.close();
    await logger.flush();
  }
}
