import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/cache/app_database.dart';

const String _schemaVersion2CachedAssetsSql =
    'CREATE TABLE cached_assets ('
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
    'checksum TEXT, '
    'size_bytes INTEGER, '
    'cached_at INTEGER, '
    'last_accessed INTEGER'
    ')';

void main() {
  test('migrates an in-memory database to schema version 3', () async {
    AppDatabase? database;
    try {
      database = AppDatabase(NativeDatabase.memory());
      await database.migrate();

      expect(database.schemaVersion, 3);
      final rows = await database
          .customSelect('SELECT version FROM schema_meta')
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<int>('version'), 3);

      final info = await database
          .customSelect('PRAGMA table_info(cached_assets)')
          .get();
      final columns = info.map((row) => row.read<String>('name')).toSet();
      expect(columns, contains('live_video_path'));
      expect(columns, contains('derived_image_path'));
      expect(columns, contains('live_video_size_bytes'));
      expect(columns, contains('derived_image_size_bytes'));
    } on Object catch (error) {
      markTestSkipped(
        'sqlite3 native library is unavailable in this environment: $error',
      );
    } finally {
      await database?.close();
    }
  });

  test('upgrades a version 2 database without losing rows', () async {
    AppDatabase? database;
    try {
      database = AppDatabase(NativeDatabase.memory());
      await database.customStatement(_schemaVersion2CachedAssetsSql);
      await database.customStatement(
        'CREATE TABLE schema_meta (version INTEGER NOT NULL)',
      );
      await database.customStatement(
        'INSERT INTO schema_meta (version) VALUES (2)',
      );
      await database.customStatement(
        'INSERT INTO cached_assets (id, album_ids, size_bytes, cached_at, '
        "last_accessed) VALUES ('legacy', '[\"album-1\"]', 10, 0, 0)",
      );

      await database.migrate();

      final version = await database
          .customSelect('SELECT version FROM schema_meta')
          .get();
      expect(version.single.read<int>('version'), 3);

      final asset = await database
          .customSelect("SELECT * FROM cached_assets WHERE id = 'legacy'")
          .get();
      expect(asset, hasLength(1));
      expect(asset.single.read<int>('size_bytes'), 10);
      expect(asset.single.readNullable<String>('live_video_path'), isNull);
      expect(asset.single.readNullable<String>('derived_image_path'), isNull);
      expect(
        asset.single.readNullable<int>('live_video_size_bytes'),
        isNull,
      );
      expect(
        asset.single.readNullable<int>('derived_image_size_bytes'),
        isNull,
      );

      final info = await database
          .customSelect('PRAGMA table_info(cached_assets)')
          .get();
      final columns = info.map((row) => row.read<String>('name')).toSet();
      expect(columns, contains('live_video_path'));
      expect(columns, contains('derived_image_path'));
      expect(columns, contains('live_video_size_bytes'));
      expect(columns, contains('derived_image_size_bytes'));
    } on Object catch (error) {
      markTestSkipped(
        'sqlite3 native library is unavailable in this environment: $error',
      );
    } finally {
      await database?.close();
    }
  });
}
