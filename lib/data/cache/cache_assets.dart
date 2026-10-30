import 'package:photoframe/data/settings/app_settings.dart';

class CachedAsset {
  const CachedAsset({
    required this.id,
    this.albumIds = const <String>{},
    this.type = MediaKind.photo,
    this.originalMimeType,
    this.width,
    this.height,
    this.aspectBucket,
    this.duration,
    this.livePhotoVideoId,
    this.exifDate,
    this.description,
    this.location,
    this.tags = const <String>[],
    this.originalPath,
    this.thumbnailPath,
    this.liveVideoPath,
    this.derivedImagePath,
    this.checksum,
    this.sizeBytes = 0,
    this.liveVideoSizeBytes = 0,
    this.derivedImageSizeBytes = 0,
    required this.cachedAt,
    required this.lastAccessedAt,
  });

  final String id;
  final Set<String> albumIds;
  final MediaKind type;
  final String? originalMimeType;
  final int? width;
  final int? height;
  final AspectBucket? aspectBucket;
  final int? duration;
  final String? livePhotoVideoId;
  final DateTime? exifDate;
  final String? description;
  final String? location;
  final List<String> tags;
  final String? originalPath;
  final String? thumbnailPath;
  final String? liveVideoPath;
  final String? derivedImagePath;
  final String? checksum;
  final int sizeBytes;
  final int liveVideoSizeBytes;
  final int derivedImageSizeBytes;
  final DateTime cachedAt;
  final DateTime lastAccessedAt;

  int get totalSizeBytes =>
      sizeBytes + liveVideoSizeBytes + derivedImageSizeBytes;

  static const Set<String> _decodableImageMimeTypes = <String>{
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
    'image/gif',
    'image/bmp',
  };

  bool get hasOriginalFile => originalPath != null && originalPath!.isNotEmpty;

  bool get hasThumbnailFile =>
      thumbnailPath != null && thumbnailPath!.isNotEmpty;

  /// Whether Flutter's built-in codecs can decode the cached original.
  bool get isDecodableImage =>
      _decodableImageMimeTypes.contains((originalMimeType ?? '').toLowerCase());

  CachedAsset copyWith({
    String? id,
    Set<String>? albumIds,
    MediaKind? type,
    String? originalMimeType,
    int? width,
    int? height,
    AspectBucket? aspectBucket,
    int? duration,
    String? livePhotoVideoId,
    DateTime? exifDate,
    String? description,
    String? location,
    List<String>? tags,
    String? originalPath,
    String? thumbnailPath,
    String? liveVideoPath,
    String? derivedImagePath,
    String? checksum,
    int? sizeBytes,
    int? liveVideoSizeBytes,
    int? derivedImageSizeBytes,
    DateTime? cachedAt,
    DateTime? lastAccessedAt,
  }) {
    return CachedAsset(
      id: id ?? this.id,
      albumIds: albumIds ?? this.albumIds,
      type: type ?? this.type,
      originalMimeType: originalMimeType ?? this.originalMimeType,
      width: width ?? this.width,
      height: height ?? this.height,
      aspectBucket: aspectBucket ?? this.aspectBucket,
      duration: duration ?? this.duration,
      livePhotoVideoId: livePhotoVideoId ?? this.livePhotoVideoId,
      exifDate: exifDate ?? this.exifDate,
      description: description ?? this.description,
      location: location ?? this.location,
      tags: tags ?? this.tags,
      originalPath: originalPath ?? this.originalPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      liveVideoPath: liveVideoPath ?? this.liveVideoPath,
      derivedImagePath: derivedImagePath ?? this.derivedImagePath,
      checksum: checksum ?? this.checksum,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      liveVideoSizeBytes: liveVideoSizeBytes ?? this.liveVideoSizeBytes,
      derivedImageSizeBytes:
          derivedImageSizeBytes ?? this.derivedImageSizeBytes,
      cachedAt: cachedAt ?? this.cachedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'albumIds': albumIds.toList(),
    'type': type.name,
    'originalMimeType': originalMimeType,
    'width': width,
    'height': height,
    'aspectBucket': aspectBucket?.name,
    'duration': duration,
    'livePhotoVideoId': livePhotoVideoId,
    'exifDate': exifDate?.millisecondsSinceEpoch,
    'description': description,
    'location': location,
    'tags': tags,
    'originalPath': originalPath,
    'thumbnailPath': thumbnailPath,
    'liveVideoPath': liveVideoPath,
    'derivedImagePath': derivedImagePath,
    'checksum': checksum,
    'sizeBytes': sizeBytes,
    'liveVideoSizeBytes': liveVideoSizeBytes,
    'derivedImageSizeBytes': derivedImageSizeBytes,
    'cachedAt': cachedAt.millisecondsSinceEpoch,
    'lastAccessedAt': lastAccessedAt.millisecondsSinceEpoch,
  };

  factory CachedAsset.fromJson(Map<String, dynamic> json) {
    return CachedAsset(
      id: _asString(json['id']) ?? '',
      albumIds: _asStrings(json['albumIds']).toSet(),
      type: MediaKind.fromJson(json['type']) ?? MediaKind.photo,
      originalMimeType: _asString(json['originalMimeType']),
      width: _asInt(json['width']),
      height: _asInt(json['height']),
      aspectBucket: AspectBucket.fromJson(json['aspectBucket']),
      duration: _asInt(json['duration']),
      livePhotoVideoId: _asString(json['livePhotoVideoId']),
      exifDate: _asDate(json['exifDate']),
      description: _asString(json['description']),
      location: _asString(json['location']),
      tags: _asStrings(json['tags']),
      originalPath: _asString(json['originalPath']),
      thumbnailPath: _asString(json['thumbnailPath']),
      liveVideoPath: _asString(json['liveVideoPath']),
      derivedImagePath: _asString(json['derivedImagePath']),
      checksum: _asString(json['checksum']),
      sizeBytes: _asInt(json['sizeBytes']) ?? 0,
      liveVideoSizeBytes: _asInt(json['liveVideoSizeBytes']) ?? 0,
      derivedImageSizeBytes: _asInt(json['derivedImageSizeBytes']) ?? 0,
      cachedAt:
          _asDate(json['cachedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastAccessedAt:
          _asDate(json['lastAccessedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class CacheStats {
  const CacheStats({
    this.assetCount = 0,
    this.originalBytes = 0,
    this.thumbnailBytes = 0,
    this.liveVideoBytes = 0,
    this.derivedImageBytes = 0,
    int? totalBytes,
    this.albumCount = 0,
    this.imageCount = 0,
    this.imageBytes = 0,
    this.videoCount = 0,
    this.videoBytes = 0,
    this.lastSync,
  }) : _totalBytes = totalBytes;

  final int assetCount;
  final int originalBytes;
  final int thumbnailBytes;
  final int liveVideoBytes;
  final int derivedImageBytes;
  final int? _totalBytes;
  final int albumCount;
  final int imageCount;
  final int imageBytes;
  final int videoCount;
  final int videoBytes;
  final DateTime? lastSync;

  int get totalBytes =>
      _totalBytes ??
      originalBytes + thumbnailBytes + liveVideoBytes + derivedImageBytes;
}

class CacheSyncState {
  const CacheSyncState({
    required this.albumId,
    this.lastSync,
    this.assetCount = 0,
  });

  final String albumId;
  final DateTime? lastSync;
  final int assetCount;
}

List<String> _asStrings(Object? value) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return const <String>[];
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

DateTime? _asDate(Object? value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}
