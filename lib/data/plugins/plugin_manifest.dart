/// Plugin manifest model and validation for plugin API v1.
///
/// This file is pure Dart: it never reads files, touches the network, or
/// renders UI. The ZIP/bundle layer supplies the decoded `plugin.json` map.
library;

/// The plugin API version supported by this host.
const int supportedPluginApiVersion = 1;

/// A readable, typed validation failure caused by untrusted plugin content.
///
/// Messages intentionally contain only manifest/field context, never decoded
/// file content, credentials, or stack traces.
class PluginValidationException implements Exception {
  const PluginValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A semantic version as declared by a plugin.
class PluginSemanticVersion implements Comparable<PluginSemanticVersion> {
  const PluginSemanticVersion._(
    this.major,
    this.minor,
    this.patch,
    this.prerelease,
  );

  factory PluginSemanticVersion.parse(
    Object? value, {
    String field = 'version',
  }) {
    if (value is! String) {
      throw PluginValidationException('$field must be a semantic version.');
    }
    final match = _semverPattern.firstMatch(value);
    if (match == null) {
      throw PluginValidationException(
        '$field must be a semantic version (for example 1.2.3).',
      );
    }
    final prerelease = match.group(4);
    return PluginSemanticVersion._(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      prerelease == null ? const <String>[] : prerelease.split('.'),
    );
  }

  final int major;
  final int minor;
  final int patch;
  final List<String> prerelease;

  String get value {
    final suffix = prerelease.isEmpty ? '' : '-${prerelease.join('.')}';
    return '$major.$minor.$patch$suffix';
  }

  @override
  int compareTo(PluginSemanticVersion other) {
    final majorCompare = major.compareTo(other.major);
    if (majorCompare != 0) {
      return majorCompare;
    }
    final minorCompare = minor.compareTo(other.minor);
    if (minorCompare != 0) {
      return minorCompare;
    }
    final patchCompare = patch.compareTo(other.patch);
    if (patchCompare != 0) {
      return patchCompare;
    }
    return _comparePrerelease(prerelease, other.prerelease);
  }

  static int _comparePrerelease(List<String> a, List<String> b) {
    if (a.isEmpty && b.isEmpty) {
      return 0;
    }
    if (a.isEmpty) {
      return 1;
    }
    if (b.isEmpty) {
      return -1;
    }
    final length = a.length < b.length ? a.length : b.length;
    for (var index = 0; index < length; index++) {
      final aPart = a[index];
      final bPart = b[index];
      final aNumber = int.tryParse(aPart);
      final bNumber = int.tryParse(bPart);
      if (aNumber != null && bNumber != null) {
        final compare = aNumber.compareTo(bNumber);
        if (compare != 0) {
          return compare;
        }
      } else if (aNumber != null) {
        return -1;
      } else if (bNumber != null) {
        return 1;
      } else {
        final compare = aPart.compareTo(bPart);
        if (compare != 0) {
          return compare;
        }
      }
    }
    return a.length.compareTo(b.length);
  }

  @override
  String toString() => value;
}

/// Snapshot sections a plugin may request. `app` and `time` are always
/// allowed; every other value must be explicitly declared.
enum PluginInput {
  app,
  time,
  weather,
  playback,
  media,
  image,
  config,
  placement;

  static PluginInput? tryParse(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final input in values) {
      if (input.name == value) {
        return input;
      }
    }
    return null;
  }
}

/// App actions a plugin may request in the manifest.
enum PluginAction {
  next,
  previous,
  pause,
  resume,
  togglePause,
  mute,
  unmute,
  toggleMute,
  mediaNext,
  mediaPrevious,
  mediaPlayPause,
  openSettings,
  openMediaSelection;

  static PluginAction? tryParse(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final action in values) {
      if (action.name == value) {
        return action;
      }
    }
    return null;
  }
}

/// Default placement anchor, one of the 3x3 positions.
enum PluginAnchor {
  topStart('top-start'),
  topCenter('top-center'),
  topEnd('top-end'),
  centerStart('center-start'),
  centerCenter('center-center'),
  centerEnd('center-end'),
  bottomStart('bottom-start'),
  bottomCenter('bottom-center'),
  bottomEnd('bottom-end');

  const PluginAnchor(this.jsonName);

  final String jsonName;

  static PluginAnchor? tryParse(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.replaceAll('_', '-');
    for (final anchor in values) {
      if (anchor.jsonName == normalized) {
        return anchor;
      }
    }
    return null;
  }
}

/// Declared capability permissions. Network access is denied by default.
class PluginPermissions {
  const PluginPermissions({this.network = false});

