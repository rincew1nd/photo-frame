import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoframe/app/connection_providers.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/core/clock.dart';
import 'package:photoframe/core/failures.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/cache/cache_sync_service.dart';
import 'package:photoframe/data/cache/media_downloader.dart';
import 'package:photoframe/data/immich/immich_client.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/weather/weather_service.dart';
import 'package:photoframe/domain/display/night_mode_service.dart';
import 'package:photoframe/domain/media/media_filters.dart';
import 'package:photoframe/domain/slideshow/slideshow_engine.dart';
import 'package:photoframe/platform/paths.dart';

/// Immutable snapshot of the slideshow for the UI.
class SlideshowViewState {
  const SlideshowViewState({
    this.assets = const <ImmichAsset>[],
    this.currentIndex = 0,
    this.current,
    this.playing = false,
    this.loading = true,
    this.nightMode = false,
    this.error,
    this.weather,
    this.total = 0,
    this.progress = 0,
    this.cached = const <CachedAsset>[],
    this.syncing = false,
  });

  final List<ImmichAsset> assets;
  final int currentIndex;
  final ImmichAsset? current;
  final bool playing;
  final bool loading;
  final bool nightMode;
  final String? error;
  final WeatherSnapshot? weather;
  final int total;
  final double progress;
  final List<CachedAsset> cached;
  final bool syncing;

  SlideshowViewState copyWith({
    List<ImmichAsset>? assets,
    int? currentIndex,
    ImmichAsset? current,
    bool? playing,
    bool? loading,
    bool? nightMode,
    String? error,
    WeatherSnapshot? weather,
    int? total,
    double? progress,
    List<CachedAsset>? cached,
    bool? syncing,
    bool clearError = false,
    bool clearWeather = false,
    bool clearCurrent = false,
  }) {
    return SlideshowViewState(
      assets: assets ?? this.assets,
      currentIndex: currentIndex ?? this.currentIndex,
      current: clearCurrent ? null : current ?? this.current,
      playing: playing ?? this.playing,
      loading: loading ?? this.loading,
      nightMode: nightMode ?? this.nightMode,
      error: clearError ? null : error ?? this.error,
      weather: clearWeather ? null : weather ?? this.weather,
      total: total ?? this.total,
      progress: progress ?? this.progress,
      cached: cached ?? this.cached,
      syncing: syncing ?? this.syncing,
    );
  }
}

final Provider<WeatherService> weatherServiceProvider =
    Provider<WeatherService>(
      (ref) => WeatherService(
        dio: Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            sendTimeout: const Duration(seconds: 10),
          ),
        ),
        clock: const SystemClock(),
      ),
    );

final AsyncNotifierProvider<SlideshowController, SlideshowViewState>
slideshowControllerProvider =
    AsyncNotifierProvider<SlideshowController, SlideshowViewState>(
      SlideshowController.new,
    );

/// Drives playback, filtering, cache sync, night mode, and weather.
class SlideshowController extends AsyncNotifier<SlideshowViewState> {
  static const String noItemsMessage = 'No items match the current filters';
  static const String connectMessage = 'Connect an account';

  Timer? _timer;
  SlideshowEngine? _engine;
  AppSettings _settings = const AppSettings();
  bool _pausedByNight = false;
  bool _userPaused = false;
  bool _weatherFetching = false;
  bool _syncing = false;
  DateTime? _lastWeatherCheck;

