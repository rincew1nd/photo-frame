import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:photoframe/data/cache/app_database.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/settings/app_settings.dart';

abstract class CacheStore {
  Future<void> init();

  Future<void> upsertAsset(CachedAsset asset);

  Future<CachedAsset?> getAsset(String id);

  Future<List<CachedAsset>> getAssetsForAlbums(Set<String> albumIds);

  Future<List<CachedAsset>> allAssets();

  Future<void> deleteAsset(String id);

  Future<void> setSyncState(CacheSyncState state);

  Future<CacheSyncState?> getSyncState(String albumId);

  Future<CacheStats> stats();

  Future<void> clear();

  Future<void> touchAsset(String id, DateTime lastAccessedAt);
}

class MemoryCacheStore implements CacheStore {
  final Map<String, CachedAsset> _assets = <String, CachedAsset>{};
  final Map<String, CacheSyncState> _syncStates = <String, CacheSyncState>{};

  @override
  Future<void> init() async {}

  @override
  Future<void> upsertAsset(CachedAsset asset) async {
    _assets[asset.id] = asset;
  }

  @override
  Future<CachedAsset?> getAsset(String id) async => _assets[id];

  @override
  Future<List<CachedAsset>> getAssetsForAlbums(Set<String> albumIds) async {
    if (albumIds.isEmpty) {
      return <CachedAsset>[];
    }
    return _assets.values
        .where((asset) => asset.albumIds.any(albumIds.contains))
        .toList();
  }

  @override
  Future<List<CachedAsset>> allAssets() async => _assets.values.toList();

  @override
  Future<void> deleteAsset(String id) async {
    _assets.remove(id);
  }

  @override
  Future<void> setSyncState(CacheSyncState state) async {
    _syncStates[state.albumId] = state;
  }

  @override
  Future<CacheSyncState?> getSyncState(String albumId) async {
    return _syncStates[albumId];
  }

  @override
  Future<CacheStats> stats() async {
    final assets = _assets.values.toList();
    final albums = <String>{for (final asset in assets) ...asset.albumIds};
    DateTime? lastSync;
    for (final state in _syncStates.values) {
      final value = state.lastSync;
      if (value != null && (lastSync == null || value.isAfter(lastSync))) {
        lastSync = value;
      }
    }
    return _statsFor(assets, albumCount: albums.length, lastSync: lastSync);
  }

  @override
  Future<void> clear() async {
    _assets.clear();
    _syncStates.clear();
  }

  @override
  Future<void> touchAsset(String id, DateTime lastAccessedAt) async {
    final asset = _assets[id];
    if (asset != null) {
      _assets[id] = asset.copyWith(lastAccessedAt: lastAccessedAt);
    }
  }
}

class DriftCacheStore implements CacheStore {
  DriftCacheStore(this._db);

  final AppDatabase _db;
  bool _initialized = false;

  static const List<String> _columns = <String>[
    'id',
    'album_ids',
    'media_kind',
    'mime',
    'width',
    'height',
    'aspect',
    'duration',
    'live_video_id',
    'exif_date',
    'description',
    'location',
    'tags',
    'original_path',
    'thumbnail_path',
    'live_video_path',
    'derived_image_path',
    'checksum',
    'size_bytes',
    'live_video_size_bytes',
    'derived_image_size_bytes',
    'cached_at',
    'last_accessed',
  ];

  @override
  Future<void> init() async {
    if (_initialized) {
      return;
    }
    await _db.migrate();
    _initialized = true;
  }

  Future<void> _ready() async {
    if (!_initialized) {
      await init();
    }
  }

