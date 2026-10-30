import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:photoframe/core/clock.dart';
import 'package:photoframe/core/failures.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/immich/immich_client.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/platform/paths.dart';

const List<int> _retryDelaysMillis = <int>[100, 300, 900];

class MediaDownloader {
  MediaDownloader({required Dio dio, required AppPaths paths, Clock? clock})
    : _dio = dio,
      _paths = paths,
      _clock = clock ?? const SystemClock();

  final Dio _dio;
  final AppPaths _paths;
  final Clock _clock;

  AppPaths get paths => _paths;

  static String originalPath(
    Directory cacheRoot, {
    required String albumId,
    required String assetId,
    String? mimeType,
  }) {
    return cacheFilePath(
      cacheRoot,
      category: 'originals/${sanitizePathSegment(albumId)}',
      assetId: assetId,
      mimeType: mimeType,
    );
  }

  static String thumbnailPath(Directory cacheRoot, {required String assetId}) {
    return cacheFilePath(
      cacheRoot,
      category: 'thumbnails',
      assetId: assetId,
      mimeType: 'image/jpeg',
      variant: '.preview',
    );
  }

  static String liveVideoPath(
    Directory cacheRoot, {
    required String liveVideoId,
  }) {
    return cacheFilePath(
      cacheRoot,
      category: 'live',
      assetId: liveVideoId,
      mimeType: 'video/quicktime',
    );
  }

  Future<CachedAsset> ensureAsset(
    ImmichClient client,
    ImmichAsset asset, {
    required String albumId,
    bool includeOriginal = true,
  }) async {
    final thumbnail = await ensureThumbnail(client, asset);
    File? original;
    if (includeOriginal) {
      original = await ensureOriginal(client, asset, albumId: albumId);
    }
    File? liveVideo;
    final liveVideoId = asset.livePhotoVideoId;
    if (asset.type == MediaKind.livePhoto && liveVideoId != null) {
      liveVideo = await ensureLiveVideo(client, liveVideoId);
    }
    final now = _clock.now();
    return CachedAsset(
      id: asset.id,
      albumIds: <String>{albumId},
      type: asset.type,
      originalMimeType: asset.originalMimeType,
      width: asset.width,
      height: asset.height,
      aspectBucket: asset.aspectBucket,
      duration: asset.duration,
      livePhotoVideoId: asset.livePhotoVideoId,
      exifDate:
          asset.exif?.dateTimeOriginal ??
          asset.localDateTime ??
          asset.fileCreatedAt,
      description: asset.exif?.description,
      location: _location(asset.exif ?? const ImmichExif()),
      tags: const <String>[],
      originalPath: original?.path,
      thumbnailPath: thumbnail?.path,
      liveVideoPath: liveVideo?.path,
      checksum: asset.checksum,
      sizeBytes: original == null ? 0 : await original.length(),
      liveVideoSizeBytes: liveVideo == null ? 0 : await liveVideo.length(),
      cachedAt: now,
      lastAccessedAt: now,
    );
  }

  Future<File?> ensureThumbnail(ImmichClient client, ImmichAsset asset) async {
    final cache = await _paths.cache();
    final destination = File(thumbnailPath(cache, assetId: asset.id));
    if (await _isUsable(destination, null, null)) {
      return destination;
    }
    final uri = Uri.parse(
      '${client.baseUri}/assets/${Uri.encodeComponent(asset.id)}/thumbnail',
    ).replace(queryParameters: <String, String>{'size': 'preview'});
    await downloadToFile(
      uri: uri,
      headers: client.authHeaders(),
      destination: destination,
    );
    return destination;
  }

  Future<File?> ensureOriginal(
    ImmichClient client,
    ImmichAsset asset, {
    required String albumId,
  }) async {
    final cache = await _paths.cache();
    final destination = File(
      originalPath(
        cache,
        albumId: albumId,
        assetId: asset.id,
        mimeType: asset.originalMimeType,
      ),
    );
    if (await _isUsable(
      destination,
      asset.checksum,
      asset.exif?.fileSizeInByte,
    )) {
      return destination;
    }
    final uri = Uri.parse(
      '${client.baseUri}/assets/${Uri.encodeComponent(asset.id)}/original',
    );
    await downloadToFile(
      uri: uri,
      headers: client.authHeaders(),
      destination: destination,
      expectedChecksum: asset.checksum,
    );
    return destination;
  }

  Future<File?> ensureLiveVideo(ImmichClient client, String liveVideoId) async {
    final cache = await _paths.cache();
    final destination = File(liveVideoPath(cache, liveVideoId: liveVideoId));
    if (await _isUsable(destination, null, null)) {
      return destination;
    }
    final uri = Uri.parse(
      '${client.baseUri}/assets/${Uri.encodeComponent(liveVideoId)}/original',
    );
    await downloadToFile(
      uri: uri,
      headers: client.authHeaders(),
      destination: destination,
    );
    return destination;
  }

