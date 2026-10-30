import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/data/cache/media_downloader.dart';
import 'package:photoframe/platform/paths.dart';

void main() {
  late Directory temporary;
  late Directory cache;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'photoframe_cache_paths_',
    );
    final paths = InMemoryAppPaths(temporary);
    cache = await paths.cache();
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('nested original path sanitizes album and asset ids', () {
    final path = MediaDownloader.originalPath(
      cache,
      albumId: 'album/1',
      assetId: 'a:b/c',
      mimeType: 'image/png',
    );

    expect(
      p.equals(p.dirname(path), p.join(cache.path, 'originals', 'album_1')),
      isTrue,
      reason: path,
    );
    expect(p.basename(path), 'a_b_c.png');
  });

  test('original path uses the mime extension', () {
    expect(
      p.basename(
        MediaDownloader.originalPath(
          cache,
          albumId: 'album-1',
          assetId: 'asset-1',
          mimeType: 'video/quicktime',
        ),
      ),
      'asset-1.mov',
    );
    expect(
      p.basename(
        MediaDownloader.originalPath(
          cache,
          albumId: 'album-1',
          assetId: 'asset-1',
          mimeType: null,
        ),
      ),
      'asset-1.bin',
    );
  });

  test('thumbnail path stays flat and uses the preview variant', () {
    final path = MediaDownloader.thumbnailPath(cache, assetId: 'asset/1');

    expect(p.equals(p.dirname(path), p.join(cache.path, 'thumbnails')), isTrue);
    expect(p.basename(path), 'asset_1.preview.jpg');
  });

  test('live video path lives in the live directory', () {
    final path = MediaDownloader.liveVideoPath(cache, liveVideoId: 'live-1');

    expect(p.equals(p.dirname(path), p.join(cache.path, 'live')), isTrue);
    expect(p.basename(path), 'live-1.mov');
  });

  test('cache creates all media subdirectories', () async {
    final freshCache = await InMemoryAppPaths(
      Directory(p.join(temporary.path, 'fresh')),
    ).cache();
    for (final name in <String>['originals', 'thumbnails', 'live', 'derived']) {
      expect(
        Directory(p.join(freshCache.path, name)).existsSync(),
        isTrue,
        reason: name,
      );
    }
  });

  test('cacheFilePath keeps single-segment categories flat', () {
    final path = cacheFilePath(
      cache,
      category: 'thumbnails',
      assetId: 'asset-1',
      mimeType: 'image/jpeg',
    );

    expect(p.equals(p.dirname(path), p.join(cache.path, 'thumbnails')), isTrue);
    expect(p.basename(path), 'asset-1.jpg');
  });
}
