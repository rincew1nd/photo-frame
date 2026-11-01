import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/platform/paths.dart';

/// Persists and loads [AppSettings].
abstract class SettingsRepository {
  /// Reads the current settings, falling back to defaults when missing.
  Future<AppSettings> load();

  /// Atomically writes [settings].
  Future<void> save(AppSettings settings);
}

/// Stores settings in `settings.json` under the support directory.
class FileSettingsRepository implements SettingsRepository {
  FileSettingsRepository(this._paths);

  final AppPaths _paths;
  File? _cachedFile;
  Future<File>? _fileFuture;
  int _saveCounter = 0;

  Future<File> _settingsFile() {
    return _fileFuture ??= _resolveSettingsFile();
  }

  Future<File> _resolveSettingsFile() async {
    final support = await _paths.support();
    return File(p.join(support.path, 'settings.json'));
  }

  @override
  Future<AppSettings> load() async {
    final file = _cachedFile = await _settingsFile();
    if (!await file.exists()) {
      return const AppSettings();
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('Settings root is not an object');
      }
      return migrate(<String, dynamic>{
        for (final entry in decoded.entries) entry.key.toString(): entry.value,
      });
    } on Object {
      await _backupCorrupt(file);
      return const AppSettings();
    }
  }

  Future<void> _backupCorrupt(File file) async {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final backup = File(
      p.join(file.parent.path, 'settings.corrupt.$timestamp.json'),
    );
    try {
      await file.rename(backup.path);
    } on FileSystemException {
      try {
        await file.copy(backup.path);
        await file.delete();
      } on FileSystemException {
        return;
      }
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    _cachedFile ??= await _settingsFile();
    final file = _cachedFile!;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final temporary = File('${file.path}.$stamp.${_saveCounter++}.tmp');
    temporary.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      flush: true,
    );
    if (file.existsSync()) {
      file.deleteSync();
    }
    temporary.renameSync(file.path);
  }
}

/// Keeps settings in memory; useful for tests and previews.
class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([AppSettings initial = const AppSettings()])
    : _settings = initial;

  AppSettings _settings;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
  }
}

/// Upgrades a decoded settings map to [AppSettings.currentSchemaVersion].
AppSettings migrate(Map<String, dynamic> json) {
  final data = Map<String, dynamic>.from(json);
  final version = data['schemaVersion'];
  final parsedVersionOrNull = version is num
      ? version.toInt()
      : version is String
      ? int.tryParse(version)
      : 0;
  var parsedVersion = parsedVersionOrNull ?? 0;

  if (parsedVersion < 1) {
    data['schemaVersion'] = 1;
    data.putIfAbsent('playback', () => <String, dynamic>{});
    data.putIfAbsent('filters', () => <String, dynamic>{});
    data.putIfAbsent('display', () => <String, dynamic>{});
    data.putIfAbsent('cache', () => <String, dynamic>{});
    data.putIfAbsent('overlays', () => <String, dynamic>{});
    data.putIfAbsent('automation', () => <String, dynamic>{});
    data.putIfAbsent('connection', () => <String, dynamic>{});
    data.putIfAbsent('defaultProfile', () => <String, dynamic>{});
    data.putIfAbsent('aspectOverrides', () => <String, dynamic>{});
    parsedVersion = 1;
  }

  if (parsedVersion < 2) {
    _migrateV1ToV2(data);
  }

  if (parsedVersion < 3) {
    _migrateV2ToV3(data);
  }

  if (parsedVersion < 4) {
    _migrateV3ToV4(data);
  }

  return AppSettings.fromJson(data);
}

void _migrateV1ToV2(Map<String, dynamic> data) {
  data['schemaVersion'] = 2;

  final playback = _section(data, 'playback');
  final defaultProfile = _section(data, 'defaultProfile');
  final display = _section(data, 'display');
  final automation = _section(data, 'automation');
  final filters = _section(data, 'filters');
  final overrides = _jsonMap(data['aspectOverrides']);

  final imageMotion = display['imageMotion'];
  final livePhotoMode = defaultProfile['livePhotoMode'];

  playback.putIfAbsent(
    'livePhotoMode',
    () => livePhotoMode ?? LivePhotoMode.off.jsonName,
  );
  playback.putIfAbsent(
    'videoPlaybackMode',
    () => VideoPlaybackMode.staticPreview.jsonName,
  );
  defaultProfile.putIfAbsent('imageMotion', () => imageMotion ?? true);
  defaultProfile.putIfAbsent(
    'adaptiveBackground',
    () => AdaptiveBackground.none.jsonName,
  );
  automation['fullscreen'] = false;

  if (!data.containsKey('customizations')) {
    final customizations = <Map<String, dynamic>>[];
    for (final bucket in AspectBucket.values) {
      if (!overrides.containsKey(bucket.jsonName)) {
        continue;
      }
      final profile = <String, dynamic>{
        ..._jsonMap(overrides[bucket.jsonName]),
      };
      profile.remove('livePhotoMode');
      profile.putIfAbsent('imageMotion', () => imageMotion ?? true);
      profile.putIfAbsent(
        'adaptiveBackground',
        () => AdaptiveBackground.none.jsonName,
      );
      customizations.add(<String, dynamic>{
        'id': 'aspect-${bucket.jsonName}',
        'name': '${bucket.label} override',
        'aspects': <String>[bucket.jsonName],
        'mediaTypes': <String>[],
        'profile': profile,
      });
    }
    data['customizations'] = customizations;
  }

  data.remove('aspectOverrides');
  filters.remove('enabledTypes');
  filters.remove('enabledAspects');
  display.remove('imageMotion');
  automation.remove('launcherMode');
  automation.remove('kiosk');
  automation.remove('updateChecks');
  defaultProfile.remove('livePhotoMode');
}

void _migrateV2ToV3(Map<String, dynamic> data) {
  data['schemaVersion'] = 3;

  final automation = _section(data, 'automation');
  automation.putIfAbsent('startOnBoot', () => false);
  automation.putIfAbsent('kiosk', () => false);
  automation.putIfAbsent('updateChecks', () => false);
}

void _migrateV3ToV4(Map<String, dynamic> data) {
  data['schemaVersion'] = 4;

  final plugins = _section(data, 'plugins');
  plugins.putIfAbsent('gridSnap', () => false);
  plugins.putIfAbsent('gridSize', () => 16);
  plugins.putIfAbsent('seededExamplesVersion', () => 0);
}

Map<String, dynamic> _section(Map<String, dynamic> data, String key) {
  final section = _jsonMap(data[key]);
  data[key] = section;
  return section;
}

Map<String, dynamic> _jsonMap(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return <String, dynamic>{};
}