  final bool network;

  static const PluginPermissions none = PluginPermissions();
}

/// Optional default placement. Coordinates are normalized to 0..1; width and
/// height are logical pixels.
class PluginPlacement {
  const PluginPlacement({
    this.anchor = PluginAnchor.topStart,
    this.x,
    this.y,
    required this.width,
    required this.height,
    this.zOrder = 0,
    this.showDuringNight = false,
  });

  final PluginAnchor anchor;
  final double? x;
  final double? y;
  final double width;
  final double height;
  final int zOrder;
  final bool showDuringNight;
}

/// Supported settings field types.
enum PluginSettingType {
  text,
  multiline,
  number,
  boolean,
  select,
  color,
  url;

  static PluginSettingType? tryParse(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final type in values) {
      if (type.name == value) {
        return type;
      }
    }
    return null;
  }
}

/// One option in a `select` settings field.
class PluginSettingOption {
  const PluginSettingOption({required this.value, required this.label});

  final String value;
  final String label;
}

/// A single renderable settings field.
class PluginSettingField {
  PluginSettingField({
    required this.key,
    required this.type,
    required this.label,
    required this.defaultValue,
    this.help,
    this.maxLength,
    this.rows,
    this.min,
    this.max,
    this.step,
    this.pattern,
    List<PluginSettingOption> options = const <PluginSettingOption>[],
  }) : options = List.unmodifiable(options);

  final String key;
  final PluginSettingType type;
  final String label;
  final Object? defaultValue;
  final String? help;
  final int? maxLength;
  final int? rows;
  final num? min;
  final num? max;
  final num? step;
  final String? pattern;
  final List<PluginSettingOption> options;
}