  @override
  Future<void> upsertAsset(CachedAsset asset) async {
    await _ready();
    final placeholders = List<String>.filled(_columns.length, '?').join(', ');
    await _db.customInsert(
      'INSERT OR REPLACE INTO cached_assets (${_columns.join(', ')}) '
      'VALUES ($placeholders)',
      variables: <Variable>[
        Variable.withString(asset.id),
        Variable.withString(jsonEncode(asset.albumIds.toList())),
        Variable.withString(asset.type.name),
        Variable<String>(asset.originalMimeType),
        Variable<int>(asset.width),
        Variable<int>(asset.height),
        Variable<String>(asset.aspectBucket?.name),
        Variable<int>(asset.duration),
        Variable<String>(asset.livePhotoVideoId),
        Variable<String>(asset.exifDate?.toIso8601String()),
        Variable<String>(asset.description),
        Variable<String>(asset.location),
        Variable.withString(jsonEncode(asset.tags)),
        Variable<String>(asset.originalPath),
        Variable<String>(asset.thumbnailPath),
        Variable<String>(asset.liveVideoPath),
        Variable<String>(asset.derivedImagePath),
        Variable<String>(asset.checksum),
        Variable.withInt(asset.sizeBytes),
        Variable.withInt(asset.liveVideoSizeBytes),
        Variable.withInt(asset.derivedImageSizeBytes),
        Variable.withInt(asset.cachedAt.millisecondsSinceEpoch),
        Variable.withInt(asset.lastAccessedAt.millisecondsSinceEpoch),
      ],
    );
  }

