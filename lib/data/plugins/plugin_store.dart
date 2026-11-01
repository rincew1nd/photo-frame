import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/core/clock.dart';
import 'package:photoframe/data/cache/app_database.dart';
import 'package:photoframe/data/plugins/plugin_bundle.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';
import 'package:photoframe/platform/paths.dart';

/// The source values persisted in `plugin_registry.source`.
const String pluginSourceZip = 'zip';
const String pluginSourceBundled = 'bundled';

const Set<String> _pluginSources = <String>{
  pluginSourceZip,
  pluginSourceBundled,
};

/// A readable failure raised by plugin persistence operations.
///
/// It extends [PluginValidationException] so callers can treat duplicate,
/// missing, and invalid plugin operations like any other validation failure.
class PluginStoreException extends PluginValidationException {
  const PluginStoreException(super.message);
}

/// An installed plugin plus its instance configuration and placement.
class InstalledPlugin {
  const InstalledPlugin({
    required this.id,
    required this.version,
    required this.apiVersion,
    required this.manifest,
    required this.bundlePath,
    required this.sha256,
    required this.enabled,
    required this.source,
    required this.installedAt,
    required this.updatedAt,
    required this.config,
    required this.placement,
    required this.visible,
  });

  final String id;
  final String version;
  final int apiVersion;
  final PluginManifest manifest;
  final String bundlePath;
  final String sha256;
  final bool enabled;

  /// One of [pluginSourceZip] or [pluginSourceBundled].
  final String source;
  final DateTime installedAt;
  final DateTime updatedAt;
  final Map<String, dynamic> config;
  final PluginPlacement placement;
  final bool visible;
}

/// Persists installed plugins, their configuration, placement, and storage.
///
/// Bundles live under `<support>/plugins/<id>/<version>/`; metadata lives in
/// the v4 `plugin_*` tables. The canonical seed marker is the `plugin_meta`
/// row [seedMarkerKey]; [isSeeded] and [markSeeded] read and write it.
class PluginStore {
  PluginStore(
    this._db,
    this._paths, {
    Clock clock = const SystemClock(),
  }) : _clock = clock;

  final AppDatabase _db;
  final AppPaths _paths;
  final Clock _clock;

  /// The single marker that records whether bundled examples were seeded.
  static const String seedMarkerKey = 'bundled_examples_seeded';

  /// Version marker for refreshing bundled examples without reinstalling
  /// deleted ones.
  static const String seedVersionKey = 'bundled_examples_version';

  /// Per-plugin limit for the sum of all value bytes in `plugin_storage`.
  static const int storageQuotaBytes = 1024 * 1024;

  bool _initialized = false;

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

  Future<List<InstalledPlugin>> list() async {
    await _ready();
    final rows = await _db
        .customSelect('SELECT * FROM plugin_registry ORDER BY id')
        .get();
    final plugins = <InstalledPlugin>[];
    for (final row in rows) {
      plugins.add(
        _installedFromRow(row, await _instanceRow(row.read<String>('id'))),
      );
    }
    return plugins;
  }

  Future<InstalledPlugin?> get(String id) async {
    await _ready();
    final rows = await _db
        .customSelect(
          'SELECT * FROM plugin_registry WHERE id = ? LIMIT 1',
          variables: <Variable>[Variable.withString(id)],
        )
        .get();
    if (rows.isEmpty) {
      return null;
    }
    return _installedFromRow(rows.first, await _instanceRow(id));
  }

  /// Installs [bundle] through a temporary directory and atomic rename.
  ///
  /// With [overwrite] an existing plugin is replaced and returns to its
  /// manifest defaults. Without it a duplicate id is rejected before any file
  /// is written.
  Future<InstalledPlugin> install(
    PluginBundle bundle, {
    required bool enabled,
    required String source,
    bool overwrite = false,
  }) async {
    await _ready();
    _validateSource(source);

    final id = bundle.manifest.id;
    final existing = await get(id);
    if (existing != null && !overwrite) {
      throw PluginStoreException('Plugin "$id" is already installed.');
    }

    final now = _clock.now();
    final config = _defaultConfig(bundle.manifest);
    final placement = _defaultPlacement(bundle.manifest);
    final staged = await _stageBundle(bundle);

    try {
      await _db.transaction(() async {
        await _writeRegistry(
          bundle: bundle,
          bundlePath: staged.target.path,
          enabled: enabled,
          source: source,
          installedAt: existing?.installedAt ?? now,
          updatedAt: now,
        );
        await _writeInstance(
          id: id,
          config: config,
          placement: placement,
          visible: true,
          updatedAt: now,
        );
      });
    } on Object {
      await staged.rollback();
      rethrow;
    }

    await staged.commit();
    if (existing != null && existing.bundlePath != staged.target.path) {
      await _tryDeleteDirectory(Directory(existing.bundlePath));
    }
    return (await get(id))!;
  }