/// Immutable, validated plugin manifest.
class PluginManifest {
  PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.apiVersion,
    required this.minAppVersion,
    required this.author,
    required this.license,
    required this.description,
    this.homepage,
    required this.entry,
    this.icon,
    required Set<String> screenshots,
    required this.permissions,
    required Set<PluginInput> inputs,
    required Set<PluginAction> actions,
    required Set<String> updateTriggers,
    this.placement,
    required List<PluginSettingField> settings,
  }) : screenshots = Set.unmodifiable(screenshots),
       inputs = Set.unmodifiable(inputs),
       actions = Set.unmodifiable(actions),
       updateTriggers = Set.unmodifiable(updateTriggers),
       settings = List.unmodifiable(settings);

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    _validatePluginId(id);

    final version = PluginSemanticVersion.parse(json['version']);
    final minAppVersion = json['minAppVersion'] == null
        ? PluginSemanticVersion.parse('0.0.0', field: 'minAppVersion')
        : PluginSemanticVersion.parse(
            json['minAppVersion'],
            field: 'minAppVersion',
          );

    final apiVersion = _asInt(json['apiVersion'], 'apiVersion');
    if (apiVersion < 1) {
      throw const PluginValidationException('apiVersion must be positive.');
    }

    final entry = normalizePluginPath(json['entry'], field: 'entry');
    final iconValue = json['icon'];
    final icon = iconValue == null
        ? null
        : normalizePluginPath(iconValue, field: 'icon');

    final screenshots = <String>{};
    final screenshotsValue = json['screenshots'];
    if (screenshotsValue != null) {
      for (final screenshot in _asList(
        screenshotsValue,
        'screenshots',
      )) {
        screenshots.add(
          normalizePluginPath(screenshot, field: 'screenshots'),
        );
      }
    }

    final permissionsJson = _asMap(json['permissions'], 'permissions');
    final networkValue = permissionsJson['network'];
    if (networkValue != null && networkValue is! bool) {
      throw const PluginValidationException(
        'permissions.network must be a boolean.',
      );
    }

    final inputs = <PluginInput>{};
    final inputsValue = json['inputs'];
    if (inputsValue != null) {
      for (final rawInput in _asList(inputsValue, 'inputs')) {
        final input = PluginInput.tryParse(rawInput);
        if (input == null) {
          throw PluginValidationException(
            'Unknown input "${_display(rawInput)}". Supported inputs: '
            '${PluginInput.values.map((item) => item.name).join(', ')}.',
          );
        }
        inputs.add(input);
      }
    }

    final actions = <PluginAction>{};
    final actionsValue = json['actions'];
    if (actionsValue != null) {
      for (final rawAction in _asList(actionsValue, 'actions')) {
        final action = PluginAction.tryParse(rawAction);
        if (action == null) {
          throw PluginValidationException(
            'Unknown action "${_display(rawAction)}". Supported actions: '
            '${PluginAction.values.map((item) => item.name).join(', ')}.',
          );
        }
        actions.add(action);
      }
    }

    final updateTriggers = <String>{};
    final updateTriggersValue = json['updateTriggers'];
    if (updateTriggersValue != null) {
      for (final rawTrigger in _asList(
        updateTriggersValue,
        'updateTriggers',
      )) {
        if (rawTrigger is! String || rawTrigger.trim().isEmpty) {
          throw const PluginValidationException(
            'updateTriggers must contain non-empty strings.',
          );
        }
        updateTriggers.add(rawTrigger);
      }
    }

    final placementValue = json['placement'];
    final placement = placementValue == null
        ? null
        : _parsePlacement(placementValue);

    return PluginManifest(
      id: id,
      name: _requiredString(json, 'name'),
      version: version,
      apiVersion: apiVersion,
      minAppVersion: minAppVersion,
      author: _requiredString(json, 'author'),
      license: _requiredString(json, 'license'),
      description: _requiredString(json, 'description'),
      homepage: _optionalString(json, 'homepage'),
      entry: entry,
      icon: icon,
      screenshots: screenshots,
      permissions: PluginPermissions(
        network: networkValue is bool ? networkValue : false,
      ),
      inputs: inputs,
      actions: actions,
      updateTriggers: updateTriggers,
      placement: placement,
      settings: _parseSettings(json['settings']),
    );
  }

  final String id;
  final String name;
  final PluginSemanticVersion version;
  final int apiVersion;
  final PluginSemanticVersion minAppVersion;
  final String author;
  final String license;
  final String description;
  final String? homepage;
  final String entry;
  final String? icon;
  final Set<String> screenshots;
  final PluginPermissions permissions;
  final Set<PluginInput> inputs;
  final Set<PluginAction> actions;
  final Set<String> updateTriggers;
  final PluginPlacement? placement;
  final List<PluginSettingField> settings;

  /// True when this plugin targets a supported API version and the host app
  /// is at least [minAppVersion].
  bool isCompatible({
    required int hostApiVersion,
    required String hostAppVersion,
  }) {
    return compatibilityIssue(
          hostApiVersion: hostApiVersion,
          hostAppVersion: hostAppVersion,
        ) ==
        null;
  }

  /// A readable reason why [isCompatible] is false, or null when compatible.
  String? compatibilityIssue({
    required int hostApiVersion,
    required String hostAppVersion,
  }) {
    if (hostApiVersion != supportedPluginApiVersion) {
      return 'Host plugin API version $hostApiVersion is not supported '
          '(requires v$supportedPluginApiVersion).';
    }
    if (apiVersion != supportedPluginApiVersion) {
      return 'Plugin API version $apiVersion is not supported '
          '(requires v$supportedPluginApiVersion).';
    }
    final hostVersion = PluginSemanticVersion.parse(
      hostAppVersion,
      field: 'hostAppVersion',
    );
    if (hostVersion.compareTo(minAppVersion) < 0) {
      return 'Plugin requires app version ${minAppVersion.value} or newer '
          '(host is ${hostVersion.value}).';
    }
    return null;
  }
}

/// Normalizes a bundle-relative path and rejects absolute, traversal, and
/// backslash paths. Empty and `.` segments are dropped.
String normalizePluginPath(Object? value, {String field = 'path'}) {
  if (value is! String) {
    throw PluginValidationException('$field must be a string.');
  }
  if (value.trim().isEmpty) {
    throw PluginValidationException('$field must not be empty.');
  }
  if (value.contains('\\')) {
    throw PluginValidationException('$field must not contain backslashes.');
  }
  if (value.startsWith('/')) {
    throw PluginValidationException('$field must be a relative path.');
  }
  if (RegExp(r'^[A-Za-z]:').hasMatch(value)) {
    throw PluginValidationException('$field must be a relative path.');
  }

  final segments = <String>[];
  for (final segment in value.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      throw PluginValidationException('$field must not contain ".." segments.');
    }
    for (final rune in segment.runes) {
      if (rune < 0x20 || rune == 0x7f) {
        throw PluginValidationException(
          '$field must not contain control characters.',
        );
      }
    }
    segments.add(segment);
  }
  if (segments.isEmpty) {
    throw PluginValidationException('$field must not be empty.');
  }
  return segments.join('/');
}

final RegExp _semverPattern = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
  r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
  r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
);

final RegExp _pluginIdPattern = RegExp(
  r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
  r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$',
);

final RegExp _colorPattern = RegExp(
  r'^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
);