  @override
  Future<CachedAsset?> getAsset(String id) async {
    await _ready();
    final rows = await _db
        .customSelect(
          'SELECT * FROM cached_assets WHERE id = ? LIMIT 1',
          variables: <Variable>[Variable.withString(id)],
        )
        .get();
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<List<CachedAsset>> getAssetsForAlbums(Set<String> albumIds) async {
    if (albumIds.isEmpty) {
      return <CachedAsset>[];
    }
    final assets = await allAssets();
    return assets
        .where((asset) => asset.albumIds.any(albumIds.contains))
        .toList();
  }

  @override
  Future<List<CachedAsset>> allAssets() async {
    await _ready();
    final rows = await _db.customSelect('SELECT * FROM cached_assets').get();
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> deleteAsset(String id) async {
    await _ready();
    await _db.customStatement(
      'DELETE FROM cached_assets WHERE id = ?',
      <Object?>[id],
    );
  }

  @override
  Future<void> setSyncState(CacheSyncState state) async {
    await _ready();
    await _db.customInsert(
      'INSERT OR REPLACE INTO album_sync_states '
      '(album_id, last_sync, asset_count) VALUES (?, ?, ?)',
      variables: <Variable>[
        Variable.withString(state.albumId),
        Variable<int>(state.lastSync?.millisecondsSinceEpoch),
        Variable.withInt(state.assetCount),
      ],
    );
  }

  @override
  Future<CacheSyncState?> getSyncState(String albumId) async {
    await _ready();
    final rows = await _db
        .customSelect(
          'SELECT * FROM album_sync_states WHERE album_id = ? LIMIT 1',
          variables: <Variable>[Variable.withString(albumId)],
        )
        .get();
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return CacheSyncState(
      albumId: row.read<String>('album_id'),
      lastSync: _fromMillis(row.readNullable<int>('last_sync')),
      assetCount: row.readNullable<int>('asset_count') ?? 0,
    );
  }

  @override
  Future<CacheStats> stats() async {
    await _ready();
    final assets = await allAssets();
    final albums = <String>{for (final asset in assets) ...asset.albumIds};
    final rows = await _db
        .customSelect(
          'SELECT MAX(last_sync) AS last_sync FROM album_sync_states',
        )
        .get();
    final lastSync = rows.isEmpty
        ? null
        : _fromMillis(rows.first.readNullable<int>('last_sync'));
    return _statsFor(assets, albumCount: albums.length, lastSync: lastSync);
  }

  @override
  Future<void> clear() async {
    await _ready();
    await _db.customStatement('DELETE FROM cached_assets');
    await _db.customStatement('DELETE FROM album_sync_states');
  }

  @override
  Future<void> touchAsset(String id, DateTime lastAccessedAt) async {
    await _ready();
    await _db.customStatement(
      'UPDATE cached_assets SET last_accessed = ? WHERE id = ?',
      <Object?>[lastAccessedAt.millisecondsSinceEpoch, id],
    );
  }

  CachedAsset _fromRow(QueryRow row) {
    return CachedAsset(
      id: row.read<String>('id'),
      albumIds: _decodeStrings(row.readNullable<String>('album_ids')).toSet(),
      type:
          MediaKind.fromJson(row.readNullable<String>('media_kind')) ??
          MediaKind.photo,
      originalMimeType: row.readNullable<String>('mime'),
      width: row.readNullable<int>('width'),
      height: row.readNullable<int>('height'),
      aspectBucket: AspectBucket.fromJson(row.readNullable<String>('aspect')),
      duration: row.readNullable<int>('duration'),
      livePhotoVideoId: row.readNullable<String>('live_video_id'),
      exifDate: _parseDate(row.readNullable<String>('exif_date')),
      description: row.readNullable<String>('description'),
      location: row.readNullable<String>('location'),
      tags: _decodeStrings(row.readNullable<String>('tags')),
      originalPath: row.readNullable<String>('original_path'),
      thumbnailPath: row.readNullable<String>('thumbnail_path'),
      liveVideoPath: row.readNullable<String>('live_video_path'),
      derivedImagePath: row.readNullable<String>('derived_image_path'),
      checksum: row.readNullable<String>('checksum'),
      sizeBytes: row.readNullable<int>('size_bytes') ?? 0,
      liveVideoSizeBytes: row.readNullable<int>('live_video_size_bytes') ?? 0,
      derivedImageSizeBytes:
          row.readNullable<int>('derived_image_size_bytes') ?? 0,
      cachedAt:
          _fromMillis(row.read<int>('cached_at')) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastAccessedAt:
          _fromMillis(row.read<int>('last_accessed')) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

List<String> _decodeStrings(String? value) {
  if (value == null || value.isEmpty) {
    return <String>[];
  }
  try {
    final decoded = jsonDecode(value);
    if (decoded is List) {
      return decoded.whereType<String>().toList();
    }
  } on FormatException {
    return <String>[];
  }
  return <String>[];
}

DateTime? _fromMillis(int? value) {
  return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
}

DateTime? _parseDate(String? value) {
  return value == null || value.isEmpty ? null : DateTime.tryParse(value);
}

Future<CacheStats> _statsFor(
  Iterable<CachedAsset> assets, {
  required int albumCount,
  DateTime? lastSync,
}) async {
  var assetCount = 0;
  var originalBytes = 0;
  var thumbnailBytes = 0;
  var liveVideoBytes = 0;
  var derivedImageBytes = 0;
  var imageCount = 0;
  var imageBytes = 0;
  var videoCount = 0;
  var videoBytes = 0;
  for (final asset in assets) {
    assetCount++;
    originalBytes += asset.sizeBytes;
    liveVideoBytes += asset.liveVideoSizeBytes;
    derivedImageBytes += asset.derivedImageSizeBytes;
    final thumbnail = await _fileBytes(asset.thumbnailPath);
    thumbnailBytes += thumbnail;
    if (asset.type == MediaKind.video) {
      videoCount++;
      videoBytes += asset.totalSizeBytes + thumbnail;
    } else {
      imageCount++;
      imageBytes += asset.totalSizeBytes + thumbnail;
    }
  }
  return CacheStats(
    assetCount: assetCount,
    originalBytes: originalBytes,
    thumbnailBytes: thumbnailBytes,
    liveVideoBytes: liveVideoBytes,
    derivedImageBytes: derivedImageBytes,
    albumCount: albumCount,
    imageCount: imageCount,
    imageBytes: imageBytes,
    videoCount: videoCount,
    videoBytes: videoBytes,
    lastSync: lastSync,
  );
}

Future<int> _fileBytes(String? path) async {
  if (path == null || path.isEmpty) {
    return 0;
  }
  final file = File(path);
  if (await file.exists()) {
    return file.length();
  }
  return 0;
}
