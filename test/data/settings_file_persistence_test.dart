import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/platform/paths.dart';

const AppSettings _updated = AppSettings(
  playback: PlaybackSettings(
    intervalSeconds: 42,
    livePhotoMode: LivePhotoMode.loop,
  ),
  defaultProfile: AspectProfile(fit: ImageFit.cover, panStrength: 0),
  overlays: OverlaySettings(clock: false),
);

void main() {
  late Directory temporary;
  late InMemoryAppPaths paths;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('photoframe_file_');
    paths = InMemoryAppPaths(temporary);
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('save is durable before its returned future is awaited', () async {
    final support = await paths.support();
    final file = File(p.join(support.path, 'settings.json'));
    final repository = FileSettingsRepository(paths);
    await repository.load();

    unawaited(repository.save(_updated));

    expect(file.existsSync(), isTrue);
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final profile = decoded['defaultProfile'] as Map<String, dynamic>;
    expect(profile['fit'], 'cover');
    expect(profile.containsKey('livePhotoMode'), isFalse);
    expect(profile['panStrength'], 0);
    final playback = decoded['playback'] as Map<String, dynamic>;
    expect(playback['intervalSeconds'], 42);
    expect(playback['livePhotoMode'], 'loop');
    expect((decoded['overlays'] as Map<String, dynamic>)['clock'], isFalse);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test(
    'concurrent saves keep the last value and leave no temp files',
    () async {
      final repository = FileSettingsRepository(paths);
      final first = repository.save(
        const AppSettings(playback: PlaybackSettings(intervalSeconds: 11)),
      );
      final second = repository.save(
        const AppSettings(playback: PlaybackSettings(intervalSeconds: 22)),
      );
      await Future.wait(<Future<void>>[first, second]);

      final restarted = FileSettingsRepository(paths);
      expect((await restarted.load()).playback.intervalSeconds, 22);

      final support = await paths.support();
      final leftovers = await support
          .list()
          .where((entity) => entity.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    },
  );

  test('saved settings survive a simulated restart', () async {
    final repository = FileSettingsRepository(paths);
    await repository.load();
    await repository.save(_updated);

    final restarted = FileSettingsRepository(paths);
    final loaded = await restarted.load();

    expect(loaded.defaultProfile.fit, ImageFit.cover);
    expect(loaded.playback.livePhotoMode, LivePhotoMode.loop);
    expect(loaded.defaultProfile.panStrength, 0);
    expect(loaded.playback.intervalSeconds, 42);
    expect(loaded.overlays.clock, isFalse);
  });

  test('controller save is durable and survives a restart', () async {
    final repository = FileSettingsRepository(paths);
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(settingsControllerProvider.future);
    final notifier = container.read(settingsControllerProvider.notifier);

    unawaited(
      notifier.save(
        (settings) => settings.copyWith(
          playback: settings.playback.copyWith(
            intervalSeconds: 42,
            livePhotoMode: LivePhotoMode.loop,
          ),
          defaultProfile: settings.defaultProfile.copyWith(
            fit: ImageFit.cover,
            panStrength: 0,
          ),
        ),
      ),
    );

    final support = await paths.support();
    final file = File(p.join(support.path, 'settings.json'));
    expect(file.existsSync(), isTrue);
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final profile = decoded['defaultProfile'] as Map<String, dynamic>;
    expect(profile['fit'], 'cover');
    expect(profile.containsKey('livePhotoMode'), isFalse);
    expect(profile['panStrength'], 0);
    final playback = decoded['playback'] as Map<String, dynamic>;
    expect(playback['livePhotoMode'], 'loop');

    await notifier.flush();
    final restarted = FileSettingsRepository(paths);
    final loaded = await restarted.load();
    expect(loaded.playback.intervalSeconds, 42);
    expect(loaded.defaultProfile.fit, ImageFit.cover);
    expect(loaded.playback.livePhotoMode, LivePhotoMode.loop);
    expect(loaded.defaultProfile.panStrength, 0);
  });
}