  /// Replaces an installed plugin with [bundle].
  ///
  /// Configuration is preserved when the settings keys, types, and defaults
  /// are unchanged; otherwise it resets to the new manifest defaults.
  /// Placement is independent of the settings schema and is always preserved.
  /// The old bundle is removed only after the database update succeeds.
  Future<InstalledPlugin> update(
    PluginBundle bundle, {
    required bool enabled,
    bool resetPlacement = false,
  }) async {
    await _ready();
    final id = bundle.manifest.id;
    final existing = await get(id);
    if (existing == null) {
      throw PluginStoreException('Plugin "$id" is not installed.');
    }

    final compatible = _settingsCompatible(
      existing.manifest,
      bundle.manifest,
    );
    final config = compatible
        ? existing.config
        : _defaultConfig(bundle.manifest);
    final now = _clock.now();
    final staged = await _stageBundle(bundle);

    try {
      await _db.transaction(() async {
        await _writeRegistry(
          bundle: bundle,
          bundlePath: staged.target.path,
          enabled: enabled,
          source: existing.source,
          installedAt: existing.installedAt,
          updatedAt: now,
        );
        await _writeInstance(
          id: id,
          config: config,
          placement: resetPlacement
              ? _defaultPlacement(bundle.manifest)
              : existing.placement,
          visible: existing.visible,
          updatedAt: now,
        );
      });
    } on Object {
      await staged.rollback();
      rethrow;
    }

    await staged.commit();
    if (existing.bundlePath != staged.target.path) {
      await _tryDeleteDirectory(Directory(existing.bundlePath));
    }
    return (await get(id))!;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await _ready();
    await _requirePlugin(id);
    final now = _clock.now();
    await _db.customStatement(
      'UPDATE plugin_registry SET enabled = ?, updated_at = ? WHERE id = ?',
      <Object?>[enabled ? 1 : 0, now.millisecondsSinceEpoch, id],
    );
  }

  Future<void> setVisible(String id, bool visible) async {
    await _ready();
    await _requireInstance(id);
    final now = _clock.now();
    await _db.customStatement(
      'UPDATE plugin_instances SET visible = ?, updated_at = ? '
      'WHERE plugin_id = ?',
      <Object?>[visible ? 1 : 0, now.millisecondsSinceEpoch, id],
    );
  }

  Future<void> delete(String id) async {
    await _ready();
    await _requirePlugin(id);
    final support = await _paths.support();

    await _db.transaction(() async {
      await _db.customStatement(
        'DELETE FROM plugin_storage WHERE plugin_id = ?',
        <Object?>[id],
      );
      await _db.customStatement(
        'DELETE FROM plugin_instances WHERE plugin_id = ?',
        <Object?>[id],
      );
      await _db.customStatement(
        'DELETE FROM plugin_registry WHERE id = ?',
        <Object?>[id],
      );
    });

    await _tryDeleteDirectory(
      Directory(p.join(support.path, 'plugins', id)),
    );
  }

  Future<Map<String, dynamic>> getConfig(String id) async {
    await _ready();
    final rows = await _instanceRows(id);
    if (rows.isEmpty) {
      throw PluginStoreException('Plugin "$id" is not installed.');
    }
    return _decodeJsonMap(
      rows.first.read<String>('config_json'),
      'Plugin "$id" configuration',
    );
  }

  Future<void> setConfig(String id, Map<String, dynamic> config) async {
    await _ready();
    await _requireInstance(id);
    final encoded = _encodeJson(config, 'Plugin configuration');
    final now = _clock.now();
    await _db.customStatement(
      'UPDATE plugin_instances SET config_json = ?, updated_at = ? '
      'WHERE plugin_id = ?',
      <Object?>[encoded, now.millisecondsSinceEpoch, id],
    );
  }