void _validatePluginId(String id) {
  if (id.length > 255 || !_pluginIdPattern.hasMatch(id)) {
    throw const PluginValidationException(
      'id must be a reverse-DNS identifier such as com.example.plugin.',
    );
  }
}

Map<String, dynamic> _asMap(Object? value, String field) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map<Object?, Object?>) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw PluginValidationException('$field keys must be strings.');
      }
      result[key] = entry.value;
    }
    return result;
  }
  throw PluginValidationException('$field must be an object.');
}

List<Object?> _asList(Object? value, String field) {
  if (value is List<Object?>) {
    return value;
  }
  throw PluginValidationException('$field must be an array.');
}

String _requiredString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String || value.trim().isEmpty) {
    throw PluginValidationException('$field must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw PluginValidationException('$field must be a non-empty string.');
  }
  return value;
}

int _asInt(Object? value, String field) {
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  throw PluginValidationException('$field must be an integer.');
}

num _asNum(Object? value, String field) {
  if (value is num && value.isFinite) {
    return value;
  }
  throw PluginValidationException('$field must be a number.');
}

String _display(Object? value) {
  if (value is String) {
    return value;
  }
  if (value == null) {
    return 'null';
  }
  return value.runtimeType.toString();
}

PluginPlacement _parsePlacement(Object? value) {
  final json = _asMap(value, 'placement');

  final anchorValue = json['anchor'];
  final anchor = anchorValue == null
      ? PluginAnchor.topStart
      : PluginAnchor.tryParse(anchorValue);
  if (anchor == null) {
    throw PluginValidationException(
      'placement.anchor must be one of '
      '${PluginAnchor.values.map((item) => item.jsonName).join(', ')}.',
    );
  }

  final x = json['x'] == null
      ? null
      : _asCoordinate(json['x'], 'placement.x');
  final y = json['y'] == null
      ? null
      : _asCoordinate(json['y'], 'placement.y');

  final width = _asPositiveDouble(json['width'], 'placement.width');
  final height = _asPositiveDouble(json['height'], 'placement.height');

  final zOrder = json['zOrder'] == null
      ? 0
      : _asInt(json['zOrder'], 'placement.zOrder');

  final showDuringNightValue = json['showDuringNight'];
  if (showDuringNightValue != null && showDuringNightValue is! bool) {
    throw const PluginValidationException(
      'placement.showDuringNight must be a boolean.',
    );
  }

  return PluginPlacement(
    anchor: anchor,
    x: x,
    y: y,
    width: width,
    height: height,
    zOrder: zOrder,
    showDuringNight:
        showDuringNightValue is bool ? showDuringNightValue : false,
  );
}

double _asCoordinate(Object? value, String field) {
  final parsed = _asNum(value, field).toDouble();
  if (parsed < 0 || parsed > 1) {
    throw PluginValidationException('$field must be between 0 and 1.');
  }
  return parsed;
}

double _asPositiveDouble(Object? value, String field) {
  final parsed = _asNum(value, field).toDouble();
  if (parsed <= 0) {
    throw PluginValidationException('$field must be greater than 0.');
  }
  return parsed;
}

List<PluginSettingField> _parseSettings(Object? value) {
  if (value == null) {
    return const <PluginSettingField>[];
  }
  final json = _asMap(value, 'settings');
  final settings = <PluginSettingField>[];
  for (final entry in json.entries) {
    settings.add(_parseSettingField(entry.key, entry.value));
  }
  return List.unmodifiable(settings);
}

