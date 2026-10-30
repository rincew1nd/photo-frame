import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/settings/settings_repository.dart';

class _DelayedSettingsRepository implements SettingsRepository {
  _DelayedSettingsRepository([AppSettings initial = const AppSettings()])
    : _settings = initial;

  AppSettings _settings;
  final List<AppSettings> saved = <AppSettings>[];

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    saved.add(settings);
    _settings = settings;
  }
}

void main() {
  test('serializes rapid saves and keeps the last interval', () async {
    final repository = _DelayedSettingsRepository();
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(settingsControllerProvider.future);
    final notifier = container.read(settingsControllerProvider.notifier);

    final first = notifier.save(
      (settings) => settings.copyWith(
        playback: settings.playback.copyWith(intervalSeconds: 5),
      ),
    );
    final second = notifier.save(
      (settings) => settings.copyWith(
        playback: settings.playback.copyWith(intervalSeconds: 6),
      ),
    );

    expect(
      container
          .read(settingsControllerProvider)
          .value
          ?.playback
          .intervalSeconds,
      6,
    );

    await Future.wait(<Future<void>>[first, second]);

    expect(repository.saved.last.playback.intervalSeconds, 6);
    expect((await repository.load()).playback.intervalSeconds, 6);
    expect(
      container
          .read(settingsControllerProvider)
          .value
          ?.playback
          .intervalSeconds,
      6,
    );
  });
}
