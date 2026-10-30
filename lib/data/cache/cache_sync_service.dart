import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:photoframe/core/clock.dart';
import 'package:photoframe/core/failures.dart';
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/cache/cache_store.dart';
import 'package:photoframe/data/cache/eviction_policy.dart';
import 'package:photoframe/data/cache/media_downloader.dart';
import 'package:photoframe/data/immich/immich_client.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/platform/paths.dart';

class CacheSyncResult {
  const CacheSyncResult({
    this.downloaded = 0,
    this.skipped = 0,
    this.failed = 0,
    this.evicted = 0,
    required this.stats,
  });

  final int downloaded;
  final int skipped;
  final int failed;
  final int evicted;
  final CacheStats stats;
}

class CacheSyncService {
  CacheSyncService({
    required this.client,
    required this.store,
    required this.downloader,
    required this.logger,
    Clock? clock,
  }) : clock = clock ?? const SystemClock();

  final ImmichClient client;
  final CacheStore store;
  final MediaDownloader downloader;
  final AppLogger logger;
  final Clock clock;

  Future<CacheSyncResult> syncAlbums(
    Set<String> albumIds, {
    int prefetchCount = 3,
    int quotaBytes = 4 * 1024 * 1024 * 1024,
    Set<String> protectedIds = const <String>{},
  }) async {
    var downloaded = 0;
    var skipped = 0;
    var failed = 0;
    var evicted = 0;

    for (final albumId in albumIds) {
      final List<ImmichAsset> assets;
      try {
        assets = await client.fetchAllAlbumAssets(albumId);
      } on AppFailure catch (failure) {
        logger.warning('Album sync failed for $albumId', error: failure);
        continue;
      }

      for (final asset in assets) {
        final existing = await store.getAsset(asset.id);
        final hadFiles = existing != null && await _hasFiles(existing, true);
        try {
          final cached = await downloader.ensureAsset(
            client,
            asset,
            albumId: albumId,
            includeOriginal: true,
          );
          final merged = cached.copyWith(
            albumIds: <String>{...?existing?.albumIds, albumId},
            cachedAt: existing?.cachedAt ?? cached.cachedAt,
            lastAccessedAt: existing?.lastAccessedAt ?? cached.lastAccessedAt,
          );
          await store.upsertAsset(merged);
          if (hadFiles) {
            skipped++;
          } else {
            downloaded++;
          }
        } on AppFailure catch (failure) {
          failed++;
          logger.warning('Asset sync failed for ${asset.id}', error: failure);
        }
      }

      await store.setSyncState(
        CacheSyncState(
          albumId: albumId,
          lastSync: clock.now(),
          assetCount: assets.length,
        ),
      );
    }

    final all = await store.allAssets();
    final selection = EvictionSelection.select(
      assets: all,
      quotaBytes: quotaBytes,
      incomingBytes: 0,
      protectedIds: protectedIds,
    );
    for (final asset in selection.evicted) {
      await _deleteFiles(asset);
      await store.deleteAsset(asset.id);
      evicted++;
    }

    return CacheSyncResult(
      downloaded: downloaded,
      skipped: skipped,
      failed: failed,
      evicted: evicted,
      stats: await store.stats(),
    );
  }

  Future<CachedAsset?> resolve(String assetId) async {
    final asset = await store.getAsset(assetId);
    if (asset == null) {
      return null;
    }
    for (final path in <String?>[
      asset.derivedImagePath,
      asset.originalPath,
      asset.thumbnailPath,
    ]) {
      if (path == null || path.isEmpty) {
        continue;
      }
      if (await File(path).exists()) {
        final now = clock.now();
        await store.touchAsset(asset.id, now);
        return asset.copyWith(lastAccessedAt: now);
      }
    }
    return null;
  }

  Future<List<CachedAsset>> prefetch(
    List<ImmichAsset> sequence,
    int currentIndex,
    int count,
  ) async {
    if (sequence.isEmpty || count <= 0) {
      return <CachedAsset>[];
    }

    final rows = <CachedAsset>[];
    final seen = <String>{};
    for (var offset = 1; offset <= count; offset++) {
      final index = (currentIndex + offset) % sequence.length;
      final asset = sequence[index];
      if (!seen.add(asset.id)) {
        continue;
      }

      final existing = await store.getAsset(asset.id);
      final albumId = existing != null && existing.albumIds.isNotEmpty
          ? existing.albumIds.first
          : 'prefetch';
      try {
        final cached = await downloader.ensureAsset(
          client,
          asset,
          albumId: albumId,
          includeOriginal: true,
        );
        final merged = cached.copyWith(
          albumIds: <String>{...?existing?.albumIds, albumId},
          cachedAt: existing?.cachedAt ?? cached.cachedAt,
          lastAccessedAt: existing?.lastAccessedAt ?? cached.lastAccessedAt,
        );
        await store.upsertAsset(merged);
        rows.add(merged);
      } on AppFailure catch (failure) {
        logger.warning('Prefetch failed for asset ${asset.id}', error: failure);
      }
    }
    return rows;
  }

  Future<void> clear() async {
    await store.clear();
    final cache = await downloader.paths.cache();
    for (final name in cacheSubdirectories) {
      final directory = Directory(p.join(cache.path, name));
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      await directory.create(recursive: true);
    }
  }

  Future<bool> _hasFiles(CachedAsset asset, bool includeOriginal) async {
    final thumbnail = asset.thumbnailPath;
    if (thumbnail == null ||
        thumbnail.isEmpty ||
        !await File(thumbnail).exists()) {
      return false;
    }
    if (!includeOriginal) {
      return true;
    }
    final original = asset.originalPath;
    if (original == null ||
        original.isEmpty ||
        !await File(original).exists()) {
      return false;
    }
    final liveVideoId = asset.livePhotoVideoId;
    if (liveVideoId != null && liveVideoId.isNotEmpty) {
      final liveVideo = asset.liveVideoPath;
      if (liveVideo == null ||
          liveVideo.isEmpty ||
          !await File(liveVideo).exists()) {
        return false;
      }
    }
    return true;
  }

  Future<void> _deleteFiles(CachedAsset asset) async {
    for (final path in <String?>[
      asset.originalPath,
      asset.thumbnailPath,
      asset.liveVideoPath,
      asset.derivedImagePath,
    ]) {
      if (path == null || path.isEmpty) {
        continue;
      }
      final file = File(path);
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } on FileSystemException {
        continue;
      }
    }
  }
}
