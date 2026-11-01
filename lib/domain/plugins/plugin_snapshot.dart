/// Redacted, read-only plugin state snapshots for plugin API v1.
///
/// The builder is pure Dart: it reads only the typed inputs in
/// [PluginSnapshotSource] and emits a bounded map. It never receives an
/// `ImmichAsset`, a `CachedAsset`, a file path, an album id, a checksum, an API
/// key, a server URL, or credentials.
library;

import 'package:photoframe/data/plugins/plugin_manifest.dart';

/// Safe-area insets in logical pixels.
class PluginInsets {
  const PluginInsets({
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
    this.left = 0,
  });

  const PluginInsets.zero() : this();

  final double top;
  final double right;
  final double bottom;
  final double left;

  Map<String, double> toJson() => <String, double>{
    'top': top,
    'right': right,
    'bottom': bottom,
    'left': left,
  };
}

/// The current image, reduced to the v1 snapshot field set.
///
/// Deliberately excludes album ids, paths, checksums, original file names,
/// live-photo video ids, and unrelated EXIF data.
class PluginImageSnapshot {
  const PluginImageSnapshot({
    required this.id,
    required this.type,
    this.livePhoto = false,
    this.width,
    this.height,
    this.aspectBucket,
    this.aspectLabel,
    this.mimeType,
    this.cached = false,
    this.exifDate,
    this.description,
    this.location,
    this.tags = const <String>[],
  });

  final String id;

  /// One of `photo`, `livePhoto`, or `video`.
  final String type;
  final bool livePhoto;
  final int? width;
  final int? height;

  /// The aspect bucket name, such as `sixteenNine`.
  final String? aspectBucket;

  /// The human-readable aspect label, such as `16:9`.
  final String? aspectLabel;
  final String? mimeType;

  /// Whether the image is available from the local cache (works offline).
  final bool cached;
  final DateTime? exifDate;
  final String? description;
  final String? location;
  final List<String> tags;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type,
    'livePhoto': livePhoto,
    'width': width,
    'height': height,
    'aspectBucket': aspectBucket,
    'aspectLabel': aspectLabel,
    'mimeType': mimeType,
    'cached': cached,
    'exifDate': exifDate?.toIso8601String(),
    'description': description,
    'location': location,
    'tags': List<String>.of(tags),
  };
}

/// The current slideshow/playback state.
class PluginPlaybackSnapshot {
  const PluginPlaybackSnapshot({
    required this.playing,
    required this.index,
    required this.total,
    required this.intervalSeconds,
    required this.progress,
    required this.muted,
    required this.slideshowRunning,
  });

  final bool playing;
  final int index;
  final int total;
  final int intervalSeconds;

  /// Elapsed fraction of the current interval, normally 0.0..1.0.
  final double progress;
  final bool muted;
  final bool slideshowRunning;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'playing': playing,
    'index': index,
    'total': total,
    'intervalSeconds': intervalSeconds,
    'progress': progress,
    'muted': muted,
    'slideshowRunning': slideshowRunning,
  };
}

/// Background media (for example Spotify), or null when nothing is playing.
class PluginMediaSnapshot {
  const PluginMediaSnapshot({
    required this.hasSession,
    this.title,
    this.artist,
    this.album,
    this.packageName,
    required this.playing,
    required this.canPrevious,
    required this.canNext,
    this.positionSeconds,
    this.durationSeconds,
  });

  final bool hasSession;
  final String? title;
  final String? artist;
  final String? album;
  final String? packageName;
  final bool playing;
  final bool canPrevious;
  final bool canNext;
  final double? positionSeconds;
  final double? durationSeconds;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'hasSession': hasSession,
    'title': title,
    'artist': artist,
    'album': album,
    'packageName': packageName,
    'playing': playing,
    'canPrevious': canPrevious,
    'canNext': canNext,
    'positionSeconds': positionSeconds,
    'durationSeconds': durationSeconds,
  };
}

/// Current weather, or null when the host has no fresh data.
class PluginWeatherSnapshot {
  const PluginWeatherSnapshot({
    required this.temperature,
    required this.unit,
    required this.code,
    required this.description,
    required this.locationLabel,
    required this.fetchedAt,
  });