  @override
  Future<SlideshowViewState> build() async {
    _timer?.cancel();
    final settings =
        ref.read(settingsControllerProvider).value ??
        await ref.read(settingsRepositoryProvider).load();
    if (!ref.mounted) {
      return const SlideshowViewState(loading: false);
    }
    _settings = settings;
    final cached = await _cachedAssets(settings);
    if (!ref.mounted) {
      return const SlideshowViewState(loading: false);
    }
    _scheduleAutoSync(settings, cached);
    final assets = _filteredAssets(cached, settings);
    final engine = SlideshowEngine(
      assets,
      intervalSeconds: settings.playback.intervalSeconds,
      shuffle: settings.playback.shuffle,
    );
    _engine = engine;
    _syncEngineDuration(engine);
    final night = _isNight(settings);
    final pauseForNight = night && settings.nightMode.pauseSlideshow;
    if (assets.isEmpty || pauseForNight) {
      engine.pause();
    }
    _pausedByNight = pauseForNight && assets.isNotEmpty;
    _userPaused = false;
    _startTimer();
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    ref.listen(settingsControllerProvider, (previous, next) {
      final value = next.value;
      if (value != null && ref.mounted) {
        unawaited(reload());
      }
    });
    return _viewState(
      engine: engine,
      cached: cached,
      nightMode: night,
      error: assets.isEmpty ? _emptyError(settings, cached) : null,
    );
  }

  Future<void> reload() async {
    if (!ref.mounted) {
      return;
    }
    final settings =
        ref.read(settingsControllerProvider).value ??
        await ref.read(settingsRepositoryProvider).load();
    if (!ref.mounted) {
      return;
    }
    _settings = settings;
    final cached = await _cachedAssets(settings);
    if (!ref.mounted) {
      return;
    }
    _scheduleAutoSync(settings, cached);
    final assets = _filteredAssets(cached, settings);
    final engine =
        _engine ??
        SlideshowEngine(
          assets,
          intervalSeconds: settings.playback.intervalSeconds,
          shuffle: settings.playback.shuffle,
        );
    engine.setInterval(settings.playback.intervalSeconds);
    engine.setShuffle(settings.playback.shuffle);
    engine.reorder(assets);
    _syncEngineDuration(engine);

    final night = _isNight(settings);
    final pauseForNight = night && settings.nightMode.pauseSlideshow;
    if (assets.isEmpty) {
      engine.pause();
      _pausedByNight = false;
    } else if (pauseForNight) {
      if (engine.playing) {
        engine.pause();
        _pausedByNight = true;
      }
    } else if (_pausedByNight) {
      _pausedByNight = false;
      if (!_userPaused) {
        engine.resume();
      }
    }

    final previousWeather = state.value?.weather;
    state = AsyncData(
      _viewState(
        engine: engine,
        cached: cached,
        nightMode: night,
        weather: _weatherConfigured(settings) ? previousWeather : null,
        error: assets.isEmpty ? _emptyError(settings, cached) : null,
      ),
    );
  }

  Future<void> syncNow() async {
    if (_syncing) {
      return;
    }
    _syncing = true;
    _setSyncing(true);
    try {
      final settings = _settings;
      final client = await ref
          .read(connectionControllerProvider.notifier)
          .clientFromStoredCredentials();
      await _syncService(client).syncAlbums(
        settings.connection.albumIds,
        prefetchCount: settings.cache.prefetchCount,
        quotaBytes: settings.cache.quotaBytes,
      );
      await reload();
    } on AppFailure catch (failure) {
      _setError(failure.message);
    } on Object {
      _setError('Sync failed');
    } finally {
      _syncing = false;
      _setSyncing(false);
    }
  }

  void _scheduleAutoSync(AppSettings settings, List<CachedAsset> cached) {
    if (_syncing) {
      return;
    }
    if (settings.connection.albumIds.isEmpty) {
      return;
    }
    if ((settings.connection.serverUrl ?? '').isEmpty) {
      return;
    }
    if (!_needsSync(cached)) {
      return;
    }
    _syncing = true;
    unawaited(_autoSync());
  }

  Future<void> _autoSync() async {
    try {
      final client = await ref
          .read(connectionControllerProvider.notifier)
          .clientFromStoredCredentials();
      final settings = _settings;
      await _syncService(client).syncAlbums(
        settings.connection.albumIds,
        prefetchCount: settings.cache.prefetchCount,
        quotaBytes: settings.cache.quotaBytes,
      );
      await reload();
    } on Object {
      return;
    } finally {
      _syncing = false;
      _setSyncing(false);
    }
  }

