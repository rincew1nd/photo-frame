import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:photoframe/core/failures.dart';
import 'package:photoframe/data/immich/models.dart';

class ImmichClient {
  ImmichClient({required this.baseUri, this.apiKey, this.accessToken, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  final Uri baseUri;
  final String? apiKey;
  final String? accessToken;
  final Dio _dio;

  static Uri normalizeBaseUrl(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null) {
      throw const FormatException('Invalid server URL');
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const FormatException('Server URL must use http or https');
    }
    if (uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Invalid server host');
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw const FormatException(
        'Server URL must not contain a query or fragment',
      );
    }

    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.isEmpty) {
      path = '/api';
    } else if (!path.toLowerCase().endsWith('/api')) {
      path = '$path/api';
    }

    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    );
  }

  Map<String, String> authHeaders() => _headers();

  static bool isValidServerUrl(String input) {
    try {
      normalizeBaseUrl(input);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Formats a stored server URL for display by trimming and removing `/api`.
  static String displayUrl(String? url) {
    final text = (url ?? '').trim();
    if (text.toLowerCase().endsWith('/api')) {
      return text.substring(0, text.length - 4);
    }
    return text;
  }

  Future<ImmichServerVersion> getVersion() async {
    final json = await _json('server/version');
    return ImmichServerVersion.fromJson(json);
  }

  Future<ImmichUser> getCurrentUser() async {
    final json = await _json('users/me');
    return ImmichUser.fromJson(json);
  }

  Future<List<ImmichAlbum>> getAlbums() async {
    final data = await _get('albums');
    final list = _asList(data) ?? _asList(_asMap(data)?['albums']);
    if (list == null) {
      throw const AppFailure(FailureKind.invalidResponse, 'Malformed response');
    }
    final albums = <ImmichAlbum>[];
    for (final item in list) {
      final map = _asMap(item);
      if (map != null) {
        albums.add(ImmichAlbum.fromJson(map));
      }
    }
    return albums;
  }

  Future<List<ImmichAsset>> getAlbumAssets(
    String albumId, {
    int pageSize = 100,
  }) {
    return fetchAllAlbumAssets(albumId, pageSize: pageSize);
  }

  Future<List<ImmichAsset>> fetchAllAlbumAssets(
    String albumId, {
    int pageSize = 100,
  }) async {
    final assets = <ImmichAsset>[];
    var page = 1;
    while (true) {
      final result = await searchAssets(
        albumIds: <String>[albumId],
        page: page,
        size: pageSize,
      );
      assets.addAll(result.items);
      final next = result.nextPage;
      if (next == null || next <= page) {
        break;
      }
      page = next;
    }
    return assets;
  }

  Future<ImmichAssetPage> searchAssets({
    List<String> albumIds = const <String>[],
    int page = 1,
    int size = 100,
    bool withExif = true,
  }) async {
    final body = <String, dynamic>{
      'page': page,
      'size': size,
      'withExif': withExif,
    };
    if (albumIds.isNotEmpty) {
      body['albumIds'] = albumIds;
    }

    final data = await _post('search/metadata', body: body);
    final assets = _asMap(_asMap(data)?['assets']);
    final items = _asList(assets?['items']);
    if (assets == null || items == null) {
      throw const AppFailure(FailureKind.invalidResponse, 'Malformed response');
    }

    final parsed = <ImmichAsset>[];
    for (final item in items) {
      final map = _asMap(item);
      if (map != null) {
        parsed.add(ImmichAsset.fromJson(map));
      }
    }

    return ImmichAssetPage(
      items: parsed,
      nextPage: _asInt(assets['nextPage']),
      total: _asInt(assets['total']) ?? parsed.length,
    );
  }

  Future<ImmichAsset> getAsset(String id) async {
    final json = await _json('assets/${Uri.encodeComponent(id)}');
    return ImmichAsset.fromJson(json);
  }

  Future<Uint8List> getThumbnailBytes(String id, {String size = 'thumbnail'}) {
    return _bytes(
      'assets/${Uri.encodeComponent(id)}/thumbnail',
      query: <String, dynamic>{'size': size},
    );
  }

  Future<Uint8List> getOriginalBytes(String id, {int? start, int? end}) {
    final headers = _headers();
    if (start != null || end != null) {
      headers['Range'] = 'bytes=${start ?? 0}-${end ?? ''}';
    }
    return _bytes(
      'assets/${Uri.encodeComponent(id)}/original',
      headers: headers,
    );
  }

  Future<String> createApiKey({
    String name = 'Photo Frame',
    List<ImmichPermission> permissions = ImmichPermission.apiKeyDefaults,
  }) async {
    final json = await _json(
      'api-keys',
      method: 'POST',
      body: <String, dynamic>{
        'name': name,
        'permissions': permissions.map((item) => item.jsonName).toList(),
      },
      preferBearer: true,
    );
    final secret = _asString(json['secret']);
    if (secret == null) {
      throw const AppFailure(FailureKind.invalidResponse, 'Malformed response');
    }
    return secret;
  }

  Future<Uri> startOAuth({
    required String codeChallenge,
    required String redirectUri,
    required String state,
  }) async {
    final json = await _json(
      'oauth/authorize',
      method: 'POST',
      body: <String, dynamic>{
        'codeChallenge': codeChallenge,
        'redirectUri': redirectUri,
        'state': state,
      },
    );
    final url = _asString(json['url']);
    final parsed = url == null ? null : Uri.tryParse(url);
    if (parsed == null) {
      throw const AppFailure(FailureKind.invalidResponse, 'Malformed response');
    }
    return parsed;
  }

  Future<String> completeOAuth({
    required Uri callbackUrl,
    required String codeVerifier,
    required String state,
  }) async {
    final json = await _json(
      'oauth/callback',
      method: 'POST',
      body: <String, dynamic>{
        'url': callbackUrl.toString(),
        'codeVerifier': codeVerifier,
        'state': state,
      },
    );
    final token = _asString(json['accessToken']);
    if (token == null) {
      throw const AppFailure(FailureKind.invalidResponse, 'Malformed response');
    }
    return token;
  }

  Future<PermissionReport> checkPermissions() async {
    final statuses = <ImmichPermission, PermissionStatus>{
      for (final permission in ImmichPermission.values)
        permission: PermissionStatus.notTested,
    };
    AppFailure? blocking;
    ImmichUser? user;

    void failed(ImmichPermission permission, AppFailure failure) {
      statuses[permission] = failure.kind == FailureKind.permission
          ? PermissionStatus.denied
          : PermissionStatus.error;
      if (PermissionReport.blockingPermissions.contains(permission)) {
        blocking ??= failure;
      }
    }

    try {
      user = await getCurrentUser();
      statuses[ImmichPermission.userRead] = PermissionStatus.granted;
    } on AppFailure catch (failure) {
      failed(ImmichPermission.userRead, failure);
    }

    try {
      await getAlbums();
      statuses[ImmichPermission.albumRead] = PermissionStatus.granted;
    } on AppFailure catch (failure) {
      failed(ImmichPermission.albumRead, failure);
    }

    ImmichAsset? first;
    try {
      final page = await searchAssets(size: 1);
      statuses[ImmichPermission.assetRead] = PermissionStatus.granted;
      first = page.items.isEmpty ? null : page.items.first;
    } on AppFailure catch (failure) {
      failed(ImmichPermission.assetRead, failure);
    }

    if (first != null) {
      try {
        await getThumbnailBytes(first.id);
        statuses[ImmichPermission.assetView] = PermissionStatus.granted;
      } on AppFailure catch (failure) {
        failed(ImmichPermission.assetView, failure);
      }

      try {
        await getOriginalBytes(first.id, start: 0, end: 0);
        statuses[ImmichPermission.assetDownload] = PermissionStatus.granted;
      } on AppFailure catch (failure) {
        failed(ImmichPermission.assetDownload, failure);
      }
    }

    return PermissionReport(
      permissions: statuses,
      blockingFailure: blocking,
      checkedAt: DateTime.now(),
      user: user,
    );
  }

  Map<String, String> _headers({bool preferBearer = false}) {
    final headers = <String, String>{};
    final bearer = accessToken;
    final key = apiKey;
    if (preferBearer && bearer != null && bearer.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearer';
    } else if (key != null && key.isNotEmpty) {
      headers['x-api-key'] = key;
    } else if (bearer != null && bearer.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearer';
    }
    return headers;
  }

  Uri _uri(String path) => Uri.parse('$baseUri/$path');
  Uri _uriWithQuery(String path, Map<String, dynamic>? query) {
    final uri = _uri(path);
    if (query == null || query.isEmpty) {
      return uri;
    }
    return uri.replace(
      queryParameters: query.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }

  Future<dynamic> _get(
    String path, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) async {
    final response = await _request<dynamic>(
      () => _dio.getUri<dynamic>(
        _uriWithQuery(path, query),
        options: Options(headers: headers ?? _headers()),
      ),
    );
    return response.data;
  }

  Future<dynamic> _post(String path, {Object? body}) async {
    final response = await _request<dynamic>(
      () => _dio.postUri<dynamic>(
        _uri(path),
        data: body,
        options: Options(headers: _headers()),
      ),
    );
    return response.data;
  }

  Future<Map<String, dynamic>> _json(
    String path, {
    String method = 'GET',
    Object? body,
    bool preferBearer = false,
  }) async {
    final dynamic data;
    if (method == 'POST') {
      final response = await _request<dynamic>(
        () => _dio.postUri<dynamic>(
          _uri(path),
          data: body,
          options: Options(headers: _headers(preferBearer: preferBearer)),
        ),
      );
      data = response.data;
    } else {
      final response = await _request<dynamic>(
        () => _dio.getUri<dynamic>(
          _uri(path),
          options: Options(headers: _headers(preferBearer: preferBearer)),
        ),
      );
      data = response.data;
    }
    final map = _asMap(data);
    if (map == null) {
      throw const AppFailure(FailureKind.invalidResponse, 'Malformed response');
    }
    return map;
  }

  Future<Uint8List> _bytes(
    String path, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) async {
    final response = await _request<List<int>>(
      () => _dio.getUri<List<int>>(
        _uriWithQuery(path, query),
        options: Options(
          headers: headers ?? _headers(),
          responseType: ResponseType.bytes,
        ),
      ),
    );
    final data = response.data;
    if (data == null) {
      throw const AppFailure(FailureKind.invalidResponse, 'Malformed response');
    }
    return Uint8List.fromList(data);
  }

  Future<Response<T>> _request<T>(Future<Response<T>> Function() run) async {
    try {
      return await run();
    } on Object catch (error) {
      throw _mapError(error);
    }
  }

  AppFailure _mapError(Object error) {
    if (error is AppFailure) {
      return error;
    }
    if (error is FormatException) {
      return const AppFailure(
        FailureKind.invalidResponse,
        'Malformed response',
      );
    }
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.transformTimeout:
        case DioExceptionType.connectionError:
          return const AppFailure(FailureKind.network, 'Network unavailable');
        case DioExceptionType.badCertificate:
          return const AppFailure(
            FailureKind.network,
            'Secure connection failed',
          );
        case DioExceptionType.cancel:
          return const AppFailure(FailureKind.unknown, 'Request cancelled');
        case DioExceptionType.badResponse:
          return _statusFailure(statusCode);
        case DioExceptionType.unknown:
          if (error.error is FormatException) {
            return const AppFailure(
              FailureKind.invalidResponse,
              'Malformed response',
            );
          }
          return const AppFailure(
            FailureKind.network,
            'Network request failed',
          );
      }
    }
    return const AppFailure(FailureKind.unknown, 'Request failed');
  }

  AppFailure _statusFailure(int? statusCode) {
    if (statusCode == 401) {
      return AppFailure(
        FailureKind.auth,
        'Authentication failed',
        statusCode: statusCode,
      );
    }
    if (statusCode == 403) {
      return AppFailure(
        FailureKind.permission,
        'Permission denied',
        statusCode: statusCode,
      );
    }
    if (statusCode == 404) {
      return AppFailure(
        FailureKind.notFound,
        'Not found',
        statusCode: statusCode,
      );
    }
    if (statusCode != null && statusCode >= 500) {
      return AppFailure(
        FailureKind.server,
        'Server error',
        statusCode: statusCode,
      );
    }
    return AppFailure(
      FailureKind.invalidResponse,
      'Unexpected response',
      statusCode: statusCode,
    );
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return null;
}

List<dynamic>? _asList(Object? value) {
  return value is List ? value : null;
}

String? _asString(Object? value) {
  return value is String && value.isNotEmpty ? value : null;
}

int? _asInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