  Future<void> downloadToFile({
    required Uri uri,
    required Map<String, String> headers,
    required File destination,
    String? expectedChecksum,
    int attempts = 3,
  }) async {
    final parent = destination.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final part = File('${destination.path}.part');
    final safeAttempts = attempts < 1 ? 1 : attempts;
    Object? lastError;

    for (var attempt = 0; attempt < safeAttempts; attempt++) {
      try {
        var existing = 0;
        if (await part.exists()) {
          existing = await part.length();
        }
        final requestHeaders = Map<String, String>.from(headers);
        if (existing > 0) {
          requestHeaders['Range'] = 'bytes=$existing-';
        }
        final response = await _dio.getUri<ResponseBody>(
          uri,
          options: Options(
            responseType: ResponseType.stream,
            headers: requestHeaders,
            validateStatus: (status) =>
                status != null && (status == 200 || status == 206),
          ),
        );
        final body = response.data;
        if (body == null) {
          throw const AppFailure(FailureKind.invalidResponse, 'Empty download');
        }
        final append = response.statusCode == 206 && existing > 0;
        final sink = part.openWrite(
          mode: append ? FileMode.append : FileMode.write,
        );
        try {
          await sink.addStream(body.stream);
          await sink.flush();
        } finally {
          await sink.close();
        }

        if (expectedChecksum != null && expectedChecksum.isNotEmpty) {
          final actual = await _sha1Base64(part);
          if (actual != expectedChecksum) {
            if (await part.exists()) {
              await part.delete();
            }
            if (attempt + 1 >= safeAttempts) {
              throw const AppFailure(
                FailureKind.invalidResponse,
                'Checksum mismatch',
              );
            }
            await Future<void>.delayed(_backoff(attempt));
            continue;
          }
        }

        if (await destination.exists()) {
          await destination.delete();
        }
        await part.rename(destination.path);
        return;
      } on Object catch (error) {
        lastError = error;
        if (!_isRetryable(error) || attempt + 1 >= safeAttempts) {
          throw _mapError(error);
        }
        await Future<void>.delayed(_backoff(attempt));
      }
    }

    throw _mapError(
      lastError ?? const AppFailure(FailureKind.storage, 'Download failed'),
    );
  }

  Future<bool> _isUsable(File file, String? checksum, int? expectedSize) async {
    if (!await file.exists()) {
      return false;
    }
    final length = await file.length();
    if (length <= 0) {
      return false;
    }
    if (expectedSize != null && expectedSize > 0 && length != expectedSize) {
      return false;
    }
    if (checksum != null && checksum.isNotEmpty) {
      return await _sha1Base64(file) == checksum;
    }
    return true;
  }

  Future<String> _sha1Base64(File file) async {
    final digest = await sha1.bind(file.openRead()).first;
    return base64.encode(digest.bytes);
  }

  Duration _backoff(int attempt) {
    final index = attempt < _retryDelaysMillis.length
        ? attempt
        : _retryDelaysMillis.length - 1;
    return Duration(milliseconds: _retryDelaysMillis[index]);
  }

  bool _isRetryable(Object error) {
    if (error is AppFailure) {
      return error.kind == FailureKind.network ||
          error.kind == FailureKind.server;
    }
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status != null) {
        return status >= 500;
      }
      return error.type != DioExceptionType.cancel &&
          error.type != DioExceptionType.badCertificate;
    }
    return error is SocketException ||
        error is TimeoutException ||
        error is HttpException;
  }

  AppFailure _mapError(Object error) {
    if (error is AppFailure) {
      return error;
    }
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 401) {
        return AppFailure(
          FailureKind.auth,
          'Authentication failed',
          statusCode: status,
          cause: error,
        );
      }
      if (status == 403) {
        return AppFailure(
          FailureKind.permission,
          'Permission denied',
          statusCode: status,
          cause: error,
        );
      }
      if (status == 404) {
        return AppFailure(
          FailureKind.notFound,
          'Not found',
          statusCode: status,
          cause: error,
        );
      }
      if (status != null && status >= 500) {
        return AppFailure(
          FailureKind.server,
          'Server error',
          statusCode: status,
          cause: error,
        );
      }
      if (status != null) {
        return AppFailure(
          FailureKind.invalidResponse,
          'Download failed',
          statusCode: status,
          cause: error,
        );
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.transformTimeout ||
          error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.unknown) {
        return AppFailure(
          FailureKind.network,
          'Network unavailable',
          cause: error,
        );
      }
      return AppFailure(
        FailureKind.invalidResponse,
        'Download failed',
        cause: error,
      );
    }
    if (error is SocketException || error is TimeoutException) {
      return AppFailure(
        FailureKind.network,
        'Network unavailable',
        cause: error,
      );
    }
    if (error is FileSystemException) {
      return AppFailure(
        FailureKind.storage,
        'Storage write failed',
        cause: error,
      );
    }
    return AppFailure(FailureKind.storage, 'Download failed', cause: error);
  }

  String? _location(ImmichExif exif) {
    final parts = <String?>[
      exif.city,
      exif.state,
      exif.country,
    ].whereType<String>().where((value) => value.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }
}