  CacheSyncService _syncService(ImmichClient client) {
    return CacheSyncService(
      client: client,
      store: ref.read(cacheStoreProvider),
      downloader: MediaDownloader(
        dio: Dio(),
        paths: ref.read(appPathsProvider),
      ),
      logger: ref.read(appLoggerProvider),
    );
  }

  bool _needsSync(List<CachedAsset> cached) {
    if (cached.isEmpty) {
      return true;
    }
    return cached.any((asset) => !_hasDisplayFile(asset));
  }

  bool _hasDisplayFile(CachedAsset asset) {
    final thumbnail = fileIfExists(asset.thumbnailPath) != null;
    if (asset.type == MediaKind.video) {
      return thumbnail;
    }
    if (asset.isDecodableImage) {
      return fileIfExists(asset.originalPath) != null || thumbnail;
    }
    return thumbnail;
  }

  void _setSyncing(bool value) {
    final current = state.value;
    if (current == null || !ref.mounted || current.syncing == value) {
      return;
    }
    state = AsyncData(current.copyWith(syncing: value));
  }

  void next() {
    final engine = _engine;
    if (engine == null || !engine.hasItems) {
      return;
    }
    engine.next();
    _syncEngineDuration(engine);
    _publishEngine(engine);
  }

  void previous() {
    final engine = _engine;
    if (engine == null || !engine.hasItems) {
      return;
    }
    engine.previous();
    _syncEngineDuration(engine);
    _publishEngine(engine);
  }

  void advanceIfCurrent(String assetId) {
    final engine = _engine;
    if (engine == null ||
        engine.current == null ||
        engine.current?.id != assetId) {
      return;
    }
    engine.next();
    _syncEngineDuration(engine);
    _publishEngine(engine);
  }

  void togglePause() {
    final engine = _engine;
    if (engine == null || !engine.hasItems) {
      return;
    }
    if (engine.playing) {
      engine.pause();
      _userPaused = true;
    } else {
      engine.resume();
      _userPaused = false;
      _pausedByNight = false;
    }
    _publishEngine(engine);
  }

