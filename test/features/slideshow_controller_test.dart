import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/app/connection_providers.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/cache/cache_store.dart';
import 'package:photoframe/data/immich/immich_client.dart';
import 'package:photoframe/data/media/still_decoder.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/features/slideshow/slideshow_controller.dart';
import 'package:photoframe/platform/paths.dart';

import '../support/mock_immich_server.dart';

class _FakeStillDecoder implements StillDecoder {
  @override
  Future<DecodedRgba?> decode(String path, {required int maxLongSide}) async {
    const width = 8;
    const height = 4;
    return DecodedRgba(
      bytes: Uint8List.fromList(List<int>.filled(width * height * 4, 255)),
      width: width,
      height: height,
    );
  }
}

class _FakeConnectionController extends ConnectionController {
  _FakeConnectionController(this.client);

  final ImmichClient client;

  @override
  Future<ConnectionState> build() async =>
      const ConnectionState(settings: AppSettings());

  @override
  Future<ImmichClient> clientFromStoredCredentials() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return client;
  }
}

void main() {
  late MockImmichServer server;
  late Directory temporary;
  late InMemoryAppPaths paths;
  late MemoryCacheStore store;
  late ImmichClient client;
  late ProviderContainer container;

  setUp(() async {
    server = await MockImmichServer.start();
    temporary = Directory.systemTemp.createTempSync('photoframe_slideshow_');
    paths = InMemoryAppPaths(temporary);
    store = MemoryCacheStore();
    client = ImmichClient(baseUri: server.apiUrl, apiKey: 'test-key');
    final settings = AppSettings(
      connection: ConnectionSettings(
        serverUrl: server.apiUrl.toString(),
        albumIds: const <String>{'album-1'},
      ),
    );
    container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(settings),
        ),
        cacheStoreProvider.overrideWithValue(store),
        appPathsProvider.overrideWithValue(paths),
        appLoggerProvider.overrideWithValue(AppLogger()),
        stillDecoderProvider.overrideWithValue(_FakeStillDecoder()),
        connectionControllerProvider.overrideWith(
          () => _FakeConnectionController(client),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await server.close();
    if (temporary.existsSync()) {
      temporary.deleteSync(recursive: true);
    }
  });

  test('build auto-syncs an empty cache and clears the syncing flag', () async {
    final initial = await container.read(slideshowControllerProvider.future);
    expect(initial.cached, isEmpty);
    expect(initial.syncing, isTrue);

    SlideshowViewState? state;
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      state = container.read(slideshowControllerProvider).value;
      final assets = await store.allAssets();
      if (state != null && !state.syncing && assets.length == 3) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    state = container.read(slideshowControllerProvider).value;
    expect(state?.syncing, isFalse);
    expect(state?.cached, hasLength(3));
    expect(state?.current, isNotNull);
    expect(await store.allAssets(), hasLength(3));
  });

  test('build auto-syncs when a live photo is missing its motion', () async {
    final now = DateTime.utc(2026);
    final still = File('${temporary.path}/live.jpg')
      ..writeAsBytesSync(<int>[0, 1, 2]);
    final thumbnail = File('${temporary.path}/live_thumb.jpg')
      ..writeAsBytesSync(<int>[0, 1, 2]);
    await store.upsertAsset(
      CachedAsset(
        id: 'live-1',
        type: MediaKind.livePhoto,
        originalMimeType: 'image/jpeg',
        originalPath: still.path,
        thumbnailPath: thumbnail.path,
        livePhotoVideoId: 'live-video-1',
        albumIds: const <String>{'album-1'},
        cachedAt: now,
        lastAccessedAt: now,
      ),
    );

    final initial = await container.read(slideshowControllerProvider.future);
    expect(initial.syncing, isTrue);
    expect(initial.cached.single.id, 'live-1');

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (container.read(slideshowControllerProvider).value?.syncing == false) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  });

  test('ensureDerived stores a derived image and refreshes cached state', () async {
    final original = File('${temporary.path}/original.heic')
      ..writeAsBytesSync(<int>[0, 1, 2, 3]);
    final thumbnail = File('${temporary.path}/thumb.jpg')
      ..writeAsBytesSync(<int>[0, 1, 2, 3]);
    final now = DateTime.utc(2026);
    await store.upsertAsset(
      CachedAsset(
        id: 'heic-1',
        originalMimeType: 'image/heic',
        originalPath: original.path,
        thumbnailPath: thumbnail.path,
        checksum: 'abcdef1234567890',
        albumIds: const <String>{'album-1'},
        cachedAt: now,
        lastAccessedAt: now,
      ),
    );

    final state = await container.read(slideshowControllerProvider.future);
    final asset = state.cached.firstWhere((entry) => entry.id == 'heic-1');
    await container
        .read(slideshowControllerProvider.notifier)
        .ensureDerived(asset, targetLongSide: 320);

    final stored = await store.getAsset('heic-1');
    expect(stored?.derivedImagePath, isNotNull);
    expect(File(stored!.derivedImagePath!).existsSync(), isTrue);
    expect(stored.derivedImageSizeBytes, greaterThan(0));

    final refreshed = container.read(slideshowControllerProvider).value;
    final updated = refreshed!.cached.firstWhere(
      (entry) => entry.id == 'heic-1',
    );
    expect(updated.derivedImagePath, stored.derivedImagePath);
  });

  test('build skips videos when asset.download is denied', () async {
    final now = DateTime.utc(2026);
    final localStore = MemoryCacheStore();
    final files = <File>[
      File('${temporary.path}/photo.jpg')..writeAsBytesSync(<int>[0, 1, 2]),
      File('${temporary.path}/photo_thumb.jpg')
        ..writeAsBytesSync(<int>[0, 1, 2]),
      File('${temporary.path}/video.mp4')..writeAsBytesSync(<int>[3, 4, 5]),
      File('${temporary.path}/video_thumb.jpg')
        ..writeAsBytesSync(<int>[3, 4, 5]),
    ];
    await localStore.upsertAsset(
      CachedAsset(
        id: 'photo-1',
        originalMimeType: 'image/jpeg',
        originalPath: files[0].path,
        thumbnailPath: files[1].path,
        albumIds: const <String>{'album-1'},
        cachedAt: now,
        lastAccessedAt: now,
      ),
    );
    await localStore.upsertAsset(
      CachedAsset(
        id: 'video-1',
        type: MediaKind.video,
        originalMimeType: 'video/mp4',
        originalPath: files[2].path,
        thumbnailPath: files[3].path,
        duration: 5000,
        albumIds: const <String>{'album-1'},
        cachedAt: now,
        lastAccessedAt: now,
      ),
    );

    AppSettings settingsWith(String downloadStatus) => AppSettings(
      connection: ConnectionSettings(
        serverUrl: server.apiUrl.toString(),
        albumIds: const <String>{'album-1'},
        permissions: <String, String>{'asset.download': downloadStatus},
      ),
      playback: const PlaybackSettings(
        videoPlaybackMode: VideoPlaybackMode.full,
      ),
    );

    ProviderContainer containerWith(AppSettings settings) => ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(settings),
        ),
        cacheStoreProvider.overrideWithValue(localStore),
      ],
    );

    final denied = containerWith(settingsWith('denied'));
    addTearDown(denied.dispose);
    final deniedState = await denied.read(slideshowControllerProvider.future);
    expect(deniedState.assets.map((asset) => asset.id), <String>['photo-1']);
    expect(
      deniedState.assets.any((asset) => asset.type == MediaKind.video),
      isFalse,
    );

    final granted = containerWith(settingsWith('granted'));
    addTearDown(granted.dispose);
    final grantedState = await granted.read(
      slideshowControllerProvider.future,
    );
    expect(
      grantedState.assets.any((asset) => asset.type == MediaKind.video),
      isTrue,
    );
  });
}
