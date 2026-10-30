import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/platform/paths.dart';

void main() {
  late Directory temporary;
  late InMemoryAppPaths paths;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('photoframe_settings_');
    paths = InMemoryAppPaths(temporary);
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('defaults roundtrip through the file repository', () async {
    final repository = FileSettingsRepository(paths);
    const defaults = AppSettings();

    await repository.save(defaults);
    final loaded = await repository.load();

    expect(loaded.toJson(), equals(defaults.toJson()));
    expect(loaded.schemaVersion, AppSettings.currentSchemaVersion);

    final support = await paths.support();
    final file = File(p.join(support.path, 'settings.json'));
    expect(await file.exists(), isTrue);
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test('corrupt settings fall back to defaults and are backed up', () async {
    final repository = FileSettingsRepository(paths);
    final support = await paths.support();
    final file = File(p.join(support.path, 'settings.json'));
    await file.writeAsString('{not valid json');

    final loaded = await repository.load();

    expect(loaded.toJson(), equals(const AppSettings().toJson()));
    final entries = await support.list().toList();
    expect(
      entries.any(
        (entity) =>
            entity is File &&
            p.basename(entity.path).startsWith('settings.corrupt.'),
      ),
      isTrue,
    );
  });

  test('save writes atomically', () async {
    final repository = FileSettingsRepository(paths);
    final settings = const AppSettings().copyWith(
      playback: const PlaybackSettings(intervalSeconds: 42),
    );
    await repository.save(settings);

    final support = await paths.support();
    final file = File(p.join(support.path, 'settings.json'));
    expect(await file.exists(), isTrue);
    expect(await File('${file.path}.tmp').exists(), isFalse);
    expect((await repository.load()).playback.intervalSeconds, 42);
  });

  test('migration from empty and older maps applies defaults', () {
    final fromEmpty = migrate(<String, dynamic>{});
    expect(fromEmpty.schemaVersion, AppSettings.currentSchemaVersion);
    expect(fromEmpty.playback.intervalSeconds, 10);
    expect(fromEmpty.filters.selectedAssetIds, isEmpty);
    expect(fromEmpty.customizations, isEmpty);

    final fromZero = migrate(<String, dynamic>{'schemaVersion': 0});
    expect(fromZero.schemaVersion, AppSettings.currentSchemaVersion);
    expect(fromZero.display.theme, 'system');
    expect(fromZero.playback.videoPlaybackMode, VideoPlaybackMode.staticPreview);
    expect(fromZero.playback.livePhotoMode, LivePhotoMode.off);
    expect(fromZero.defaultProfile.imageMotion, isTrue);
    expect(fromZero.defaultProfile.adaptiveBackground, AdaptiveBackground.none);
    expect(fromZero.automation.fullscreen, isFalse);

    final clamped = migrate(<String, dynamic>{
      'schemaVersion': 0,
      'playback': <String, dynamic>{'intervalSeconds': 99999},
    });
    expect(clamped.playback.intervalSeconds, 3600);
  });

  test('migrates v1 aspect overrides into customizations', () {
    final migrated = migrate(<String, dynamic>{
      'schemaVersion': 1,
      'playback': <String, dynamic>{'intervalSeconds': 5},
      'display': <String, dynamic>{'imageMotion': false},
      'defaultProfile': <String, dynamic>{
        'fit': 'cover',
        'livePhotoMode': 'loop',
      },
      'filters': <String, dynamic>{
        'enabledTypes': <String>['photo'],
        'selectedAssetIds': <String>['asset-1', 'asset-2'],
      },
      'aspectOverrides': <String, dynamic>{
        'sixteenNine': <String, dynamic>{'fit': 'cover', 'panStrength': 10},
        'oneToOne': <String, dynamic>{'fit': 'contain'},
      },
      'automation': <String, dynamic>{'kiosk': true, 'launcherMode': true},
    });

    expect(migrated.schemaVersion, 2);
    expect(migrated.playback.livePhotoMode, LivePhotoMode.loop);
    expect(
      migrated.playback.videoPlaybackMode,
      VideoPlaybackMode.staticPreview,
    );
    expect(migrated.defaultProfile.imageMotion, isFalse);
    expect(migrated.defaultProfile.adaptiveBackground, AdaptiveBackground.none);
    expect(migrated.automation.fullscreen, isFalse);
    expect(migrated.filters.selectedAssetIds, <String>{'asset-1', 'asset-2'});

    expect(migrated.customizations, hasLength(2));
    final first = migrated.customizations.first;
    expect(first.id, 'aspect-oneToOne');
    expect(first.name, '1:1 override');
    expect(first.aspects, <AspectBucket>{AspectBucket.oneToOne});
    expect(first.mediaTypes, isEmpty);
    expect(first.profile.fit, ImageFit.contain);
    expect(first.profile.imageMotion, isFalse);
    expect(first.profile.adaptiveBackground, AdaptiveBackground.none);

    final second = migrated.customizations.last;
    expect(second.id, 'aspect-sixteenNine');
    expect(second.name, '16:9 override');
    expect(second.aspects, <AspectBucket>{AspectBucket.sixteenNine});
    expect(second.profile.fit, ImageFit.cover);
    expect(second.profile.panStrength, 10);
    expect(second.profile.imageMotion, isFalse);

    for (final customization in migrated.customizations) {
      expect(
        customization.profile.toJson().containsKey('livePhotoMode'),
        isFalse,
      );
    }

    final json = migrated.toJson();
    expect(json.containsKey('aspectOverrides'), isFalse);
    final filters = json['filters'] as Map<String, dynamic>;
    expect(filters.containsKey('enabledTypes'), isFalse);
    expect(filters.containsKey('enabledAspects'), isFalse);
    final display = json['display'] as Map<String, dynamic>;
    expect(display.containsKey('imageMotion'), isFalse);
    final automation = json['automation'] as Map<String, dynamic>;
    expect(automation.containsKey('kiosk'), isFalse);
    expect(automation.containsKey('launcherMode'), isFalse);
    expect(automation.containsKey('updateChecks'), isFalse);
    final defaultProfile = json['defaultProfile'] as Map<String, dynamic>;
    expect(defaultProfile.containsKey('livePhotoMode'), isFalse);
  });

  test('v2 settings with legacy keys still load and ignore them', () {
    final loaded = migrate(<String, dynamic>{
      'schemaVersion': 2,
      'filters': <String, dynamic>{
        'enabledTypes': <String>['photo'],
        'enabledAspects': <String>['sixteenNine'],
        'selectedAssetIds': <String>['asset-1'],
      },
      'display': <String, dynamic>{'imageMotion': false},
      'defaultProfile': <String, dynamic>{'livePhotoMode': 'loop'},
      'aspectOverrides': <String, dynamic>{
        'sixteenNine': <String, dynamic>{'fit': 'cover'},
      },
      'automation': <String, dynamic>{
        'kiosk': true,
        'launcherMode': true,
        'updateChecks': false,
      },
    });

    expect(loaded.schemaVersion, 2);
    expect(loaded.filters.selectedAssetIds, <String>{'asset-1'});
    expect(loaded.playback.livePhotoMode, LivePhotoMode.off);
    expect(loaded.defaultProfile.imageMotion, isTrue);
    expect(loaded.automation.fullscreen, isFalse);
    expect(loaded.customizations, isEmpty);
  });

  test('round trips new fields and customizations through JSON', () {
    const settings = AppSettings(
      playback: PlaybackSettings(
        videoPlaybackMode: VideoPlaybackMode.full,
        livePhotoMode: LivePhotoMode.loop,
      ),
      defaultProfile: AspectProfile(
        adaptiveBackground: AdaptiveBackground.blurredCover,
        imageMotion: false,
      ),
      automation: AutomationSettings(fullscreen: true),
      customizations: <CustomizationProfile>[
        CustomizationProfile(
          id: 'custom-1',
          name: 'Videos',
          aspects: <AspectBucket>{AspectBucket.sixteenNine},
          mediaTypes: <MediaKind>{MediaKind.video},
          profile: AspectProfile(fit: ImageFit.cover),
        ),
      ],
    );

    final decoded = AppSettings.fromJson(settings.toJson());

    expect(decoded.toJson(), equals(settings.toJson()));
    expect(decoded.playback.videoPlaybackMode, VideoPlaybackMode.full);
    expect(decoded.playback.livePhotoMode, LivePhotoMode.loop);
    expect(
      decoded.defaultProfile.adaptiveBackground,
      AdaptiveBackground.blurredCover,
    );
    expect(decoded.defaultProfile.imageMotion, isFalse);
    expect(decoded.automation.fullscreen, isTrue);
    expect(decoded.customizations.single.id, 'custom-1');
    expect(decoded.customizations.single.mediaTypes, <MediaKind>{
      MediaKind.video,
    });
  });
}
