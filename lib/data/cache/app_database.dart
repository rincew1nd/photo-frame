import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

const String cachedAssetsTableSql =
    'CREATE TABLE IF NOT EXISTS cached_assets ('
    'id TEXT PRIMARY KEY, '
    'album_ids TEXT NOT NULL, '
    'media_kind TEXT, '
    'mime TEXT, '
    'width INTEGER, '
    'height INTEGER, '
    'aspect TEXT, '
    'duration INTEGER, '
    'live_video_id TEXT, '
    'exif_date TEXT, '
    'description TEXT, '
    'location TEXT, '
    'tags TEXT, '
    'original_path TEXT, '
    'thumbnail_path TEXT, '
    'live_video_path TEXT, '
    'derived_image_path TEXT, '
    'checksum TEXT, '
    'size_bytes INTEGER, '
    'live_video_size_bytes INTEGER, '
    'derived_image_size_bytes INTEGER, '
    'cached_at INTEGER, '
    'last_accessed INTEGER'
    ')';

const String albumSyncStatesTableSql =
    'CREATE TABLE IF NOT EXISTS album_sync_states ('
    'album_id TEXT PRIMARY KEY, '
    'last_sync INTEGER, '
    'asset_count INTEGER'
    ')';

const String pluginRegistryTableSql =
    'CREATE TABLE IF NOT EXISTS plugin_registry ('
    'id TEXT PRIMARY KEY, '
    'version TEXT NOT NULL, '
    'api_version INTEGER NOT NULL, '
    'manifest_json TEXT NOT NULL, '
    'bundle_path TEXT NOT NULL, '
    'sha256 TEXT NOT NULL, '
    'enabled INTEGER NOT NULL, '
    'source TEXT NOT NULL, '
    'installed_at INTEGER NOT NULL, '
    'updated_at INTEGER NOT NULL'
    ')';

const String pluginInstancesTableSql =
    'CREATE TABLE IF NOT EXISTS plugin_instances ('
    'plugin_id TEXT PRIMARY KEY, '
    'x REAL, '
    'y REAL, '
    'width REAL NOT NULL, '
    'height REAL NOT NULL, '
    'z_order INTEGER NOT NULL, '
    'show_during_night INTEGER NOT NULL, '
    'config_json TEXT NOT NULL, '
    'visible INTEGER NOT NULL, '
    'updated_at INTEGER NOT NULL'
    ')';

const String pluginStorageTableSql =
    'CREATE TABLE IF NOT EXISTS plugin_storage ('
    'plugin_id TEXT NOT NULL, '
    'key TEXT NOT NULL, '
    'value TEXT NOT NULL, '
    'updated_at INTEGER NOT NULL, '
    'PRIMARY KEY(plugin_id, key)'
    ')';

// Seed/migration markers (for example, whether bundled examples were seeded).
const String pluginMetaTableSql =
    'CREATE TABLE IF NOT EXISTS plugin_meta ('
    'key TEXT PRIMARY KEY, '
    'value TEXT NOT NULL'
    ')';

class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);

  static Future<AppDatabase> open(File file) async {
    return AppDatabase(NativeDatabase(file, enableMigrations: false));
  }

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables =>
      const <TableInfo<Table, dynamic>>[];

  @override
  int get schemaVersion => 4;

  static const Map<String, String> _cachedAssetColumns = <String, String>{
    'live_video_path': 'TEXT',
    'derived_image_path': 'TEXT',
    'live_video_size_bytes': 'INTEGER',
    'derived_image_size_bytes': 'INTEGER',
  };

  Future<void> migrate() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS schema_meta (version INTEGER NOT NULL)',
    );
    final rows = await customSelect('SELECT version FROM schema_meta LIMIT 1')
        .get();
    await customStatement(cachedAssetsTableSql);
    await customStatement(albumSyncStatesTableSql);
    await customStatement(pluginRegistryTableSql);
    await customStatement(pluginInstancesTableSql);
    await customStatement(pluginStorageTableSql);
    await customStatement(pluginMetaTableSql);
    final info = await customSelect('PRAGMA table_info(cached_assets)').get();
    final existing = info.map((row) => row.read<String>('name')).toSet();
    for (final column in _cachedAssetColumns.entries) {
      if (!existing.contains(column.key)) {
        await customStatement(
          'ALTER TABLE cached_assets ADD COLUMN ${column.key} ${column.value}',
        );
      }
    }
    if (rows.isEmpty) {
      await customStatement(
        'INSERT INTO schema_meta (version) VALUES ($schemaVersion)',
      );
    } else if (rows.first.read<int>('version') != schemaVersion) {
      await customStatement('UPDATE schema_meta SET version = $schemaVersion');
    }
  }
}
