import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:photoframe/app/bootstrap.dart';
import 'package:photoframe/app/router.dart';
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/data/cache/app_database.dart';
import 'package:photoframe/data/cache/cache_store.dart';
import 'package:photoframe/data/media/media_kit_playback.dart';
import 'package:photoframe/data/media/native/native_still_decoder.dart';
import 'package:photoframe/data/media/playback.dart';
import 'package:photoframe/data/media/preview_only_decoder.dart';
import 'package:photoframe/data/media/still_decoder.dart';
import 'package:photoframe/data/plugins/plugin_store.dart';
import 'package:photoframe/data/secure/secure_store.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/platform/paths.dart';
import 'package:photoframe/platform/media_session.dart';
import 'package:photoframe/platform/services.dart';

final Provider<Bootstrap> bootstrapProvider = Provider<Bootstrap>((ref) {
  throw StateError('bootstrapProvider must be overridden');
});

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
      (ref) => ref.watch(bootstrapProvider).settings,
    );

final Provider<SecureStore> secureStoreProvider = Provider<SecureStore>(
  (ref) => ref.watch(bootstrapProvider).secure,
);

final Provider<AppPaths> appPathsProvider = Provider<AppPaths>(
  (ref) => ref.watch(bootstrapProvider).paths,
);

final Provider<AppLogger> appLoggerProvider = Provider<AppLogger>(
  (ref) => ref.watch(bootstrapProvider).logger,
);

final Provider<AppDatabase> databaseProvider = Provider<AppDatabase>(
  (ref) => ref.watch(bootstrapProvider).database,
);

final Provider<CacheStore> cacheStoreProvider = Provider<CacheStore>(
  (ref) => DriftCacheStore(ref.watch(databaseProvider)),
);

final Provider<PluginStore> pluginStoreProvider = Provider<PluginStore>((ref) {
  final store = PluginStore(
    ref.watch(databaseProvider),
    ref.watch(appPathsProvider),
  );
  // Public store methods also await init(); this warms the schema early.
  unawaited(store.init().catchError((Object _) {}));
  return store;
});

final FutureProvider<List<InstalledPlugin>> installedPluginsProvider =
    FutureProvider<List<InstalledPlugin>>(
      (ref) => ref.watch(pluginStoreProvider).list(),
    );

final FutureProvider<String> hostAppVersionProvider = FutureProvider<String>(
  (ref) async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } on Object {
      // ponytail: fall back to the minimum supported app version when package
      // metadata is unavailable (e.g. widget tests).
      return '0.0.0';
    }
  },
);

final Provider<PlatformServices> platformServicesProvider =
    Provider<PlatformServices>((ref) => ref.watch(bootstrapProvider).platform);

final Provider<AudioFocusService> audioFocusServiceProvider =
    Provider<AudioFocusService>((ref) => PlatformAudioFocus());

final Provider<MediaSessionService> mediaSessionServiceProvider =
    Provider<MediaSessionService>(
      (ref) => Platform.isAndroid || Platform.isWindows
          ? PlatformMediaSessionService()
          : const UnsupportedMediaSessionService(),
    );

final StreamProvider<BackgroundMediaState> backgroundMediaProvider =
    StreamProvider<BackgroundMediaState>(
      (ref) => ref.watch(mediaSessionServiceProvider).watch(),
    );

final Provider<BiometricsService> biometricsServiceProvider =
    Provider<BiometricsService>(
      (ref) => ref.watch(platformServicesProvider).biometrics,
    );

final Provider<AutostartService> autostartServiceProvider =
    Provider<AutostartService>(
      (ref) => ref.watch(platformServicesProvider).autostart,
    );

final FutureProvider<bool> autostartSupportProvider = FutureProvider<bool>(
  (ref) => ref.watch(autostartServiceProvider).supported,
);

final Provider<PermissionsService> permissionsServiceProvider =
    Provider<PermissionsService>(
      (ref) => ref.watch(platformServicesProvider).permissions,
    );

final Provider<BrightnessService> brightnessServiceProvider =
    Provider<BrightnessService>(
      (ref) => ref.watch(platformServicesProvider).brightness,
    );

final FutureProvider<bool> livePhotoBounceSupportProvider =
    FutureProvider<bool>(
      (ref) => ref.watch(platformServicesProvider).livePhotoBounce.supported,
    );

final Provider<MediaPlaybackFactory> mediaPlaybackFactoryProvider =
    Provider<MediaPlaybackFactory>((ref) => MediaKitPlayback.new);

// Android hardware decoders are scarce; avoid a second player.
final Provider<bool> preloadMediaProvider = Provider<bool>(
  (ref) => !Platform.isAndroid,
);

final Provider<StillDecoder> stillDecoderProvider = Provider<StillDecoder>(
  (ref) => NativeStillDecoder.tryCreate() ?? const PreviewOnlyStillDecoder(),
);

final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  final bootstrap = ref.watch(bootstrapProvider);
  return createAppRouter(
    initialLocation: bootstrap.startAtSlideshow ? '/slideshow' : '/settings',
  );
});

final AsyncNotifierProvider<SettingsController, AppSettings>
settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
      SettingsController.new,
    );

class SettingsController extends AsyncNotifier<AppSettings> {
  Future<void> _lastSave = Future<void>.value();

  @override
  Future<AppSettings> build() {
    return ref.watch(settingsRepositoryProvider).load();
  }

  Future<void> save(AppSettings Function(AppSettings) update) {
    final repository = ref.read(settingsRepositoryProvider);
    final current = state.value ?? const AppSettings();
    final next = update(current);
    state = AsyncData(next);
    _lastSave = repository.save(next).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      state = AsyncError(error, stackTrace);
    });
    return _lastSave;
  }

  Future<void> flush() => _lastSave;

  Future<void> reload() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await ref.read(settingsRepositoryProvider).load());
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}
