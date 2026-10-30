import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/core/failures.dart';
import 'package:photoframe/data/immich/immich_client.dart';
import 'package:photoframe/data/settings/app_settings.dart';

import '../../support/mock_immich_server.dart';

void main() {
  late MockImmichServer server;

  setUp(() async {
    server = await MockImmichServer.start();
  });

  tearDown(() async {
    await server.close();
  });

  ImmichClient client({String? apiKey = 'test-key', String? accessToken}) {
    return ImmichClient(
      baseUri: server.apiUrl,
      apiKey: apiKey,
      accessToken: accessToken,
    );
  }

  Matcher failureKind(FailureKind kind) {
    return isA<AppFailure>().having((failure) => failure.kind, 'kind', kind);
  }

  group('normalizeBaseUrl', () {
    test('normalizes server roots to the api path', () {
      expect(
        ImmichClient.normalizeBaseUrl('http://host').toString(),
        'http://host/api',
      );
      expect(
        ImmichClient.normalizeBaseUrl('https://host/').toString(),
        'https://host/api',
      );
      expect(
        ImmichClient.normalizeBaseUrl('http://host:8080/immich').toString(),
        'http://host:8080/immich/api',
      );
      expect(
        ImmichClient.normalizeBaseUrl('http://host/api/').toString(),
        'http://host/api',
      );
    });

    test('rejects invalid URLs', () {
      expect(
        () => ImmichClient.normalizeBaseUrl('ftp://host'),
        throwsFormatException,
      );
      expect(
        () => ImmichClient.normalizeBaseUrl('http://host/api?key=1'),
        throwsFormatException,
      );
      expect(
        () => ImmichClient.normalizeBaseUrl('http://host/api#frag'),
        throwsFormatException,
      );
      expect(
        () => ImmichClient.normalizeBaseUrl('not a url'),
        throwsFormatException,
      );
    });

    test('validates server URLs', () {
      expect(ImmichClient.isValidServerUrl('https://photos.example'), isTrue);
      expect(ImmichClient.isValidServerUrl('ftp://photos.example'), isFalse);
    });
  });

  test('sends the api key header only on requests', () async {
    await client().getCurrentUser();

    final request = server.requests.last;
    expect(request.uri.path, '/api/users/me');
    expect(request.header('x-api-key'), 'test-key');
    expect(request.header('authorization'), isNull);
  });

  test('sends the bearer token when no api key is present', () async {
    await client(apiKey: null, accessToken: 'access-token').getCurrentUser();

    final request = server.requests.last;
    expect(request.header('authorization'), 'Bearer access-token');
    expect(request.header('x-api-key'), isNull);
  });

  test('loads albums', () async {
    final albums = await client().getAlbums();

    expect(albums, hasLength(2));
    expect(albums.first.id, 'album-1');
    expect(albums.first.albumName, 'Family');
    expect(albums.first.assetCount, 3);
    expect(albums.first.createdAt, isNotNull);
    expect(albums.last.hasSharedLink, isTrue);
  });

  test('follows nextPage when fetching album assets', () async {
    final assets = await client().getAlbumAssets('album-1', pageSize: 2);

    expect(assets, hasLength(3));
    expect(assets.map((asset) => asset.id), <String>[
      'asset-1',
      'asset-2',
      'asset-3',
    ]);
    expect(assets[0].type, MediaKind.photo);
    expect(assets[1].type, MediaKind.livePhoto);
    expect(assets[2].type, MediaKind.video);
    expect(assets[2].duration, 5000);

    final searches = server.requests
        .where((request) => request.uri.path == '/api/search/metadata')
        .toList();
    expect(searches, hasLength(2));
    expect(searches[0].jsonBody['page'], 1);
    expect(searches[1].jsonBody['page'], 2);
  });

  test('sends the search body and omits empty album ids', () async {
    await client().searchAssets(
      albumIds: <String>['album-1'],
      page: 2,
      size: 5,
      withExif: false,
    );
    var request = server.requests.last;
    expect(request.jsonBody, <String, dynamic>{
      'page': 2,
      'size': 5,
      'withExif': false,
      'albumIds': <String>['album-1'],
    });

    await client().searchAssets(size: 1);
    request = server.requests.last;
    expect(request.jsonBody.containsKey('albumIds'), isFalse);
    expect(request.jsonBody['size'], 1);
    expect(request.jsonBody['withExif'], isTrue);
  });

  test('loads a single asset', () async {
    final asset = await client().getAsset('asset-2');

    expect(asset.id, 'asset-2');
    expect(asset.type, MediaKind.livePhoto);
    expect(asset.livePhotoVideoId, 'live-video-2');
    expect(asset.originalFileName, 'asset-2.jpg');
  });

  test('downloads thumbnail and ranged original bytes', () async {
    final thumbnail = await client().getThumbnailBytes('asset-1');
    expect(thumbnail, isNotEmpty);

    final thumbnailRequest = server.requests.last;
    expect(thumbnailRequest.uri.path, '/api/assets/asset-1/thumbnail');
    expect(thumbnailRequest.uri.queryParameters['size'], 'thumbnail');
    expect(thumbnailRequest.header('x-api-key'), 'test-key');

    final original = await client().getOriginalBytes('asset-1', start: 0, end: 0);
    expect(original, hasLength(1));

    final originalRequest = server.requests.last;
    expect(originalRequest.uri.path, '/api/assets/asset-1/original');
    expect(originalRequest.header('range'), 'bytes=0-0');
  });

  test('maps HTTP errors to failures', () async {
    server.unauthorized = true;
    await expectLater(client().getCurrentUser(), throwsA(failureKind(FailureKind.auth)));

    server.unauthorized = false;
    server.denyAlbum = true;
    await expectLater(client().getAlbums(), throwsA(failureKind(FailureKind.permission)));

    server.denyAlbum = false;
    await expectLater(
      client().getAsset('missing'),
      throwsA(failureKind(FailureKind.notFound)),
    );

    server.serverError = true;
    await expectLater(client().getCurrentUser(), throwsA(failureKind(FailureKind.server)));
  });

  test('maps malformed responses', () async {
    server.malformedJson = true;

    await expectLater(
      client().getVersion(),
      throwsA(failureKind(FailureKind.invalidResponse)),
    );
  });

  test('maps network errors', () async {
    final temporary = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = temporary.port;
    await temporary.close(force: true);

    final offline = ImmichClient(baseUri: Uri.parse('http://127.0.0.1:$port/api'));
    await expectLater(
      offline.getCurrentUser(),
      throwsA(failureKind(FailureKind.network)),
    );
  });
}
