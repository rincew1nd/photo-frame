enum AuthMode {
  apiKey,
  oauth;

  static AuthMode fromJson(Object? value) {
    return _enumByName(AuthMode.values, value, AuthMode.apiKey);
  }
}

enum TransitionType {
  fade,
  slide,
  zoom,
  none;

  static TransitionType fromJson(Object? value) {
    return _enumByName(TransitionType.values, value, TransitionType.fade);
  }
}

enum MediaKind {
  photo,
  livePhoto,
  video;

  static MediaKind? fromJson(Object? value) {
    if (value is String) {
      for (final kind in MediaKind.values) {
        if (kind.name == value) {
          return kind;
        }
      }
    }
    return null;
  }
}

enum AspectBucket {
  oneToOne('1:1', 1.0),
  fourThree('4:3', 4 / 3),
  threeTwo('3:2', 3 / 2),
  sixteenNine('16:9', 16 / 9),
  panorama('Panorama', 3.0),
  other('Other', 0.0);

  const AspectBucket(this.label, this.aspectRatio);

  final String label;
  final double aspectRatio;

  String get jsonName => name;

  static AspectBucket? fromJson(Object? value) {
    if (value is String) {
      for (final bucket in AspectBucket.values) {
        if (bucket.name == value || bucket.jsonName == value) {
          return bucket;
        }
      }
    }
    return null;
  }
}

enum ImageFit {
  contain,
  cover;

  static ImageFit fromJson(Object? value) {
    return _enumByName(ImageFit.values, value, ImageFit.contain);
  }

  String get jsonName => name;
}

enum LivePhotoMode {
  off,
  live,
  loop,
  bounce;

  static LivePhotoMode fromJson(Object? value) {
    return _enumByName(LivePhotoMode.values, value, LivePhotoMode.off);
  }

  String get jsonName => name;
}

enum VideoPlaybackMode {
  off,
  staticPreview,
  full,
  speedUp,
  highlights,
  slice;

  static VideoPlaybackMode fromJson(Object? value) {
    return _enumByName(
      VideoPlaybackMode.values,
      value,
      VideoPlaybackMode.staticPreview,
    );
  }

  String get jsonName => name;
}

enum AdaptiveBackground {
  none,
  ambientGlow,
  blurredCover;

  static AdaptiveBackground fromJson(Object? value) {
    return _enumByName(AdaptiveBackground.values, value, AdaptiveBackground.none);
  }

  String get jsonName => name;
}

T _enumByName<T extends Enum>(List<T> values, Object? value, T fallback) {
  if (value is String) {
    for (final item in values) {
      if (item.name == value) {
        return item;
      }
    }
  }
  return fallback;
}

Map<String, dynamic> _jsonMap(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return <String, dynamic>{};
}

bool _asBool(Object? value, bool fallback) {
  return value is bool ? value : fallback;
}

String _asString(Object? value, String fallback) {
  return value is String ? value : fallback;
}

int _asInt(Object? value, int fallback, {int? min, int? max}) {
  final parsed = value is num
      ? value.toInt()
      : value is String
      ? int.tryParse(value)
      : null;
  if (parsed == null) {
    return fallback;
  }
  var result = parsed;
  if (min != null && result < min) {
    result = min;
  }
  if (max != null && result > max) {
    result = max;
  }
  return result;
}

double? _asNullableDouble(Object? value, {double? min, double? max}) {
  final parsed = value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value)
      : null;
  if (parsed == null) {
    return null;
  }
  var result = parsed;
  if (min != null && result < min) {
    result = min;
  }
  if (max != null && result > max) {
    result = max;
  }
  return result;
}

String? _asNullableString(Object? value) {
  return value is String && value.isNotEmpty ? value : null;
}

