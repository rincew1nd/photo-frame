import 'package:photoframe/core/failures.dart';
import 'package:photoframe/data/settings/app_settings.dart';

enum ImmichPermission {
  userRead('user.read'),
  albumRead('album.read'),
  assetRead('asset.read'),
  assetView('asset.view'),
  assetDownload('asset.download'),
  apiKeyCreate('apiKey.create');

  const ImmichPermission(this.jsonName);

  final String jsonName;

  static const List<ImmichPermission> apiKeyDefaults = <ImmichPermission>[
    userRead,
    albumRead,
    assetRead,
    assetView,
    assetDownload,
  ];

  static ImmichPermission? fromJson(Object? value) {
    if (value is String) {
      for (final permission in ImmichPermission.values) {
        if (permission.jsonName == value || permission.name == value) {
          return permission;
        }
      }
    }
    return null;
  }
}

enum PermissionStatus {
  granted,
  denied,
  notTested,
  error;

  static PermissionStatus fromJson(Object? value) {
    if (value is String) {
      for (final status in PermissionStatus.values) {
        if (status.name == value) {
          return status;
        }
      }
    }
    return PermissionStatus.notTested;
  }
}

class ImmichServerVersion {
  const ImmichServerVersion({
    this.major = 0,
    this.minor = 0,
    this.patch = 0,
  });

  final int major;
  final int minor;
  final int patch;

  factory ImmichServerVersion.fromJson(Map<String, dynamic> json) {
    return ImmichServerVersion(
      major: _asInt(json['major']) ?? 0,
      minor: _asInt(json['minor']) ?? 0,
      patch: _asInt(json['patch']) ?? 0,
    );
  }

  @override
  String toString() => '$major.$minor.$patch';
}

class ImmichUser {
  const ImmichUser({
    required this.id,
    this.email = '',
    this.name = '',
  });

  final String id;
  final String email;
  final String name;

  factory ImmichUser.fromJson(Map<String, dynamic> json) {
    return ImmichUser(
      id: _asString(json['id']) ?? '',
      email: _asString(json['email']) ?? '',
      name: _asString(json['name']) ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'email': email,
    'name': name,
  };
}

class ImmichAlbum {
  const ImmichAlbum({
    required this.id,
    this.albumName = '',
    this.assetCount = 0,
    this.createdAt,
    this.updatedAt,
    this.albumThumbnailAssetId,
    this.shared = false,
    this.hasSharedLink = false,
    this.startDate,
    this.endDate,
  });

  final String id;
  final String albumName;
  final int assetCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? albumThumbnailAssetId;
  final bool shared;
  final bool hasSharedLink;
  final DateTime? startDate;
  final DateTime? endDate;

  factory ImmichAlbum.fromJson(Map<String, dynamic> json) {
    return ImmichAlbum(
      id: _asString(json['id']) ?? '',
      albumName: _asString(json['albumName']) ?? '',
      assetCount: _asInt(json['assetCount']) ?? 0,
      createdAt: _asDate(json['createdAt']),
      updatedAt: _asDate(json['updatedAt']),
      albumThumbnailAssetId: _asString(json['albumThumbnailAssetId']),
      shared: _asBool(json['shared']) ?? false,
      hasSharedLink: _asBool(json['hasSharedLink']) ?? false,
      startDate: _asDate(json['startDate']),
      endDate: _asDate(json['endDate']),
    );
  }
}

class ImmichExif {
  const ImmichExif({
    this.width,
    this.height,
    this.dateTimeOriginal,
    this.description,
    this.city,
    this.state,
    this.country,
    this.latitude,
    this.longitude,
    this.make,
    this.model,
    this.lensModel,
    this.fileSizeInByte,
  });

  final int? width;
  final int? height;
  final DateTime? dateTimeOriginal;
  final String? description;
  final String? city;
  final String? state;
  final String? country;
  final double? latitude;
  final double? longitude;
  final String? make;
  final String? model;
  final String? lensModel;
  final int? fileSizeInByte;

  factory ImmichExif.fromJson(Map<String, dynamic> json) {
    return ImmichExif(
      width: _asInt(json['exifImageWidth']),
      height: _asInt(json['exifImageHeight']),
      dateTimeOriginal: _asDate(json['dateTimeOriginal']),
      description: _asString(json['description']),
      city: _asString(json['city']),
      state: _asString(json['state']),
      country: _asString(json['country']),
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      make: _asString(json['make']),
      model: _asString(json['model']),
      lensModel: _asString(json['lensModel']),
      fileSizeInByte: _asInt(json['fileSizeInByte']),
    );
  }
}

class ImmichAsset {
  const ImmichAsset({
    required this.id,
    this.type = MediaKind.photo,
    this.originalMimeType = '',
    this.originalFileName = '',
    this.fileCreatedAt,
    this.localDateTime,
    this.exif,
    this.livePhotoVideoId,
    this.duration,
    this.checksum,
    this.thumbhash,
    this.aspectBucket,
  });

  final String id;
  final MediaKind type;
  final String originalMimeType;
  final String originalFileName;
  final DateTime? fileCreatedAt;
  final DateTime? localDateTime;
  final ImmichExif? exif;
  final String? livePhotoVideoId;
  final int? duration;
  final String? checksum;
  final String? thumbhash;
  final AspectBucket? aspectBucket;

  int? get width => exif?.width;
  int? get height => exif?.height;

