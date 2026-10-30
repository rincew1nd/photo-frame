import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/core/failures.dart';
import 'package:photoframe/data/cache/media_downloader.dart';
import 'package:photoframe/data/immich/immich_client.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/platform/paths.dart';

import '../../support/mock_immich_server.dart';

void main() {
  late MockImmichServer server;
  late Directory temporary;
  late InMemoryAppPaths paths;
  late ImmichClient client;
  late MediaDownloader downloader;

  setUp(() async {
    server = await MockImmichServer.start();
    temporary = await Directory.systemTemp.createTemp('photoframe_downloader_');
    paths = InMemoryAppPaths(temporary);
    client = ImmichClient(baseUri: server.apiUrl, apiKey: 'test-key');
    downloader = MediaDownloader(dio: Dio(), paths: paths);
  });

  tearDown(() async {
    await server.close();
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  Uri originalUri(String id) {
    return Uri.parse('${server.apiUrl}/assets/$id/original');
  }

  List<RecordedRequest> mediaRequests(String kind) {
    return server.requests
        .where((request) => request.uri.path.endsWith('/$kind'))
        .toList();
  }

  test('downloads thumbnail and original for a photo', () async {
    final asset = await client.getAsset('asset-1');
    final cached = await downloader.ensureAsset(
      client,
      asset,
      albumId: 'album-1',
    );
    final cache = await paths.cache();

    expect(cached.id, 'asset-1');
    expect(cached.type, MediaKind.photo);
    expect(cached.albumIds, <String>{'album-1'});
    expect(cached.checksum, asset.checksum);
    expect(cached.location, 'Testville, Testland');
    expect(cached.exifDate, isNotNull);
    expect(cached.hasThumbnailFile, isTrue);
    expect(cached.hasOriginalFile, isTrue);
    expect(
      cached.thumbnailPath,
      MediaDownloader.thumbnailPath(cache, assetId: 'asset-1'),
    );
    expect(
      cached.originalPath,
      MediaDownloader.originalPath(
        cache,
        albumId: 'album-1',
        assetId: 'asset-1',
        mimeType: 'image/jpeg',
      ),
    );

    final thumbnailBytes = await File(cached.thumbnailPath!).readAsBytes();
    expect(thumbnailBytes, <int>[82, 73, 70, 70, 1, 2, 3, 4]);
    final originalBytes = await File(cached.originalPath!).readAsBytes();
    expect(originalBytes, utf8.encode('original-asset-1'));
    expect(cached.sizeBytes, originalBytes.length);
    expect(await File('${cached.originalPath!}.part').exists(), isFalse);
    expect(await File('${cached.thumbnailPath!}.part').exists(), isFalse);
  });

  test('requests the preview rendition and stores a preview file', () async {
    final asset = await client.getAsset('asset-1');
    final cached = await downloader.ensureAsset(
      client,
      asset,
      albumId: 'album-1',
    );

    final request = mediaRequests('thumbnail').single;
    expect(request.uri.queryParameters['size'], 'preview');
    expect(p.basename(cached.thumbnailPath!), 'asset-1.preview.jpg');
  });

  test('downloads thumbnail and original for video assets', () async {
    final video = await client.getAsset('asset-3');
    final cache = await paths.cache();
    final cached = await downloader.ensureAsset(
      client,
      video,
      albumId: 'album-1',
    );

    expect(cached.type, MediaKind.video);
    expect(cached.hasThumbnailFile, isTrue);
    expect(cached.hasOriginalFile, isTrue);
    expect(
      cached.originalPath,
      MediaDownloader.originalPath(
        cache,
        albumId: 'album-1',
        assetId: 'asset-3',
        mimeType: 'video/mp4',
      ),
    );
    final originalBytes = await File(cached.originalPath!).readAsBytes();
    expect(originalBytes, utf8.encode('original-asset-3'));
    expect(cached.sizeBytes, originalBytes.length);
    expect(mediaRequests('original'), hasLength(1));
    expect(mediaRequests('thumbnail'), hasLength(1));
  });

  test('downloads the motion file for Live Photo assets', () async {
    final asset = await client.getAsset('asset-2');
    final cache = await paths.cache();
    final cached = await downloader.ensureAsset(
      client,
      asset,
      albumId: 'album-1',
    );

    expect(cached.type, MediaKind.livePhoto);
    expect(cached.hasOriginalFile, isTrue);
    expect(
      cached.liveVideoPath,
      MediaDownloader.liveVideoPath(cache, liveVideoId: 'live-video-2'),
    );
    final motion = File(cached.liveVideoPath!);
    expect(await motion.exists(), isTrue);
    final motionBytes = await motion.readAsBytes();
    expect(motionBytes, utf8.encode('original-live-video-2'));
    expect(cached.liveVideoSizeBytes, motionBytes.length);
    expect(mediaRequests('original'), hasLength(2));
  });

  test('deletes the part file and throws on checksum mismatch', () async {
    final cache = await paths.cache();
    final destination = File(p.join(cache.path, 'temp', 'mismatch.jpg'));
    await destination.parent.create(recursive: true);

    await expectLater(
      downloader.downloadToFile(
        uri: originalUri('asset-1'),
        headers: client.authHeaders(),
        destination: destination,
        expectedChecksum: 'AAAAAAAAAAAAAAAAAAAAAA==',
        attempts: 1,
      ),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.kind,
          'kind',
          FailureKind.invalidResponse,
        ),
      ),
    );
    expect(await destination.exists(), isFalse);
    expect(await File('${destination.path}.part').exists(), isFalse);
  });

  test('retries a 500 and then succeeds', () async {
    server.mediaFailuresRemaining = 1;
    final asset = await client.getAsset('asset-1');

    final file = await downloader.ensureThumbnail(client, asset);

    expect(file, isNotNull);
    expect(await file!.exists(), isTrue);
    expect(mediaRequests('thumbnail'), hasLength(2));
  });

  test('skips downloads when the checksum and size match', () async {
    final asset = await client.getAsset('asset-1');
    await downloader.ensureOriginal(client, asset, albumId: 'album-1');
    final first = mediaRequests('original').length;

    await downloader.ensureOriginal(client, asset, albumId: 'album-1');

    expect(first, 1);
    expect(mediaRequests('original'), hasLength(1));
  });

  test('resumes a partial download with a Range request', () async {
    final cache = await paths.cache();
    final destination = File(
      MediaDownloader.originalPath(
        cache,
        albumId: 'album-1',
        assetId: 'asset-1',
        mimeType: 'image/jpeg',
      ),
    );
    await destination.parent.create(recursive: true);
    final bytes = utf8.encode('original-asset-1');
    final part = File('${destination.path}.part');
    await part.writeAsBytes(bytes.sublist(0, 8));

    final asset = await client.getAsset('asset-1');
    final file = await downloader.ensureOriginal(
      client,
      asset,
      albumId: 'album-1',
    );

    expect(await file!.readAsBytes(), bytes);
    expect(await part.exists(), isFalse);
    final request = server.requests.lastWhere(
      (item) => item.uri.path.endsWith('/original'),
    );
    expect(request.header('range'), 'bytes=8-');
  });
}