DateTime? _asNullableDateTime(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

Set<String> _asStringSet(Object? value, Set<String> fallback) {
  if (value is List) {
    return value.whereType<String>().toSet();
  }
  if (value is Set) {
    return value.whereType<String>().toSet();
  }
  return fallback;
}

class ConnectionSettings {
  const ConnectionSettings({
    this.serverUrl,
    this.authMode = AuthMode.apiKey,
    this.userId,
    this.userEmail,
    this.userName,
    this.permissions = const <String, String>{},
    this.albumIds = const <String>{},
    this.lastConnectedAt,
  });

  final String? serverUrl;
  final AuthMode authMode;
  final String? userId;
  final String? userEmail;
  final String? userName;
  final Map<String, String> permissions;
  final Set<String> albumIds;
  final DateTime? lastConnectedAt;

  ConnectionSettings copyWith({
    String? serverUrl,
    AuthMode? authMode,
    String? userId,
    String? userEmail,
    String? userName,
    Map<String, String>? permissions,
    Set<String>? albumIds,
    DateTime? lastConnectedAt,
  }) {
    return ConnectionSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      authMode: authMode ?? this.authMode,
      userId: userId ?? this.userId,
      userEmail: userEmail ?? this.userEmail,
      userName: userName ?? this.userName,
      permissions: permissions ?? this.permissions,
      albumIds: albumIds ?? this.albumIds,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'serverUrl': serverUrl,
    'authMode': authMode.name,
    'userId': userId,
    'userEmail': userEmail,
    'userName': userName,
    'permissions': permissions,
    'albumIds': albumIds.toList(),
    'lastConnectedAt': lastConnectedAt?.toIso8601String(),
  };

  factory ConnectionSettings.fromJson(Map<String, dynamic> json) {
    final permissions = <String, String>{};
    for (final entry in _jsonMap(json['permissions']).entries) {
      final value = entry.value;
      if (value is String) {
        permissions[entry.key] = value;
      }
    }
    return ConnectionSettings(
      serverUrl: _asNullableString(json['serverUrl']),
      authMode: AuthMode.fromJson(json['authMode']),
      userId: _asNullableString(json['userId']),
      userEmail: _asNullableString(json['userEmail']),
      userName: _asNullableString(json['userName']),
      permissions: permissions,
      albumIds: _asStringSet(json['albumIds'], const <String>{}),
      lastConnectedAt: _asNullableDateTime(json['lastConnectedAt']),
    );
  }
}

class PlaybackSettings {
  const PlaybackSettings({
    this.intervalSeconds = 10,
    this.shuffle = true,
    this.transition = TransitionType.fade,
    this.muted = true,
    this.videoPlaybackMode = VideoPlaybackMode.staticPreview,
    this.livePhotoMode = LivePhotoMode.off,
  });

  final int intervalSeconds;
  final bool shuffle;
  final TransitionType transition;
  final bool muted;
  final VideoPlaybackMode videoPlaybackMode;
  final LivePhotoMode livePhotoMode;

  PlaybackSettings copyWith({
    int? intervalSeconds,
    bool? shuffle,
    TransitionType? transition,
    bool? muted,
    VideoPlaybackMode? videoPlaybackMode,
    LivePhotoMode? livePhotoMode,
  }) {
    return PlaybackSettings(
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      shuffle: shuffle ?? this.shuffle,
      transition: transition ?? this.transition,
      muted: muted ?? this.muted,
      videoPlaybackMode: videoPlaybackMode ?? this.videoPlaybackMode,
      livePhotoMode: livePhotoMode ?? this.livePhotoMode,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'intervalSeconds': intervalSeconds,
    'shuffle': shuffle,
    'transition': transition.name,
    'muted': muted,
    'videoPlaybackMode': videoPlaybackMode.jsonName,
    'livePhotoMode': livePhotoMode.jsonName,
  };

  factory PlaybackSettings.fromJson(Map<String, dynamic> json) {
    return PlaybackSettings(
      intervalSeconds: _asInt(
        json['intervalSeconds'],
        10,
        min: 1,
        max: 3600,
      ),
      shuffle: _asBool(json['shuffle'], true),
      transition: TransitionType.fromJson(json['transition']),
      muted: _asBool(json['muted'], true),
      videoPlaybackMode: VideoPlaybackMode.fromJson(json['videoPlaybackMode']),
      livePhotoMode: LivePhotoMode.fromJson(json['livePhotoMode']),
    );
  }
}

class FilterSettings {
  const FilterSettings({this.selectedAssetIds = const <String>{}});

  final Set<String> selectedAssetIds;

  FilterSettings copyWith({Set<String>? selectedAssetIds}) {
    return FilterSettings(
      selectedAssetIds: selectedAssetIds ?? this.selectedAssetIds,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'selectedAssetIds': selectedAssetIds.toList(),
  };

  factory FilterSettings.fromJson(Map<String, dynamic> json) {
    return FilterSettings(
      selectedAssetIds: _asStringSet(
        json['selectedAssetIds'],
        const <String>{},
      ),
    );
  }
}

class AspectProfile {
  const AspectProfile({
    this.fit = ImageFit.contain,
    this.adaptiveBackground = AdaptiveBackground.none,
    this.imageMotion = true,
    int panStrength = 0,
  }) : panStrength = panStrength < 0 ? 0 : (panStrength > 100 ? 100 : panStrength);

  final ImageFit fit;
  final AdaptiveBackground adaptiveBackground;
  final bool imageMotion;
  final int panStrength;

  AspectProfile copyWith({
    ImageFit? fit,
    AdaptiveBackground? adaptiveBackground,
    bool? imageMotion,
    int? panStrength,
  }) {
    return AspectProfile(
      fit: fit ?? this.fit,
      adaptiveBackground: adaptiveBackground ?? this.adaptiveBackground,
      imageMotion: imageMotion ?? this.imageMotion,
      panStrength: panStrength ?? this.panStrength,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'fit': fit.jsonName,
    'adaptiveBackground': adaptiveBackground.jsonName,
    'imageMotion': imageMotion,
    'panStrength': panStrength,
  };

  factory AspectProfile.fromJson(Map<String, dynamic> json) {
    return AspectProfile(
      fit: ImageFit.fromJson(json['fit']),
      adaptiveBackground: AdaptiveBackground.fromJson(
        json['adaptiveBackground'],
      ),
      imageMotion: _asBool(json['imageMotion'], true),
      panStrength: _asInt(json['panStrength'], 0, min: 0, max: 100),
    );
  }
}

class CustomizationProfile {
  const CustomizationProfile({
    this.id = '',
    this.name = '',
    this.aspects = const <AspectBucket>{},
    this.mediaTypes = const <MediaKind>{},
    this.profile = const AspectProfile(),
  });

  final String id;
  final String name;
  final Set<AspectBucket> aspects;
  final Set<MediaKind> mediaTypes;
  final AspectProfile profile;

  CustomizationProfile copyWith({
    String? id,
    String? name,
    Set<AspectBucket>? aspects,
    Set<MediaKind>? mediaTypes,
    AspectProfile? profile,
  }) {
    return CustomizationProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      aspects: aspects ?? this.aspects,
      mediaTypes: mediaTypes ?? this.mediaTypes,
      profile: profile ?? this.profile,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'aspects': aspects.map((bucket) => bucket.jsonName).toList(),
    'mediaTypes': mediaTypes.map((kind) => kind.name).toList(),
    'profile': profile.toJson(),
  };

  factory CustomizationProfile.fromJson(Map<String, dynamic> json) {
    final aspects = <AspectBucket>{};
    final rawAspects = json['aspects'];
    if (rawAspects is List) {
      for (final raw in rawAspects) {
        final bucket = AspectBucket.fromJson(raw);
        if (bucket != null) {
          aspects.add(bucket);
        }
      }
    }
    final mediaTypes = <MediaKind>{};
    final rawMediaTypes = json['mediaTypes'];
    if (rawMediaTypes is List) {
      for (final raw in rawMediaTypes) {
        final kind = MediaKind.fromJson(raw);
        if (kind != null) {
          mediaTypes.add(kind);
        }
      }
    }
    return CustomizationProfile(
      id: _asString(json['id'], ''),
      name: _asString(json['name'], ''),
      aspects: aspects,
      mediaTypes: mediaTypes,
      profile: AspectProfile.fromJson(_jsonMap(json['profile'])),
    );
  }

  bool matches(MediaKind? kind, AspectBucket? aspect) {
    if (mediaTypes.isNotEmpty &&
        (kind == null || !mediaTypes.contains(kind))) {
      return false;
    }
    if (aspects.isNotEmpty &&
        !aspects.contains(aspect ?? AspectBucket.other)) {
      return false;
    }
    return true;
  }
}

class DisplaySettings {
  const DisplaySettings({this.keepScreenOn = true, this.theme = 'system'});

  final bool keepScreenOn;
  final String theme;

  DisplaySettings copyWith({bool? keepScreenOn, String? theme}) {
    return DisplaySettings(
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      theme: theme ?? this.theme,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'keepScreenOn': keepScreenOn,
    'theme': theme,
  };

  factory DisplaySettings.fromJson(Map<String, dynamic> json) {
    return DisplaySettings(
      keepScreenOn: _asBool(json['keepScreenOn'], true),
      theme: _asString(json['theme'], 'system'),
    );
  }
}

class NightModeSettings {
  const NightModeSettings({
    this.enabled = false,
    this.startMinutes = 1320,
    this.endMinutes = 420,
    this.dimOpacity = 0.8,
    this.pauseSlideshow = true,
    this.hideOverlays = true,
  });

  final bool enabled;
  final int startMinutes;
  final int endMinutes;
  final double dimOpacity;
  final bool pauseSlideshow;
  final bool hideOverlays;

  NightModeSettings copyWith({
    bool? enabled,
    int? startMinutes,
    int? endMinutes,
    double? dimOpacity,
    bool? pauseSlideshow,
    bool? hideOverlays,
  }) {
    return NightModeSettings(
      enabled: enabled ?? this.enabled,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      dimOpacity: dimOpacity ?? this.dimOpacity,
      pauseSlideshow: pauseSlideshow ?? this.pauseSlideshow,
      hideOverlays: hideOverlays ?? this.hideOverlays,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'startMinutes': startMinutes,
    'endMinutes': endMinutes,
    'dimOpacity': dimOpacity,
    'pauseSlideshow': pauseSlideshow,
    'hideOverlays': hideOverlays,
  };

  factory NightModeSettings.fromJson(Map<String, dynamic> json) {
    return NightModeSettings(
      enabled: _asBool(json['enabled'], false),
      startMinutes: _asInt(json['startMinutes'], 1320, min: 0, max: 1439),
      endMinutes: _asInt(json['endMinutes'], 420, min: 0, max: 1439),
      dimOpacity: _asNullableDouble(
            json['dimOpacity'],
            min: 0,
            max: 1,
          ) ??
          0.8,
      pauseSlideshow: _asBool(json['pauseSlideshow'], true),
      hideOverlays: _asBool(json['hideOverlays'], true),
    );
  }
}

class CacheSettings {
  const CacheSettings({
    this.quotaBytes = 4 * 1024 * 1024 * 1024,
    this.prefetchCount = 3,
  });

  final int quotaBytes;
  final int prefetchCount;

  CacheSettings copyWith({int? quotaBytes, int? prefetchCount}) {
    return CacheSettings(
      quotaBytes: quotaBytes ?? this.quotaBytes,
      prefetchCount: prefetchCount ?? this.prefetchCount,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'quotaBytes': quotaBytes,
    'prefetchCount': prefetchCount,
  };

  factory CacheSettings.fromJson(Map<String, dynamic> json) {
    return CacheSettings(
      quotaBytes: _asInt(
        json['quotaBytes'],
        4 * 1024 * 1024 * 1024,
        min: 0,
        max: 1024 * 1024 * 1024 * 1024,
      ),
      prefetchCount: _asInt(json['prefetchCount'], 3, min: 0, max: 20),
    );
  }
}

class OverlaySettings {
  const OverlaySettings({
    this.clock = true,
    this.weather = false,
    this.metadata = false,
    this.weatherLatitude,
    this.weatherLongitude,
    this.weatherLocationLabel = '',
    this.weatherUnit = 'celsius',
  });

  final bool clock;
  final bool weather;
  final bool metadata;
  final double? weatherLatitude;
  final double? weatherLongitude;
  final String weatherLocationLabel;
  final String weatherUnit;

  OverlaySettings copyWith({
    bool? clock,
    bool? weather,
    bool? metadata,
    double? weatherLatitude,
    double? weatherLongitude,
    String? weatherLocationLabel,
    String? weatherUnit,
  }) {
    return OverlaySettings(
      clock: clock ?? this.clock,
      weather: weather ?? this.weather,
      metadata: metadata ?? this.metadata,
      weatherLatitude: weatherLatitude ?? this.weatherLatitude,
      weatherLongitude: weatherLongitude ?? this.weatherLongitude,
      weatherLocationLabel: weatherLocationLabel ?? this.weatherLocationLabel,
      weatherUnit: weatherUnit ?? this.weatherUnit,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'clock': clock,
    'weather': weather,
    'metadata': metadata,
    'weatherLatitude': weatherLatitude,
    'weatherLongitude': weatherLongitude,
    'weatherLocationLabel': weatherLocationLabel,
    'weatherUnit': weatherUnit,
  };

  factory OverlaySettings.fromJson(Map<String, dynamic> json) {
    return OverlaySettings(
      clock: _asBool(json['clock'], true),
      weather: _asBool(json['weather'], false),
      metadata: _asBool(json['metadata'], false),
      weatherLatitude: _asNullableDouble(
        json['weatherLatitude'],
        min: -90,
        max: 90,
      ),
      weatherLongitude: _asNullableDouble(
        json['weatherLongitude'],
        min: -180,
        max: 180,
      ),
      weatherLocationLabel: _asString(json['weatherLocationLabel'], ''),
      weatherUnit: _asString(json['weatherUnit'], 'celsius'),
    );
  }
}

class AutomationSettings {
  const AutomationSettings({
    this.startOnBoot = false,
    this.fullscreen = false,
  });

  final bool startOnBoot;
  final bool fullscreen;

  AutomationSettings copyWith({bool? startOnBoot, bool? fullscreen}) {
    return AutomationSettings(
      startOnBoot: startOnBoot ?? this.startOnBoot,
      fullscreen: fullscreen ?? this.fullscreen,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'startOnBoot': startOnBoot,
    'fullscreen': fullscreen,
  };

  factory AutomationSettings.fromJson(Map<String, dynamic> json) {
    return AutomationSettings(
      startOnBoot: _asBool(json['startOnBoot'], false),
      fullscreen: _asBool(json['fullscreen'], false),
    );
  }
}

/// Immutable tree of persisted application settings.
class AppSettings {
  const AppSettings({
    this.schemaVersion = currentSchemaVersion,
    this.connection = const ConnectionSettings(),
    this.playback = const PlaybackSettings(),
    this.filters = const FilterSettings(),
    this.defaultProfile = const AspectProfile(),
    this.customizations = const <CustomizationProfile>[],
    this.display = const DisplaySettings(),
    this.nightMode = const NightModeSettings(),
    this.cache = const CacheSettings(),
    this.overlays = const OverlaySettings(),
    this.automation = const AutomationSettings(),
  });

  static const int currentSchemaVersion = 2;

  final int schemaVersion;
  final ConnectionSettings connection;
  final PlaybackSettings playback;
  final FilterSettings filters;
  final AspectProfile defaultProfile;
  final List<CustomizationProfile> customizations;
  final DisplaySettings display;
  final NightModeSettings nightMode;
  final CacheSettings cache;
  final OverlaySettings overlays;
  final AutomationSettings automation;

  AppSettings copyWith({
    int? schemaVersion,
    ConnectionSettings? connection,
    PlaybackSettings? playback,
    FilterSettings? filters,
    AspectProfile? defaultProfile,
    List<CustomizationProfile>? customizations,
    DisplaySettings? display,
    NightModeSettings? nightMode,
    CacheSettings? cache,
    OverlaySettings? overlays,
    AutomationSettings? automation,
  }) {
    return AppSettings(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      connection: connection ?? this.connection,
      playback: playback ?? this.playback,
      filters: filters ?? this.filters,
      defaultProfile: defaultProfile ?? this.defaultProfile,
      customizations: customizations ?? this.customizations,
      display: display ?? this.display,
      nightMode: nightMode ?? this.nightMode,
      cache: cache ?? this.cache,
      overlays: overlays ?? this.overlays,
      automation: automation ?? this.automation,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'connection': connection.toJson(),
    'playback': playback.toJson(),
    'filters': filters.toJson(),
    'defaultProfile': defaultProfile.toJson(),
    'customizations': customizations
        .map((customization) => customization.toJson())
        .toList(),
    'display': display.toJson(),
    'nightMode': nightMode.toJson(),
    'cache': cache.toJson(),
    'overlays': overlays.toJson(),
    'automation': automation.toJson(),
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final customizations = <CustomizationProfile>[];
    final rawCustomizations = json['customizations'];
    if (rawCustomizations is List) {
      for (final raw in rawCustomizations) {
        customizations.add(CustomizationProfile.fromJson(_jsonMap(raw)));
      }
    }

    return AppSettings(
      schemaVersion: _asInt(
        json['schemaVersion'],
        currentSchemaVersion,
        min: 0,
      ),
      connection: ConnectionSettings.fromJson(_jsonMap(json['connection'])),
      playback: PlaybackSettings.fromJson(_jsonMap(json['playback'])),
      filters: FilterSettings.fromJson(_jsonMap(json['filters'])),
      defaultProfile: AspectProfile.fromJson(_jsonMap(json['defaultProfile'])),
      customizations: customizations,
      display: DisplaySettings.fromJson(_jsonMap(json['display'])),
      nightMode: NightModeSettings.fromJson(_jsonMap(json['nightMode'])),
      cache: CacheSettings.fromJson(_jsonMap(json['cache'])),
      overlays: OverlaySettings.fromJson(_jsonMap(json['overlays'])),
      automation: AutomationSettings.fromJson(_jsonMap(json['automation'])),
    );
  }
}