PluginSettingField _parseSettingField(String key, Object? value) {
  if (key.trim().isEmpty) {
    throw const PluginValidationException(
      'settings field names must not be empty.',
    );
  }
  final json = _asMap(value, 'settings.$key');
  final type = PluginSettingType.tryParse(json['type']);
  if (type == null) {
    throw PluginValidationException(
      'settings.$key.type must be one of '
      '${PluginSettingType.values.map((item) => item.name).join(', ')}.',
    );
  }

  final label = _requiredString(json, 'label');
  final help = _optionalString(json, 'help');

  if (!json.containsKey('default')) {
    throw PluginValidationException('settings.$key.default is required.');
  }
  final defaultValue = json['default'];

  int? maxLength;
  int? rows;
  num? min;
  num? max;
  num? step;
  String? pattern;
  var options = const <PluginSettingOption>[];

  switch (type) {
    case PluginSettingType.text:
    case PluginSettingType.multiline:
      if (defaultValue is! String) {
        throw PluginValidationException(
          'settings.$key.default must be a string.',
        );
      }
      if (json['maxLength'] != null) {
        maxLength = _asInt(json['maxLength'], 'settings.$key.maxLength');
        if (maxLength <= 0) {
          throw PluginValidationException(
            'settings.$key.maxLength must be greater than 0.',
          );
        }
      }
      if (json['rows'] != null) {
        rows = _asInt(json['rows'], 'settings.$key.rows');
        if (rows <= 0) {
          throw PluginValidationException(
            'settings.$key.rows must be greater than 0.',
          );
        }
      }
      if (json['pattern'] != null) {
        final parsedPattern = _asPattern(
          json['pattern'],
          'settings.$key.pattern',
        );
        pattern = parsedPattern;
        if (!RegExp(parsedPattern).hasMatch(defaultValue)) {
          throw PluginValidationException(
            'settings.$key.default does not match its pattern.',
          );
        }
      }
      break;
    case PluginSettingType.number:
      if (defaultValue is! num || !defaultValue.isFinite) {
        throw PluginValidationException(
          'settings.$key.default must be a number.',
        );
      }
      if (json['min'] != null) {
        min = _asNum(json['min'], 'settings.$key.min');
      }
      if (json['max'] != null) {
        max = _asNum(json['max'], 'settings.$key.max');
      }
      if (min != null && max != null && min > max) {
        throw PluginValidationException(
          'settings.$key.min must not be greater than max.',
        );
      }
      if (min != null && defaultValue < min) {
        throw PluginValidationException(
          'settings.$key.default must be at least min.',
        );
      }
      if (max != null && defaultValue > max) {
        throw PluginValidationException(
          'settings.$key.default must be at most max.',
        );
      }
      if (json['step'] != null) {
        step = _asNum(json['step'], 'settings.$key.step');
        if (step <= 0) {
          throw PluginValidationException(
            'settings.$key.step must be greater than 0.',
          );
        }
      }
      break;
    case PluginSettingType.boolean:
      if (defaultValue is! bool) {
        throw PluginValidationException(
          'settings.$key.default must be a boolean.',
        );
      }
      break;
    case PluginSettingType.select:
      final rawOptions = json['options'];
      if (rawOptions == null) {
        throw PluginValidationException(
          'settings.$key.options is required.',
        );
      }
      final parsedOptions = <PluginSettingOption>[];
      final values = <String>{};
      for (final rawOption in _asList(rawOptions, 'settings.$key.options')) {
        final optionJson = _asMap(rawOption, 'settings.$key.options');
        final optionValue = _requiredString(optionJson, 'value');
        final optionLabel = _requiredString(optionJson, 'label');
        if (!values.add(optionValue)) {
          throw PluginValidationException(
            'settings.$key.options contain duplicate values.',
          );
        }
        parsedOptions.add(
          PluginSettingOption(value: optionValue, label: optionLabel),
        );
      }
      if (parsedOptions.isEmpty) {
        throw PluginValidationException(
          'settings.$key.options must not be empty.',
        );
      }
      if (defaultValue is! String || !values.contains(defaultValue)) {
        throw PluginValidationException(
          'settings.$key.default must match an option value.',
        );
      }
      options = parsedOptions;
      break;
    case PluginSettingType.color:
      if (defaultValue is! String || !_colorPattern.hasMatch(defaultValue)) {
        throw PluginValidationException(
          'settings.$key.default must be #RRGGBB or #AARRGGBB.',
        );
      }
      break;
    case PluginSettingType.url:
      if (defaultValue is! String) {
        throw PluginValidationException(
          'settings.$key.default must be a URL string.',
        );
      }
      _validateUrl(defaultValue, 'settings.$key.default');
      if (json['pattern'] != null) {
        final parsedPattern = _asPattern(
          json['pattern'],
          'settings.$key.pattern',
        );
        pattern = parsedPattern;
        if (!RegExp(parsedPattern).hasMatch(defaultValue)) {
          throw PluginValidationException(
            'settings.$key.default does not match its pattern.',
          );
        }
      }
      break;
  }

  return PluginSettingField(
    key: key,
    type: type,
    label: label,
    defaultValue: defaultValue,
    help: help,
    maxLength: maxLength,
    rows: rows,
    min: min,
    max: max,
    step: step,
    pattern: pattern,
    options: options,
  );
}

String _asPattern(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw PluginValidationException('$field must be a non-empty string.');
  }
  try {
    RegExp(value);
  } on FormatException {
    throw PluginValidationException('$field is not a valid regular expression.');
  }
  return value;
}

void _validateUrl(String value, String field) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw PluginValidationException('$field must be an http or https URL.');
  }
}