  Future<WeatherSnapshot?> refreshWeather() async {
    if (_weatherFetching) {
      return state.value?.weather;
    }
    final overlays = _settings.overlays;
    final latitude = overlays.weatherLatitude;
    final longitude = overlays.weatherLongitude;
    if (!overlays.weather || latitude == null || longitude == null) {
      return null;
    }
    _weatherFetching = true;
    try {
      final snapshot = await ref
          .read(weatherServiceProvider)
          .current(
            latitude: latitude,
            longitude: longitude,
            unit: overlays.weatherUnit,
            locationLabel: overlays.weatherLocationLabel,
          );
      if (snapshot != null && ref.mounted) {
        final current = state.value;
        if (current != null) {
          state = AsyncData(current.copyWith(weather: snapshot));
        }
      }
      return snapshot;
    } on Object {
      return null;
    } finally {
      _weatherFetching = false;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final current = state.value;
    final engine = _engine;
    if (current == null || engine == null) {
      return;
    }
    final night = _isNight(_settings);
    final pauseForNight = night && _settings.nightMode.pauseSlideshow;
    if (pauseForNight && engine.playing) {
      engine.pause();
      _pausedByNight = true;
    } else if (!night && _pausedByNight) {
      _pausedByNight = false;
      if (!_userPaused) {
        engine.resume();
      }
    }
    if (engine.playing) {
      engine.tick(const Duration(seconds: 1));
    }
    _syncEngineDuration(engine);

    final now = DateTime.now();
    if (_weatherConfigured(_settings) &&
        !_weatherFetching &&
        (_lastWeatherCheck == null ||
            now.difference(_lastWeatherCheck!) >=
                const Duration(seconds: 30))) {
      _lastWeatherCheck = now;
      unawaited(refreshWeather());
    }

    state = AsyncData(
      _viewState(
        engine: engine,
        cached: current.cached,
        nightMode: night,
        weather: current.weather,
        error: current.error,
      ),
    );
  }

  void _syncEngineDuration(SlideshowEngine engine) {
    final current = engine.current;
    final duration = current?.duration;
    if (_settings.playback.videoPlaybackMode == VideoPlaybackMode.full &&
        current?.type == MediaKind.video &&
        duration != null &&
        duration > 0) {
      engine.setCurrentDuration(Duration(milliseconds: duration));
    } else {
      engine.setCurrentDuration(null);
    }
  }

  void _publishEngine(SlideshowEngine engine) {    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        assets: engine.sequence,
        currentIndex: engine.currentIndex,
        current: engine.current,
        playing: engine.playing,
        progress: engine.progress,
        total: engine.total,
        clearCurrent: engine.current == null,
      ),
    );
  }

  void _setError(String message) {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(error: message, loading: false, playing: false),
    );
  }

  SlideshowViewState _viewState({
    required SlideshowEngine engine,
    required List<CachedAsset> cached,
    required bool nightMode,
    String? error,
    WeatherSnapshot? weather,
  }) {
    return SlideshowViewState(
      assets: engine.sequence,
      currentIndex: engine.currentIndex,
      current: engine.current,
      playing: engine.playing,
      loading: false,
      nightMode: nightMode,
      error: error,
      weather: weather,
      total: engine.total,
      progress: engine.progress,
      cached: cached,
      syncing: _syncing,
    );
  }

  Future<List<CachedAsset>> _cachedAssets(AppSettings settings) {
    final albumIds = settings.connection.albumIds;
    if (albumIds.isEmpty) {
      return Future<List<CachedAsset>>.value(const <CachedAsset>[]);
    }
    return ref.read(cacheStoreProvider).getAssetsForAlbums(albumIds);
  }

  List<ImmichAsset> _filteredAssets(
    List<CachedAsset> cached,
    AppSettings settings,
  ) {
    final filter = MediaFilter(
      selectedAssetIds: settings.filters.selectedAssetIds,
    );
    final assets = filter.apply(cached.map(_toImmichAsset).toList());
    if (settings.playback.videoPlaybackMode == VideoPlaybackMode.off) {
      return assets
          .where((asset) => asset.type != MediaKind.video)
          .toList();
    }
    return assets;
  }

  bool _isNight(AppSettings settings) {
    return NightModeService.isActive(
      startMinutes: settings.nightMode.startMinutes,
      endMinutes: settings.nightMode.endMinutes,
      now: DateTime.now(),
      enabled: settings.nightMode.enabled,
    );
  }

  bool _weatherConfigured(AppSettings settings) {
    return settings.overlays.weather &&
        settings.overlays.weatherLatitude != null &&
        settings.overlays.weatherLongitude != null;
  }

  String _emptyError(AppSettings settings, List<CachedAsset> cached) {
    final server = settings.connection.serverUrl;
    final connected = server != null && server.isNotEmpty;
    if (!connected && cached.isEmpty) {
      return connectMessage;
    }
    return noItemsMessage;
  }

  ImmichAsset _toImmichAsset(CachedAsset asset) {
    return ImmichAsset(
      id: asset.id,
      type: asset.type,
      originalMimeType: asset.originalMimeType ?? '',
      fileCreatedAt: asset.exifDate,
      localDateTime: asset.exifDate,
      exif: ImmichExif(
        width: asset.width,
        height: asset.height,
        dateTimeOriginal: asset.exifDate,
        description: asset.description,
        city: asset.location,
        fileSizeInByte: asset.sizeBytes == 0 ? null : asset.sizeBytes,
      ),
      livePhotoVideoId: asset.livePhotoVideoId,
      duration: asset.duration,
      checksum: asset.checksum,
      aspectBucket: asset.aspectBucket,
    );
  }
}