  Future<PluginPlacement> getPlacement(String id) async {
    final plugin = await get(id);
    if (plugin == null) {
      throw PluginStoreException('Plugin "$id" is not installed.');
    }
    return plugin.placement;
  }

  Future<void> setPlacement(String id, PluginPlacement placement) async {
    await _ready();
    _validatePlacement(placement);
    await _requireInstance(id);
    final now = _clock.now();
    await _db.customStatement(
      'UPDATE plugin_instances SET x = ?, y = ?, width = ?, height = ?, '
      'z_order = ?, show_during_night = ?, updated_at = ? '
      'WHERE plugin_id = ?',
      <Object?>[
        placement.x,
        placement.y,
        placement.width,
        placement.height,
        placement.zOrder,
        placement.showDuringNight ? 1 : 0,
        now.millisecondsSinceEpoch,
        id,
      ],
    );
  }

  Future<String?> storageGet(String id, String key) async {
    await _ready();
    await _requirePlugin(id);
    final rows = await _db
        .customSelect(
          'SELECT value FROM plugin_storage '
          'WHERE plugin_id = ? AND key = ? LIMIT 1',
          variables: <Variable>[
            Variable.withString(id),
            Variable.withString(key),
          ],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<String>('value');
  }

  /// Stores a JSON-string [value], enforcing the per-plugin byte quota.
  Future<void> storageSet(String id, String key, String value) async {
    await _ready();
    await _requirePlugin(id);
    if (key.isEmpty) {
      throw const PluginStoreException('Plugin storage keys must not be empty.');
    }

    final valueBytes = utf8.encode(value).length;
    if (valueBytes > storageQuotaBytes) {
      throw const PluginStoreException(
        'Plugin storage value exceeds the 1 MB quota.',
      );
    }

    final rows = await _db
        .customSelect(
          'SELECT COALESCE(SUM(LENGTH(CAST(value AS BLOB))), 0) AS total, '
          'COALESCE(MAX(CASE WHEN key = ? '
          'THEN LENGTH(CAST(value AS BLOB)) ELSE 0 END), 0) AS existing '
          'FROM plugin_storage WHERE plugin_id = ?',
          variables: <Variable>[
            Variable.withString(key),
            Variable.withString(id),
          ],
        )
        .get();
    final total = rows.first.read<int>('total');
    final existing = rows.first.read<int>('existing');
    if (total - existing + valueBytes > storageQuotaBytes) {
      throw const PluginStoreException(
        'Plugin storage exceeds the 1 MB quota.',
      );
    }

    await _db.customInsert(
      'INSERT OR REPLACE INTO plugin_storage '
      '(plugin_id, key, value, updated_at) VALUES (?, ?, ?, ?)',
      variables: <Variable>[
        Variable.withString(id),
        Variable.withString(key),
        Variable.withString(value),
        Variable.withInt(_clock.now().millisecondsSinceEpoch),
      ],
    );
  }

  Future<void> storageRemove(String id, String key) async {
    await _ready();
    await _requirePlugin(id);
    await _db.customStatement(
      'DELETE FROM plugin_storage WHERE plugin_id = ? AND key = ?',
      <Object?>[id, key],
    );
  }

  Future<void> storageClear(String id) async {
    await _ready();
    await _requirePlugin(id);
    await _db.customStatement(
      'DELETE FROM plugin_storage WHERE plugin_id = ?',
      <Object?>[id],
    );
  }

  /// True once bundled examples have been seeded.
  ///
  /// This is the canonical marker; [seedMarkerKey] is the `plugin_meta` key.
  Future<bool> isSeeded() async {
    await _ready();
    final rows = await _db
        .customSelect(
          'SELECT value FROM plugin_meta WHERE key = ? LIMIT 1',
          variables: <Variable>[Variable.withString(seedMarkerKey)],
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<void> markSeeded() async {
    await _ready();
    await writeMeta(
      seedMarkerKey,
      _clock.now().toUtc().toIso8601String(),
    );
  }

  Future<int> seededVersion() async {
    final value = await readMeta(seedVersionKey);
    return int.tryParse(value ?? '') ?? 0;
  }

  Future<void> markSeededVersion(int version) async {
    await writeMeta(seedVersionKey, '$version');
  }

  Future<String?> readMeta(String key) async {
    await _ready();
    final rows = await _db
        .customSelect(
          'SELECT value FROM plugin_meta WHERE key = ? LIMIT 1',
          variables: <Variable>[Variable.withString(key)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<String>('value');
  }

  Future<void> writeMeta(String key, String value) async {
    await _ready();
    await _db.customInsert(
      'INSERT OR REPLACE INTO plugin_meta (key, value) VALUES (?, ?)',
      variables: <Variable>[
        Variable.withString(key),
        Variable.withString(value),
      ],
    );
  }

  Future<List<QueryRow>> _instanceRows(String id) {
    return _db
        .customSelect(
          'SELECT * FROM plugin_instances WHERE plugin_id = ? LIMIT 1',
          variables: <Variable>[Variable.withString(id)],
        )
        .get();
  }

  Future<QueryRow?> _instanceRow(String id) async {
    final rows = await _instanceRows(id);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _requirePlugin(String id) async {
    final rows = await _db
        .customSelect(
          'SELECT 1 FROM plugin_registry WHERE id = ? LIMIT 1',
          variables: <Variable>[Variable.withString(id)],
        )
        .get();
    if (rows.isEmpty) {
      throw PluginStoreException('Plugin "$id" is not installed.');
    }
  }

  Future<void> _requireInstance(String id) async {
    final rows = await _instanceRows(id);
    if (rows.isEmpty) {
      throw PluginStoreException('Plugin "$id" is not installed.');
    }
  }

  InstalledPlugin _installedFromRow(QueryRow row, QueryRow? instance) {
    final manifest = PluginManifest.fromJson(
      _decodeJsonMap(
        row.read<String>('manifest_json'),
        'Stored plugin manifest',
      ),
    );
    final fallback = _defaultPlacement(manifest);
    return InstalledPlugin(
      id: row.read<String>('id'),
      version: row.read<String>('version'),
      apiVersion: row.read<int>('api_version'),
      manifest: manifest,
      bundlePath: row.read<String>('bundle_path'),
      sha256: row.read<String>('sha256'),
      enabled: row.read<int>('enabled') != 0,
      source: row.read<String>('source'),
      installedAt: _fromMillis(row.read<int>('installed_at')),
      updatedAt: _fromMillis(row.read<int>('updated_at')),
      config: instance == null
          ? _defaultConfig(manifest)
          : _decodeJsonMap(
              instance.read<String>('config_json'),
              'Plugin "${manifest.id}" configuration',
            ),
      placement: instance == null
          ? fallback
          : _placementFromRow(instance, fallback),
      visible: instance == null || instance.read<int>('visible') != 0,
    );
  }

  Future<void> _writeRegistry({
    required PluginBundle bundle,
    required String bundlePath,
    required bool enabled,
    required String source,
    required DateTime installedAt,
    required DateTime updatedAt,
  }) async {
    final manifest = bundle.manifest;
    await _db.customInsert(
      'INSERT OR REPLACE INTO plugin_registry '
      '(id, version, api_version, manifest_json, bundle_path, sha256, '
      'enabled, source, installed_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      variables: <Variable>[
        Variable.withString(manifest.id),
        Variable.withString(manifest.version.value),
        Variable.withInt(manifest.apiVersion),
        Variable.withString(
          _encodeJson(_manifestToJson(manifest), 'Plugin manifest'),
        ),
        Variable.withString(bundlePath),
        Variable.withString(bundle.sha256),
        Variable.withInt(enabled ? 1 : 0),
        Variable.withString(source),
        Variable.withInt(installedAt.millisecondsSinceEpoch),
        Variable.withInt(updatedAt.millisecondsSinceEpoch),
      ],
    );
  }

  Future<void> _writeInstance({
    required String id,
    required Map<String, dynamic> config,
    required PluginPlacement placement,
    required bool visible,
    required DateTime updatedAt,
  }) async {
    await _db.customInsert(
      'INSERT OR REPLACE INTO plugin_instances '
      '(plugin_id, x, y, width, height, z_order, show_during_night, '
      'config_json, visible, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      variables: <Variable>[
        Variable.withString(id),
        Variable<double>(placement.x),
        Variable<double>(placement.y),
        Variable<double>(placement.width),
        Variable<double>(placement.height),
        Variable.withInt(placement.zOrder),
        Variable.withInt(placement.showDuringNight ? 1 : 0),
        Variable.withString(_encodeJson(config, 'Plugin configuration')),
        Variable.withInt(visible ? 1 : 0),
        Variable.withInt(updatedAt.millisecondsSinceEpoch),
      ],
    );
  }

  /// Writes the bundle into a temp directory, then renames it into place.
  /// Any previous directory at the same version is moved aside and restored
  /// if the rename fails.
  Future<_StagedBundle> _stageBundle(PluginBundle bundle) async {
    final support = await _paths.support();
    final id = bundle.manifest.id;
    final version = bundle.manifest.version.value;
    final root = Directory(p.join(support.path, 'plugins', id));

    try {
      await root.create(recursive: true);
    } on FileSystemException catch (error) {
      throw PluginStoreException(
        'Could not create the plugin directory: ${error.message}',
      );
    }

    final target = Directory(p.join(root.path, version));
    final stamp = _clock.now().microsecondsSinceEpoch;
    final temporary = Directory(
      p.join(root.path, '.$version.$stamp.tmp'),
    );
    final backup = Directory(p.join(root.path, '.$version.$stamp.bak'));
    Directory? previous;

    try {
      await temporary.create(recursive: true);
      for (final entry in bundle.files.entries) {
        final file = File(
          p.joinAll(<String>[temporary.path, ...entry.key.split('/')]),
        );
        if (!p.isWithin(temporary.path, file.path)) {
          throw const PluginStoreException(
            'Plugin file path escapes the bundle directory.',
          );
        }
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }

      if (await target.exists()) {
        await target.rename(backup.path);
        previous = backup;
      }
      await temporary.rename(target.path);
      return _StagedBundle(
        root: root,
        target: target,
        previous: previous,
      );
    } on Object catch (error) {
      await _tryDeleteDirectory(temporary);
      if (previous != null &&
          !await target.exists() &&
          await previous.exists()) {
        await previous.rename(target.path);
      }
      await _tryDeleteIfEmpty(root);
      if (error is PluginValidationException) {
        rethrow;
      }
      if (error is FileSystemException) {
        throw PluginStoreException(
          'Could not write the plugin bundle: ${error.message}',
        );
      }
      rethrow;
    }
  }

  void _validateSource(String source) {
    if (!_pluginSources.contains(source)) {
      throw PluginStoreException(
        'Unknown plugin source "$source"; expected zip or bundled.',
      );
    }
  }

  void _validatePlacement(PluginPlacement placement) {
    if (!placement.width.isFinite ||
        !placement.height.isFinite ||
        placement.width <= 0 ||
        placement.height <= 0) {
      throw const PluginStoreException(
        'Plugin placement width and height must be positive.',
      );
    }
    for (final coordinate in <double?>[placement.x, placement.y]) {
      if (coordinate != null &&
          (!coordinate.isFinite || coordinate < 0 || coordinate > 1)) {
        throw const PluginStoreException(
          'Plugin placement coordinates must be between 0 and 1.',
        );
      }
    }
  }
}

class _StagedBundle {
  _StagedBundle({required this.root, required this.target, this.previous});

  final Directory root;
  final Directory target;

  /// The previous directory at [target]'s path, moved aside before rename.
  final Directory? previous;

  bool _committed = false;

  Future<void> commit() async {
    if (_committed) {
      return;
    }
    final old = previous;
    if (old != null) {
      await _tryDeleteDirectory(old);
    }
    _committed = true;
  }

  Future<void> rollback() async {
    if (_committed) {
      return;
    }
    await _tryDeleteDirectory(target);
    final old = previous;
    if (old != null && await old.exists()) {
      await old.rename(target.path);
    }
    await _tryDeleteIfEmpty(root);
  }
}

Future<void> _tryDeleteDirectory(Directory directory) async {
  try {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  } on FileSystemException {
    // Best-effort cleanup; the registry is the source of truth.
  }
}

Future<void> _tryDeleteIfEmpty(Directory directory) async {
  try {
    if (!await directory.exists()) {
      return;
    }
    if (await directory.list().isEmpty) {
      await directory.delete(recursive: true);
    }
  } on FileSystemException {
    // Best-effort cleanup.
  }
}

PluginPlacement _defaultPlacement(PluginManifest manifest) {
  return manifest.placement ??
      const PluginPlacement(width: 320, height: 160);
}

Map<String, dynamic> _defaultConfig(PluginManifest manifest) {
  return <String, dynamic>{
    for (final field in manifest.settings) field.key: field.defaultValue,
  };
}

bool _settingsCompatible(PluginManifest oldManifest, PluginManifest newManifest) {
  if (oldManifest.settings.length != newManifest.settings.length) {
    return false;
  }
  final oldFields = <String, PluginSettingField>{
    for (final field in oldManifest.settings) field.key: field,
  };
  for (final field in newManifest.settings) {
    final oldField = oldFields[field.key];
    if (oldField == null ||
        oldField.type != field.type ||
        jsonEncode(oldField.defaultValue) != jsonEncode(field.defaultValue)) {
      return false;
    }
  }
  return true;
}

String _encodeJson(Object? value, String label) {
  try {
    return jsonEncode(value);
  } on Object {
    throw PluginStoreException('$label must be JSON-serializable.');
  }
}

Map<String, dynamic> _decodeJsonMap(String raw, String label) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return <String, dynamic>{
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value,
      };
    }
  } on FormatException {
    // Fall through to the readable error below.
  }
  throw PluginStoreException('$label is not a JSON object.');
}

DateTime _fromMillis(int value) {
  return DateTime.fromMillisecondsSinceEpoch(value);
}

PluginPlacement _placementFromRow(
  QueryRow row,
  PluginPlacement fallback,
) {
  return PluginPlacement(
    anchor: fallback.anchor,
    x: row.readNullable<double>('x'),
    y: row.readNullable<double>('y'),
    width: row.read<double>('width'),
    height: row.read<double>('height'),
    zOrder: row.read<int>('z_order'),
    showDuringNight: row.read<int>('show_during_night') != 0,
  );
}

Map<String, dynamic> _manifestToJson(PluginManifest manifest) {
  return <String, dynamic>{
    'id': manifest.id,
    'name': manifest.name,
    'version': manifest.version.value,
    'apiVersion': manifest.apiVersion,
    'minAppVersion': manifest.minAppVersion.value,
    'author': manifest.author,
    'license': manifest.license,
    'description': manifest.description,
    if (manifest.homepage != null) 'homepage': manifest.homepage,
    'entry': manifest.entry,
    if (manifest.icon != null) 'icon': manifest.icon,
    if (manifest.screenshots.isNotEmpty)
      'screenshots': manifest.screenshots.toList(),
    'permissions': <String, dynamic>{
      'network': manifest.permissions.network,
    },
    if (manifest.inputs.isNotEmpty)
      'inputs': manifest.inputs.map((input) => input.name).toList(),
    if (manifest.actions.isNotEmpty)
      'actions': manifest.actions.map((action) => action.name).toList(),
    if (manifest.updateTriggers.isNotEmpty)
      'updateTriggers': manifest.updateTriggers.toList(),
    if (manifest.placement != null)
      'placement': _placementToJson(manifest.placement!),
    if (manifest.settings.isNotEmpty)
      'settings': <String, dynamic>{
        for (final field in manifest.settings)
          field.key: _settingFieldToJson(field),
      },
  };
}

Map<String, dynamic> _placementToJson(PluginPlacement placement) {
  return <String, dynamic>{
    'anchor': placement.anchor.jsonName,
    if (placement.x != null) 'x': placement.x,
    if (placement.y != null) 'y': placement.y,
    'width': placement.width,
    'height': placement.height,
    'zOrder': placement.zOrder,
    'showDuringNight': placement.showDuringNight,
  };
}

Map<String, dynamic> _settingFieldToJson(PluginSettingField field) {
  return <String, dynamic>{
    'type': field.type.name,
    'label': field.label,
    'default': field.defaultValue,
    if (field.help != null) 'help': field.help,
    if (field.maxLength != null) 'maxLength': field.maxLength,
    if (field.rows != null) 'rows': field.rows,
    if (field.min != null) 'min': field.min,
    if (field.max != null) 'max': field.max,
    if (field.step != null) 'step': field.step,
    if (field.pattern != null) 'pattern': field.pattern,
    if (field.options.isNotEmpty)
      'options': <Map<String, String>>[
        for (final option in field.options)
          <String, String>{'value': option.value, 'label': option.label},
      ],
  };
}
