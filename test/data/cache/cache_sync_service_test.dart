import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/core/clock.dart';
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/cache/cache_store.dart';
import 'package:photoframe/data/cache/cache_sync_service.dart';
import 'package:photoframe/data/cache/media_downloader.dart';
import 'package:photoframe/data/immich/immich_client.dart';
import 'package:photoframe/platform/paths.dart';

import '../../support/mock_immich_server.dart';

class _FixedClock implements Clock {
  _FixedClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

void main() {
  late MockImmichServer server;
  late Directory temporary;
  late InMemoryAppPaths paths;
  late ImmichClient client;
  late MemoryCacheStore store;
  late MediaDownloader downloader;
  late CacheSyncService service;
  late DateTime now;

  setUp(() async {
    server = await MockImmichServer.start();
    temporary = await Directory.systemTemp.createTemp('photoframe_sync_');
    paths = InMemoryAppPaths(temporary);
    client = ImmichClient(baseUri: server.apiUrl, apiKey: 'test-key');
    store = MemoryCacheStore();
    await store.init();
    now = DateTime.utc(2024, 5, 1, 12);
    final clock = _FixedClock(now);
    downloader = MediaDownloader(dio: Dio(), paths: paths, clock: clock);
    service = CacheSyncService(
      client: client,
      store: store,
      downloader: downloader,
      logger: AppLogger(),
      clock: clock,
    );
  });

  tearDown(() async {
    await server.close();
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  List<RecordedRequest> mediaRequests(String kind) {
    return server.requests
        .where((request) => request.uri.path.endsWith('/$kind'))
        .toList();
  }

  CachedAsset seedAsset({
    required String id,
    required String path,
    required int sizeBytes,
    required DateTime accessed,
  }) {
    return CachedAsset(
      id: id,
      originalPath: path,
      sizeBytes: sizeBytes,
      cachedAt: accessed,
      lastAccessedAt: accessed,
    );
  }

  test(
    'syncs originals, thumbnails, and live photo motion',
    () async {
      final result = await service.syncAlbums(<String>{'album-1'});
      final cache = await paths.cache();

      expect(result.downloaded, 3);
      expect(result.skipped, 0);
      expect(result.failed, 0);
      expect(mediaRequests('original'), hasLength(4));
      expect(mediaRequests('thumbnail'), hasLength(3));

      final photo = await store.getAsset('asset-1');
      expect(photo?.hasOriginalFile, isTrue);
      expect(photo?.hasThumbnailFile, isTrue);
      expect(photo?.albumIds, <String>{'album-1'});

      final video = await store.getAsset('asset-3');
      expect(video?.hasOriginalFile, isTrue);
      expect(video?.hasThumbnailFile, isTrue);
      expect(
        video?.originalPath,
        MediaDownloader.originalPath(
          cache,
          albumId: 'album-1',
          assetId: 'asset-3',
          mimeType: 'video/mp4',
        ),
      );

      final live = await store.getAsset('asset-2');
      expect(
        live?.liveVideoPath,
        MediaDownloader.liveVideoPath(cache, liveVideoId: 'live-video-2'),
      );
      expect(await File(live!.liveVideoPath!).exists(), isTrue);

      final state = await store.getSyncState('album-1');
      expect(state?.assetCount, 3);
      expect(state?.lastSync, now);

      expect(result.stats.assetCount, 3);
      expect(result.stats.originalBytes, greaterThan(0));
      expect(result.stats.liveVideoBytes, greaterThan(0));
      expect(result.stats.albumCount, 1);
      expect(result.stats.lastSync, now);
    },
  );

  test('second sync skips valid cached files', () async {
    await service.syncAlbums(<String>{'album-1'});
    final originals = mediaRequests('original').length;
    final thumbnails = mediaRequests('thumbnail').length;

    final result = await service.syncAlbums(<String>{'album-1'});

    expect(result.downloaded, 0);
    expect(result.skipped, 3);
    expect(result.failed, 0);
    expect(mediaRequests('original'), hasLength(originals));
    expect(mediaRequests('thumbnail'), hasLength(thumbnails));
  });

  test('prefetch downloads the next slides and wraps around', () async {
    final sequence = await client.fetchAllAlbumAssets('album-1');

    final rows = await service.prefetch(sequence, 2, 2);

    expect(rows.map((asset) => asset.id), <String>['asset-1', 'asset-2']);
    expect(await store.getAsset('asset-1'), isNotNull);
    expect(await store.getAsset('asset-2'), isNotNull);
    expect(await store.getAsset('asset-3'), isNull);
    expect(mediaRequests('original'), hasLength(3));
  });

  test(
    'eviction protects current and next and deletes evicted files',
    () async {
      final cache = await paths.cache();
      final protectedFile = File(
        p.join(cache.path, 'originals', 'old-protected.jpg'),
      );
      final freeFile = File(p.join(cache.path, 'originals', 'old-free.jpg'));
      await protectedFile.parent.create(recursive: true);
      await protectedFile.writeAsBytes(Uint8List(100));
      await freeFile.writeAsBytes(Uint8List(100));

      await store.upsertAsset(
        seedAsset(
          id: 'old-protected',
          path: protectedFile.path,
          sizeBytes: 1000,
          accessed: now.subtract(const Duration(hours: 2)),
        ),
      );
      await store.upsertAsset(
        seedAsset(
          id: 'old-free',
          path: freeFile.path,
          sizeBytes: 1000,
          accessed: now.subtract(const Duration(hours: 1)),
        ),
      );

      final result = await service.syncAlbums(
        <String>{'album-1'},
        quotaBytes: 1100,
        protectedIds: const <String>{'old-protected'},
      );

      expect(result.evicted, 1);
      expect(await store.getAsset('old-protected'), isNotNull);
      expect(await store.getAsset('old-free'), isNull);
      expect(await protectedFile.exists(), isTrue);
      expect(await freeFile.exists(), isFalse);
    },
  );

  test('continues when one asset fails', () async {
    server.mediaFailuresRemaining = 3;

    final result = await service.syncAlbums(<String>{'album-1'});

    expect(result.failed, 1);
    expect(result.downloaded, 2);
    expect(result.stats.assetCount, 2);
    expect(await store.getAsset('asset-1'), isNull);
    expect(await store.getAsset('asset-2'), isNotNull);
    expect(await store.getAsset('asset-3'), isNotNull);
  });

  test('resolve returns a touched asset with a local file', () async {
    await service.syncAlbums(<String>{'album-1'});

    final resolved = await service.resolve('asset-1');

    expect(resolved, isNotNull);
    expect(resolved!.lastAccessedAt, now);
    expect(await File(resolved.originalPath!).exists(), isTrue);
  });

  test('clear removes cached rows and media directories', () async {
    await service.syncAlbums(<String>{'album-1'});
    final cache = await paths.cache();

    await service.clear();

    expect(await store.allAssets(), isEmpty);
    expect(await store.getSyncState('album-1'), isNull);
    expect(Directory(p.join(cache.path, 'originals')).listSync(), isEmpty);
    expect(Directory(p.join(cache.path, 'thumbnails')).listSync(), isEmpty);
    expect(Directory(p.join(cache.path, 'live')).listSync(), isEmpty);
    expect(Directory(p.join(cache.path, 'derived')).listSync(), isEmpty);
  });

  test('sync re-downloads a missing live photo motion file', () async {
    await service.syncAlbums(<String>{'album-1'});
    final cache = await paths.cache();
    final motion = File(
      MediaDownloader.liveVideoPath(cache, liveVideoId: 'live-video-2'),
    );
    expect(await motion.exists(), isTrue);
    await motion.delete();

    final originals = mediaRequests('original').length;
    final thumbnails = mediaRequests('thumbnail').length;

    await service.syncAlbums(<String>{'album-1'});

    final newOriginals = mediaRequests('original');
    expect(newOriginals, hasLength(originals + 1));
    expect(
      newOriginals.last.uri.path,
      endsWith('/assets/live-video-2/original'),
    );
    expect(mediaRequests('thumbnail'), hasLength(thumbnails));
    expect(await motion.exists(), isTrue);
  });
}