  final double temperature;
  final String unit;
  final int code;
  final String description;
  final String locationLabel;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'temperature': temperature,
    'unit': unit,
    'code': code,
    'description': description,
    'locationLabel': locationLabel,
    'fetchedAt': fetchedAt.toIso8601String(),
  };
}

/// Plain, immutable host inputs for [PluginSnapshotBuilder].
class PluginSnapshotSource {
  const PluginSnapshotSource({
    required this.appVersion,
    required this.pluginApiVersion,
    required this.locale,
    required this.timeZone,
    required this.theme,
    required this.viewportWidth,
    required this.viewportHeight,
    this.safeArea = const PluginInsets.zero(),
    required this.nightMode,
    required this.now,
    this.weather,
    required this.playback,
    this.media,
    this.image,
    this.config = const <String, dynamic>{},
    required this.placement,
    required this.enabled,
    required this.visible,
  });

  final String appVersion;
  final int pluginApiVersion;
  final String locale;
  final String timeZone;
  final String theme;
  final double viewportWidth;
  final double viewportHeight;
  final PluginInsets safeArea;
  final bool nightMode;
  final DateTime now;
  final PluginWeatherSnapshot? weather;
  final PluginPlaybackSnapshot playback;
  final PluginMediaSnapshot? media;
  final PluginImageSnapshot? image;
  final Map<String, dynamic> config;
  final PluginPlacement placement;
  final bool enabled;
  final bool visible;
}

/// Builds a plugin state snapshot filtered to the manifest's declared inputs.
///
/// `app` and `time` are always present. Every other section is present only
/// when the manifest declares the matching [PluginInput]; a declared section
/// whose source value is null is emitted as null rather than omitted.
abstract final class PluginSnapshotBuilder {
  static Map<String, dynamic> build({
    required PluginManifest manifest,
    required PluginSnapshotSource source,
  }) {
    final snapshot = <String, dynamic>{
      'app': _app(source),
      'time': _time(source.now),
    };

    if (manifest.inputs.contains(PluginInput.weather)) {
      snapshot['weather'] = source.weather?.toJson();
    }
    if (manifest.inputs.contains(PluginInput.playback)) {
      snapshot['playback'] = source.playback.toJson();
    }
    if (manifest.inputs.contains(PluginInput.media)) {
      snapshot['media'] = source.media?.toJson();
    }
    if (manifest.inputs.contains(PluginInput.image)) {
      snapshot['image'] = source.image?.toJson();
    }
    if (manifest.inputs.contains(PluginInput.config)) {
      snapshot['config'] = Map<String, dynamic>.of(source.config);
    }
    if (manifest.inputs.contains(PluginInput.placement)) {
      snapshot['placement'] = _placement(source.placement);
    }

    return snapshot;
  }

  static Map<String, dynamic> _app(PluginSnapshotSource source) {
    return <String, dynamic>{
      'version': source.appVersion,
      'pluginApiVersion': source.pluginApiVersion,
      'locale': source.locale,
      'timeZone': source.timeZone,
      'theme': source.theme,
      'viewport': <String, double>{
        'width': source.viewportWidth,
        'height': source.viewportHeight,
      },
      'safeArea': source.safeArea.toJson(),
      'nightMode': source.nightMode,
      'enabled': source.enabled,
      'visible': source.visible,
    };
  }

  static Map<String, dynamic> _time(DateTime now) {
    return <String, dynamic>{
      'iso': now.toIso8601String(),
      'epochMs': now.millisecondsSinceEpoch,
      'utcOffsetMinutes': now.timeZoneOffset.inMinutes,
      'year': now.year,
      'month': now.month,
      'day': now.day,
      'hour': now.hour,
      'minute': now.minute,
      'second': now.second,
      'weekday': now.weekday,
    };
  }

  static Map<String, dynamic> _placement(PluginPlacement placement) {
    return <String, dynamic>{
      'anchor': placement.anchor.jsonName,
      'x': placement.x,
      'y': placement.y,
      'width': placement.width,
      'height': placement.height,
      'zOrder': placement.zOrder,
      'showDuringNight': placement.showDuringNight,
    };
  }
}
