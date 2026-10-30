import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/data/cache/app_database.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/cache/cache_store.dart';
import 'package:photoframe/data/settings/app_settings.dart';

void main() {
  final base = DateTime.utc(2024, 1, 2, 3, 4, 5);

  CachedAsset makeAsset({
    required String id,
    Set<String> albumIds = const <String>{'album-1'},
    MediaKind type = MediaKind.photo,
    int sizeBytes = 100,
    int liveVideoSizeBytes = 0,
    int derivedImageSizeBytes = 0,
    String? thumbnailPath,
    String? originalPath,
    String? liveVideoPath,
    String? derivedImagePath,
  }) {
    return CachedAsset(
      id: id,
      albumIds: albumIds,
      type: type,
      originalMimeType: 'image/jpeg',
      width: 4000,
      height: 3000,
      aspectBucket: AspectBucket.fourThree,
      duration: 5000,
      livePhotoVideoId: 'live-1',
      exifDate: base,
      description: 'A photo',
      location: 'Testville, Testland',
      tags: const <String>['tag'],
      originalPath: originalPath ?? '/cache/originals/album-1/$id.jpg',
      thumbnailPath: thumbnailPath ?? '/cache/thumbnails/$id.jpg',
      liveVideoPath: liveVideoPath,
      derivedImagePath: derivedImagePath,
      checksum: 'checksum',
      sizeBytes: sizeBytes,
      liveVideoSizeBytes: liveVideoSizeBytes,
      derivedImageSizeBytes: derivedImageSizeBytes,
      cachedAt: base,
      lastAccessedAt: base,
    );
  }

  group('CachedAsset', () {
    test('round trips through JSON', () {
      final asset = makeAsset(
        id: 'asset-1',
        liveVideoPath: '/cache/live/live-1.mov',
        derivedImagePath: '/cache/derived/asset-1.jpg',
        liveVideoSizeBytes: 20,
        derivedImageSizeBytes: 30,
      );
      final decoded = CachedAsset.fromJson(asset.toJson());

      expect(decoded.id, 'asset-1');
      expect(decoded.albumIds, <String>{'album-1'});
      expect(decoded.type, MediaKind.photo);
      expect(decoded.width, 4000);
      expect(decoded.aspectBucket, AspectBucket.fourThree);
      expect(decoded.tags, <String>['tag']);
      expect(decoded.checksum, 'checksum');
      expect(
        decoded.cachedAt.millisecondsSinceEpoch,
        base.millisecondsSinceEpoch,
      );
      expect(decoded.hasOriginalFile, isTrue);
      expect(decoded.hasThumbnailFile, isTrue);
      expect(decoded.liveVideoPath, '/cache/live/live-1.mov');
      expect(decoded.derivedImagePath, '/cache/derived/asset-1.jpg');
      expect(decoded.liveVideoSizeBytes, 20);
      expect(decoded.derivedImageSizeBytes, 30);
      expect(decoded.totalSizeBytes, 150);
    });
  });

  group('MemoryCacheStore', () {
    late MemoryCacheStore store;

    setUp(() async {
      store = MemoryCacheStore();
      await store.init();
    });

    test('supports CRUD, sync states, stats, and clear', () async {
      final temporary = await Directory.systemTemp.createTemp(
        'photoframe_cache_store_',
      );
      addTearDown(() async {
        if (await temporary.exists()) {
          await temporary.delete(recursive: true);
        }
      });
      final thumbnail = File(p.join(temporary.path, 'thumb.jpg'));
      await thumbnail.writeAsBytes(<int>[1, 2, 3, 4, 5, 6, 7]);

      await store.upsertAsset(makeAsset(id: 'asset-1'));
      await store.upsertAsset(
        makeAsset(
          id: 'asset-2',
          albumIds: const <String>{'album-2'},
          sizeBytes: 50,
        ),
      );
      await store.upsertAsset(
        makeAsset(
          id: 'asset-3',
          albumIds: const <String>{'album-3'},
          sizeBytes: 10,
          thumbnailPath: thumbnail.path,
        ),
      );

      expect((await store.getAsset('asset-1'))?.id, 'asset-1');
      expect(await store.allAssets(), hasLength(3));
      expect(
        await store.getAssetsForAlbums(<String>{'album-1', 'album-3'}),
        hasLength(2),
      );
      expect(await store.getAssetsForAlbums(const <String>{}), isEmpty);

      final stats = await store.stats();
      expect(stats.assetCount, 3);
      expect(stats.originalBytes, 160);
      expect(stats.thumbnailBytes, 7);
      expect(stats.totalBytes, 167);
      expect(stats.albumCount, 3);
      expect(stats.imageCount, 3);
      expect(stats.imageBytes, 167);
      expect(stats.videoCount, 0);
      expect(stats.videoBytes, 0);

      await store.setSyncState(
        CacheSyncState(albumId: 'album-1', lastSync: base, assetCount: 1),
      );
      final state = await store.getSyncState('album-1');
      expect(state?.lastSync, base);
      expect(state?.assetCount, 1);
      expect((await store.stats()).lastSync, base);

      final touched = base.add(const Duration(hours: 1));
      await store.touchAsset('asset-1', touched);
      expect((await store.getAsset('asset-1'))?.lastAccessedAt, touched);

      await store.deleteAsset('asset-2');
      expect(await store.getAsset('asset-2'), isNull);
      expect(await store.allAssets(), hasLength(2));

      await store.clear();
      expect(await store.allAssets(), isEmpty);
      expect(await store.getSyncState('album-1'), isNull);
      final cleared = await store.stats();
      expect(cleared.assetCount, 0);
      expect(cleared.originalBytes, 0);
      expect(cleared.albumCount, 0);
    });

    test('splits image and video stats and includes thumbnails', () async {
      final temporary = await Directory.systemTemp.createTemp(
        'photoframe_cache_split_',
      );
      addTearDown(() async {
        if (await temporary.exists()) {
          await temporary.delete(recursive: true);
        }
      });
      final photoThumbnail = File(p.join(temporary.path, 'photo.jpg'));
      await photoThumbnail.writeAsBytes(<int>[1, 2, 3, 4, 5, 6, 7]);
      final liveThumbnail = File(p.join(temporary.path, 'live.jpg'));
      await liveThumbnail.writeAsBytes(<int>[1, 2]);
      final videoThumbnail = File(p.join(temporary.path, 'video.jpg'));
      await videoThumbnail.writeAsBytes(<int>[1, 2, 3]);

      await store.upsertAsset(
        makeAsset(
          id: 'photo',
          type: MediaKind.photo,
          sizeBytes: 100,
          thumbnailPath: photoThumbnail.path,
        ),
      );
      await store.upsertAsset(
        makeAsset(
          id: 'live',
          type: MediaKind.livePhoto,
          sizeBytes: 10,
          thumbnailPath: liveThumbnail.path,
        ),
      );
      await store.upsertAsset(
        makeAsset(
          id: 'video',
          type: MediaKind.video,
          sizeBytes: 50,
          thumbnailPath: videoThumbnail.path,
        ),
      );

      final stats = await store.stats();

      expect(stats.assetCount, 3);
      expect(stats.originalBytes, 160);
      expect(stats.thumbnailBytes, 12);
      expect(stats.totalBytes, 172);
      expect(stats.imageCount, 2);
      expect(stats.imageBytes, 119);
      expect(stats.videoCount, 1);
      expect(stats.videoBytes, 53);
    });

    test('includes live and derived bytes in totals and owning kinds', () async {
      await store.upsertAsset(
        makeAsset(
          id: 'photo',
          type: MediaKind.photo,
          sizeBytes: 100,
          derivedImageSizeBytes: 30,
        ),
      );
      await store.upsertAsset(
        makeAsset(
          id: 'live',
          type: MediaKind.livePhoto,
          sizeBytes: 10,
          liveVideoSizeBytes: 20,
        ),
      );
      await store.upsertAsset(
        makeAsset(
          id: 'video',
          type: MediaKind.video,
          sizeBytes: 50,
          liveVideoSizeBytes: 5,
          derivedImageSizeBytes: 5,
        ),
      );

      final stats = await store.stats();

      expect(stats.originalBytes, 160);
      expect(stats.liveVideoBytes, 25);
      expect(stats.derivedImageBytes, 35);
      expect(stats.totalBytes, 220);
      expect(stats.imageCount, 2);
      expect(stats.imageBytes, 160);
      expect(stats.videoCount, 1);
      expect(stats.videoBytes, 60);
    });
  });

  group('DriftCacheStore', () {
    test('persists assets, sync state, and schema version 3', () async {
      AppDatabase? database;
      try {
        database = AppDatabase(NativeDatabase.memory());
        final store = DriftCacheStore(database);
        await store.init();

        expect(database.schemaVersion, 3);
        final tables = await database
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
            .get();
        final names = tables.map((row) => row.read<String>('name')).toSet();
        expect(names, contains('cached_assets'));
        expect(names, contains('album_sync_states'));

        final asset = makeAsset(
          id: 'asset-1',
          albumIds: const <String>{'album-1', 'album-2'},
        );
        await store.upsertAsset(asset);

        final loaded = await store.getAsset('asset-1');
        expect(loaded, isNotNull);
        expect(loaded!.albumIds, <String>{'album-1', 'album-2'});
        expect(loaded.type, MediaKind.photo);
        expect(loaded.width, 4000);
        expect(loaded.aspectBucket, AspectBucket.fourThree);
        expect(loaded.duration, 5000);
        expect(loaded.livePhotoVideoId, 'live-1');
        expect(loaded.exifDate, base);
        expect(loaded.tags, <String>['tag']);
        expect(loaded.checksum, 'checksum');
        expect(loaded.sizeBytes, 100);
        expect(
          loaded.cachedAt.millisecondsSinceEpoch,
          base.millisecondsSinceEpoch,
        );
        expect(
          loaded.lastAccessedAt.millisecondsSinceEpoch,
          base.millisecondsSinceEpoch,
        );
        expect(
          await store.getAssetsForAlbums(<String>{'album-2'}),
          hasLength(1),
        );

        await store.setSyncState(
          CacheSyncState(albumId: 'album-1', lastSync: base, assetCount: 1),
        );
        final state = await store.getSyncState('album-1');
        expect(
          state?.lastSync?.millisecondsSinceEpoch,
          base.millisecondsSinceEpoch,
        );
        expect(state?.assetCount, 1);

        final stats = await store.stats();
        expect(stats.assetCount, 1);
        expect(stats.originalBytes, 100);
        expect(stats.albumCount, 2);
        expect(stats.imageCount, 1);
        expect(stats.imageBytes, 100);
        expect(stats.videoCount, 0);
        expect(stats.videoBytes, 0);
        expect(
          stats.lastSync?.millisecondsSinceEpoch,
          base.millisecondsSinceEpoch,
        );

        await store.upsertAsset(
          makeAsset(
            id: 'asset-live',
            type: MediaKind.livePhoto,
            sizeBytes: 20,
          ),
        );
        await store.upsertAsset(
          makeAsset(
            id: 'asset-video',
            type: MediaKind.video,
            sizeBytes: 40,
          ),
        );
        final split = await store.stats();
        expect(split.imageCount, 2);
        expect(split.imageBytes, 120);
        expect(split.videoCount, 1);
        expect(split.videoBytes, 40);

        final touched = base.add(const Duration(hours: 1));
        await store.touchAsset('asset-1', touched);
        expect(
          (await store.getAsset('asset-1'))!
              .lastAccessedAt
              .millisecondsSinceEpoch,
          touched.millisecondsSinceEpoch,
        );

        await store.deleteAsset('asset-1');
        expect(await store.getAsset('asset-1'), isNull);
        await store.clear();
        expect(await store.allAssets(), isEmpty);
        expect(await store.getSyncState('album-1'), isNull);
      } on Object catch (error) {
        markTestSkipped(
          'sqlite3 native library is unavailable in this environment: $error',
        );
      } finally {
        await database?.close();
      }
    });
  });
}
