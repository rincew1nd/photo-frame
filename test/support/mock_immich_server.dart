import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class RecordedRequest {
  const RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;

  String? header(String name) => headers[name.toLowerCase()];

  Map<String, dynamic> get jsonBody {
    final decoded = jsonDecode(body);
    return decoded is Map
        ? <String, dynamic>{
            for (final entry in decoded.entries)
              entry.key.toString(): entry.value,
          }
        : <String, dynamic>{};
  }
}

class MockImmichServer {
  MockImmichServer._(this._server);

  final HttpServer _server;
  final List<RecordedRequest> requests = <RecordedRequest>[];

  String token = 'test-key';
  bool denyDownload = false;
  bool denyAlbum = false;
  bool denyApiKey = false;
  bool unauthorized = false;
  bool serverError = false;
  bool malformedJson = false;
  bool emptyLibrary = false;
  int mediaFailuresRemaining = 0;

  Uri get rootUrl => Uri.parse('http://127.0.0.1:${_server.port}');

  Uri get apiUrl => rootUrl.replace(path: '/api');

  static Future<MockImmichServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mock = MockImmichServer._(server);
    mock._listen();
    return mock;
  }

  Future<void> close() => _server.close(force: true);

  void _listen() {
    _server.listen((request) {
      _handle(request).catchError((Object _) async {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } on Object {
          return;
        }
      });
    });
  }

  Future<void> _handle(HttpRequest request) async {
    final headers = <String, String>{};
    request.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(',');
    });
    final body = await utf8.decoder.bind(request).join();
    final recorded = RecordedRequest(
      method: request.method,
      uri: request.uri,
      headers: headers,
      body: body,
    );
    requests.add(recorded);

    final path = request.uri.path;
    final route = path.startsWith('/api') ? path.substring(4) : path;
    final isPublic =
        route == '/server/version' ||
        route == '/server/config' ||
        route == '/oauth/authorize' ||
        route == '/oauth/callback';

    if (malformedJson) {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{');
      await request.response.close();
      return;
    }

    if (!isPublic) {
      if (unauthorized || !_authorized(headers)) {
        await _json(request, <String, dynamic>{
          'message': 'Unauthorized',
        }, status: 401);
        return;
      }
      if (serverError) {
        await _json(request, <String, dynamic>{
          'message': 'Server error',
        }, status: 500);
        return;
      }
    }

    if (request.method == 'GET' && route == '/server/version') {
      await _json(request, <String, dynamic>{
        'major': 3,
        'minor': 3,
        'patch': 5,
      });
      return;
    }

    if (request.method == 'GET' && route == '/server/config') {
      await _json(request, <String, dynamic>{
        'loginPageMessage': '',
        'trashDays': 30,
        'oauth': <String, dynamic>{'enabled': true, 'autoLaunch': false},
      });
      return;
    }

    if (request.method == 'GET' && route == '/users/me') {
      await _json(request, <String, dynamic>{
        'id': 'user-1',
        'email': 'test@example.com',
        'name': 'Test User',
      });
      return;
    }

    if (request.method == 'GET' && route == '/albums') {
      if (denyAlbum) {
        await _json(request, <String, dynamic>{
          'message': 'Forbidden',
        }, status: 403);
        return;
      }
      await _json(request, _albums());
      return;
    }

    if (request.method == 'POST' && route == '/search/metadata') {
      await _json(request, _search(recorded.jsonBody));
      return;
    }

    if (request.method == 'GET' && route.startsWith('/assets/')) {
      await _assetRoute(request, route);
      return;
    }

    if (request.method == 'POST' && route == '/api-keys') {
      if (denyApiKey) {
        await _json(request, <String, dynamic>{
          'message': 'Forbidden',
        }, status: 403);
        return;
      }
      final json = recorded.jsonBody;
      await _json(request, <String, dynamic>{
        'id': 'api-key-1',
        'name': json['name'] ?? 'Photo Frame',
        'permissions': json['permissions'] ?? <String>[],
        'secret': token,
      });
      return;
    }

    if (request.method == 'POST' && route == '/oauth/authorize') {
      final json = recorded.jsonBody;
      final url = rootUrl.replace(
        path: '/oauth/authorize',
        queryParameters: <String, String>{
          'codeChallenge': json['codeChallenge']?.toString() ?? '',
          'state': json['state']?.toString() ?? '',
          'redirectUri': json['redirectUri']?.toString() ?? '',
        },
      );
      await _json(request, <String, dynamic>{'url': url.toString()});
      return;
    }

    if (request.method == 'POST' && route == '/oauth/callback') {
      await _json(request, <String, dynamic>{
        'accessToken': 'oauth-access-token',
        'userId': 'user-1',
        'email': 'test@example.com',
        'name': 'Test User',
      });
      return;
    }

    await _json(request, <String, dynamic>{
      'message': 'Not found',
    }, status: 404);
  }

  bool _authorized(Map<String, String> headers) {
    final key = headers['x-api-key'];
    if (key != null && key == token) {
      return true;
    }
    final authorization = headers['authorization'];
    return authorization != null &&
        authorization.toLowerCase().startsWith('bearer ') &&
        authorization.length > 7;
  }

  Future<void> _assetRoute(HttpRequest request, String route) async {
    final segments = route.split('/');
    if (segments.length < 3) {
      await _json(request, <String, dynamic>{
        'message': 'Not found',
      }, status: 404);
      return;
    }
    final id = segments[2];
    final index = _assetList.indexWhere((asset) => asset['id'] == id);
    // Live Photo motion ids are not in the asset list but still have originals.
    final isOriginal = segments.length == 4 && segments[3] == 'original';
    if (index < 0 && !isOriginal) {
      await _json(request, <String, dynamic>{
        'message': 'Not found',
      }, status: 404);
      return;
    }

    if (segments.length == 3) {
      await _json(request, _assetList[index]);
      return;
    }

    if (segments.length == 4 &&
        (segments[3] == 'thumbnail' || segments[3] == 'original') &&
        mediaFailuresRemaining > 0) {
      mediaFailuresRemaining -= 1;
      await _json(request, <String, dynamic>{
        'message': 'Server error',
      }, status: 500);
      return;
    }

    if (segments.length == 4 && segments[3] == 'thumbnail') {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType('image', 'webp');
      request.response.add(<int>[82, 73, 70, 70, 1, 2, 3, 4]);
      await request.response.close();
      return;
    }

    if (segments.length == 4 && segments[3] == 'original') {
      if (denyDownload) {
        await _json(request, <String, dynamic>{
          'message': 'Forbidden',
        }, status: 403);
        return;
      }
      final bytes = utf8.encode('original-$id');
      final range = request.headers.value('range');
      final match = range == null
          ? null
          : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
      if (match != null) {
        final start = int.parse(match.group(1)!);
        final rawEnd = match.group(2)!;
        final end = rawEnd.isEmpty ? bytes.length - 1 : int.parse(rawEnd);
        final safeEnd = end >= bytes.length ? bytes.length - 1 : end;
        if (start > safeEnd) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          'content-range',
          'bytes $start-$safeEnd/${bytes.length}',
        );
        request.response.add(bytes.sublist(start, safeEnd + 1));
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.binary;
      request.response.add(bytes);
      await request.response.close();
      return;
    }

    await _json(request, <String, dynamic>{
      'message': 'Not found',
    }, status: 404);
  }

  List<Map<String, dynamic>> _albums() {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'album-1',
        'albumName': 'Family',
        'assetCount': 3,
        'createdAt': '2024-01-01T09:00:00.000Z',
        'updatedAt': '2024-01-04T09:00:00.000Z',
        'albumThumbnailAssetId': 'asset-1',
        'shared': false,
        'hasSharedLink': false,
        'startDate': '2024-01-01T00:00:00.000Z',
        'endDate': '2024-01-03T00:00:00.000Z',
      },
      <String, dynamic>{
        'id': 'album-2',
        'albumName': 'Travel',
        'assetCount': 3,
        'createdAt': '2024-02-01T09:00:00.000Z',
        'updatedAt': '2024-02-04T09:00:00.000Z',
        'albumThumbnailAssetId': 'asset-2',
        'shared': true,
        'hasSharedLink': true,
        'startDate': null,
        'endDate': null,
      },
    ];
  }

  List<Map<String, dynamic>> get _assetList => <Map<String, dynamic>>[
    _assetJson(0, 4000, 3000),
    _assetJson(1, 3000, 4000),
    _assetJson(2, 1920, 1080),
  ];

  Map<String, dynamic> _assetJson(int index, int width, int height) {
    final isVideo = index == 2;
    final id = 'asset-${index + 1}';
    final originalBytes = utf8.encode('original-$id');
    return <String, dynamic>{
      'id': id,
      'type': isVideo ? 'VIDEO' : 'IMAGE',
      'originalMimeType': isVideo ? 'video/mp4' : 'image/jpeg',
      'originalFileName': 'asset-${index + 1}.${isVideo ? 'mp4' : 'jpg'}',
      'fileCreatedAt': '2024-01-0${index + 1}T10:00:00.000Z',
      'localDateTime': '2024-01-0${index + 1}T11:00:00.000Z',
      'exifInfo': <String, dynamic>{
        'exifImageWidth': width,
        'exifImageHeight': height,
        'dateTimeOriginal': '2024-01-0${index + 1}T10:00:00.000Z',
        'fileSizeInByte': originalBytes.length,
        'make': 'TestMake',
        'model': 'TestModel',
        'city': 'Testville',
        'country': 'Testland',
        'latitude': 10.5 + index,
        'longitude': 20.5 + index,
      },
      'livePhotoVideoId': index == 1 ? 'live-video-2' : null,
      'duration': isVideo ? 5000 : null,
      'checksum': base64.encode(sha1.convert(originalBytes).bytes),
      'thumbhash': 'thumbhash-${index + 1}',
    };
  }

  Map<String, dynamic> _search(Map<String, dynamic> body) {
    final page = _int(body['page']) ?? 1;
    final size = _int(body['size']) ?? 100;
    final safePage = page < 1 ? 1 : page;
    final safeSize = size < 1 ? 100 : size;
    final all = emptyLibrary ? const <Map<String, dynamic>>[] : _assetList;
    final start = (safePage - 1) * safeSize;
    final rawEnd = start + safeSize;
    final end = rawEnd > all.length ? all.length : rawEnd;
    final items = start >= all.length
        ? const <Map<String, dynamic>>[]
        : all.sublist(start, end);
    final nextPage = end < all.length ? safePage + 1 : null;
    return <String, dynamic>{
      'albums': <dynamic>[],
      'assets': <String, dynamic>{
        'total': all.length,
        'count': items.length,
        'items': items,
        'nextPage': nextPage,
        'nextCursor': null,
      },
    };
  }

  int? _int(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  Future<void> _json(
    HttpRequest request,
    Object? data, {
    int status = 200,
  }) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
    await request.response.close();
  }
}