  factory ImmichAsset.fromJson(Map<String, dynamic> json) {
    final exif = ImmichExif.fromJson(_asMap(json['exifInfo']) ?? const {});
    final livePhotoVideoId = _asString(json['livePhotoVideoId']);
    final rawType = (_asString(json['type']) ?? '').toUpperCase();
    final mimeType = (_asString(json['originalMimeType']) ?? '').toLowerCase();

    final MediaKind type;
    if (rawType == 'VIDEO' || mimeType.startsWith('video/')) {
      type = MediaKind.video;
    } else if (livePhotoVideoId != null || rawType.contains('LIVE')) {
      type = MediaKind.livePhoto;
    } else {
      type = MediaKind.photo;
    }

    return ImmichAsset(
      id: _asString(json['id']) ?? '',
      type: type,
      originalMimeType: _asString(json['originalMimeType']) ?? '',
      originalFileName: _asString(json['originalFileName']) ?? '',
      fileCreatedAt: _asDate(json['fileCreatedAt']),
      localDateTime: _asDate(json['localDateTime']),
      exif: exif,
      livePhotoVideoId: livePhotoVideoId,
      duration: _asInt(json['duration']),
      checksum: _asString(json['checksum']),
      thumbhash: _asString(json['thumbhash']),
      aspectBucket: aspectBucketFor(exif.width, exif.height),
    );
  }
}

class ImmichAssetPage {
  const ImmichAssetPage({
    this.items = const <ImmichAsset>[],
    this.nextPage,
    this.total = 0,
  });

  final List<ImmichAsset> items;
  final int? nextPage;
  final int total;
}

class ImmichAuthSession {
  const ImmichAuthSession({
    this.apiKey,
    this.accessToken,
    this.authMode = AuthMode.oauth,
  });

  final String? apiKey;
  final String? accessToken;
  final AuthMode authMode;
}

class PermissionReport {
  const PermissionReport({
    required this.permissions,
    required this.checkedAt,
    this.blockingFailure,
    this.user,
  });

  static const List<ImmichPermission> blockingPermissions = <ImmichPermission>[
    ImmichPermission.userRead,
    ImmichPermission.albumRead,
    ImmichPermission.assetRead,
    ImmichPermission.assetView,
  ];

  final Map<ImmichPermission, PermissionStatus> permissions;
  final AppFailure? blockingFailure;
  final DateTime checkedAt;
  final ImmichUser? user;

  PermissionStatus statusOf(ImmichPermission permission) {
    return permissions[permission] ?? PermissionStatus.notTested;
  }

  bool get canConnect {
    for (final permission in blockingPermissions) {
      final status = statusOf(permission);
      if (status == PermissionStatus.denied || status == PermissionStatus.error) {
        return false;
      }
    }
    return true;
  }

  bool get downloadAllowed {
    return statusOf(ImmichPermission.assetDownload) == PermissionStatus.granted;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'permissions': <String, dynamic>{
      for (final entry in permissions.entries)
        entry.key.jsonName: entry.value.name,
    },
    'blockingFailure': blockingFailure == null
        ? null
        : <String, dynamic>{
            'kind': blockingFailure!.kind.name,
            'message': blockingFailure!.message,
            'statusCode': blockingFailure!.statusCode,
          },
    'checkedAt': checkedAt.toIso8601String(),
    'user': user?.toJson(),
  };

  factory PermissionReport.fromJson(Map<String, dynamic> json) {
    final permissions = <ImmichPermission, PermissionStatus>{};
    final rawPermissions = _asMap(json['permissions']) ?? const {};
    for (final entry in rawPermissions.entries) {
      final permission = ImmichPermission.fromJson(entry.key);
      if (permission != null) {
        permissions[permission] = PermissionStatus.fromJson(entry.value);
      }
    }

    AppFailure? blockingFailure;
    final rawFailure = _asMap(json['blockingFailure']);
    if (rawFailure != null) {
      blockingFailure = AppFailure(
        _failureKind(rawFailure['kind']),
        _asString(rawFailure['message']) ?? 'Request failed',
        statusCode: _asInt(rawFailure['statusCode']),
      );
    }

    final rawUser = _asMap(json['user']);

    return PermissionReport(
      permissions: permissions,
      blockingFailure: blockingFailure,
      checkedAt: _asDate(json['checkedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      user: rawUser == null ? null : ImmichUser.fromJson(rawUser),
    );
  }
}

const double _aspectTolerance = 0.05;

const List<(AspectBucket, double)> _namedAspects = <(AspectBucket, double)>[
  (AspectBucket.oneToOne, 1.0),
  (AspectBucket.fourThree, 4 / 3),
  (AspectBucket.threeTwo, 1.5),
  (AspectBucket.sixteenNine, 16 / 9),
];

AspectBucket? aspectBucketFor(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  final long = width >= height ? width : height;
  final short = width >= height ? height : width;
  final ratio = long / short;
  if (ratio >= 2.0) {
    return AspectBucket.panorama;
  }
  AspectBucket nearest = AspectBucket.oneToOne;
  var nearestError = double.infinity;
  for (final (bucket, target) in _namedAspects) {
    final error = (ratio / target - 1).abs();
    if (error <= _aspectTolerance) {
      return bucket;
    }
    if (error < nearestError) {
      nearestError = error;
      nearest = bucket;
    }
  }
  return nearest;
}

FailureKind _failureKind(Object? value) {
  if (value is String) {
    for (final kind in FailureKind.values) {
      if (kind.name == value) {
        return kind;
      }
    }
  }
  return FailureKind.unknown;
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return null;
}

String? _asString(Object? value) {
  return value is String && value.isNotEmpty ? value : null;
}

bool? _asBool(Object? value) => value is bool ? value : null;

int? _asInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

double? _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

DateTime? _asDate(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  return null;
}
