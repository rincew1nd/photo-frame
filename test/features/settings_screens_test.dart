import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/cache/cache_store.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/features/settings/automation_settings_screen.dart';
import 'package:photoframe/features/settings/cache_settings_screen.dart';
import 'package:photoframe/features/settings/playback_settings_screen.dart';
import 'package:photoframe/features/settings/plugins_settings_screen.dart';
import 'package:photoframe/features/settings/slideshow_settings_screen.dart';
import 'package:photoframe/l10n/app_localizations.dart';

Future<void> _pump(
  WidgetTester tester, {
  required InMemorySettingsRepository repository,
  required Widget screen,
  CacheStore? cacheStore,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repository),
        cacheStoreProvider.overrideWithValue(cacheStore ?? MemoryCacheStore()),
        appLoggerProvider.overrideWithValue(AppLogger()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('playback screen saves playback settings', (tester) async {
    final repository = InMemorySettingsRepository();
    await _pump(
      tester,
      repository: repository,
      screen: const PlaybackSettingsScreen(),
    );

    tester.widget<Slider>(find.byType(Slider)).onChanged!(20);
    await tester.pumpAndSettle();
    expect((await repository.load()).playback.intervalSeconds, 20);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Shuffle'));
    await tester.pumpAndSettle();
    expect((await repository.load()).playback.shuffle, isFalse);

    await tester.tap(find.byType(DropdownButton<TransitionType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zoom').last);
    await tester.pumpAndSettle();
    expect((await repository.load()).playback.transition, TransitionType.zoom);

    await tester.tap(find.byKey(const ValueKey<String>('video-mode-off')));
    await tester.pumpAndSettle();
    expect(
      (await repository.load()).playback.videoPlaybackMode,
      VideoPlaybackMode.off,
    );

    expect(
      tester
          .widget<RadioListTile<VideoPlaybackMode>>(
            find.byKey(const ValueKey<String>('video-mode-full')),
          )
          .enabled,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey<String>('video-mode-full')));
    await tester.pumpAndSettle();
    expect(
      (await repository.load()).playback.videoPlaybackMode,
      VideoPlaybackMode.full,
    );

    final loopRadio = find.byKey(
      const ValueKey<String>('live-photo-mode-loop'),
    );
    // ponytail: production leaves `enabled` null (resolved by RadioGroup),
    // so assert "not disabled" rather than requiring an explicit true.
    expect(
      tester.widget<RadioListTile<LivePhotoMode>>(loopRadio).enabled,
      isNot(false),
    );
    await tester.ensureVisible(loopRadio);
    await tester.tap(loopRadio);
    await tester.pumpAndSettle();
    expect(
      (await repository.load()).playback.livePhotoMode,
      LivePhotoMode.loop,
    );

    final bounceRadio = find.byKey(
      const ValueKey<String>('live-photo-mode-bounce'),
    );
    expect(
      tester.widget<RadioListTile<LivePhotoMode>>(bounceRadio).enabled,
      isNot(false),
    );
    await tester.ensureVisible(bounceRadio);
    await tester.tap(bounceRadio);
    await tester.pumpAndSettle();
    expect(
      (await repository.load()).playback.livePhotoMode,
      LivePhotoMode.bounce,
    );

    final muteSwitch = find.widgetWithText(
      SwitchListTile,
      'Mute video/live audio',
    );
    expect(tester.widget<SwitchListTile>(muteSwitch).onChanged, isNotNull);
    expect((await repository.load()).playback.muted, isTrue);
    await tester.tap(muteSwitch);
    await tester.pumpAndSettle();
    expect((await repository.load()).playback.muted, isFalse);
  });

  testWidgets('slideshow screen saves the default profile', (tester) async {
    final repository = InMemorySettingsRepository();
    await _pump(
      tester,
      repository: repository,
      screen: const SlideshowSettingsScreen(),
    );

    await tester.tap(find.text('Cover'));
    await tester.pumpAndSettle();
    expect((await repository.load()).defaultProfile.fit, ImageFit.cover);

    await tester.tap(find.text('Ambient glow'));
    await tester.pumpAndSettle();
    expect(
      (await repository.load()).defaultProfile.adaptiveBackground,
      AdaptiveBackground.ambientGlow,
    );

    await tester.tap(find.widgetWithText(SwitchListTile, 'Image motion'));
    await tester.pumpAndSettle();
    expect((await repository.load()).defaultProfile.imageMotion, isFalse);

    tester.widget<Slider>(find.byType(Slider)).onChanged!(40);
    await tester.pumpAndSettle();
    expect((await repository.load()).defaultProfile.panStrength, 40);

    expect(
      find.widgetWithText(ListTile, 'Customizations'),
      findsOneWidget,
    );
  });

  testWidgets('automation screen saves automation and night mode', (
    tester,
  ) async {
    final repository = InMemorySettingsRepository();
    await _pump(
      tester,
      repository: repository,
      screen: const AutomationSettingsScreen(),
    );

    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Start on boot'),
          )
          .onChanged,
      isNull,
    );

    await tester.tap(find.widgetWithText(SwitchListTile, 'Fullscreen'));
    await tester.pumpAndSettle();
    expect((await repository.load()).automation.fullscreen, isTrue);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Keep screen on'));
    await tester.pumpAndSettle();
    expect((await repository.load()).display.keepScreenOn, isFalse);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Enable night mode'));
    await tester.pumpAndSettle();
    expect((await repository.load()).nightMode.enabled, isTrue);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Pause slideshow'));
    await tester.pumpAndSettle();
    expect((await repository.load()).nightMode.pauseSlideshow, isFalse);

    expect(find.widgetWithText(ListTile, 'Start time'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'End time'), findsOneWidget);
  });

  testWidgets('cache screen shows stats and saves quota and prefetch', (
    tester,
  ) async {
    final store = MemoryCacheStore();
    final cachedAt = DateTime.utc(2026, 1, 1);
    await store.upsertAsset(
      CachedAsset(
        id: 'photo-1',
        albumIds: <String>{'album-1'},
        sizeBytes: 1024,
        cachedAt: cachedAt,
        lastAccessedAt: cachedAt,
      ),
    );
    await store.upsertAsset(
      CachedAsset(
        id: 'video-1',
        albumIds: <String>{'album-1'},
        type: MediaKind.video,
        sizeBytes: 2048,
        cachedAt: cachedAt,
        lastAccessedAt: cachedAt,
      ),
    );

    final repository = InMemorySettingsRepository();
    await _pump(
      tester,
      repository: repository,
      screen: const CacheSettingsScreen(),
      cacheStore: store,
    );

    for (final text in <String>[
      'Images',
      'Videos',
      'Total',
      'Sync now',
      'Clear cache',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('1 · 1.0 KB'), findsOneWidget);
    expect(find.text('1 · 2.0 KB'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '2048');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      (await repository.load()).cache.quotaBytes,
      2048 * 1024 * 1024,
    );

    tester.widget<Slider>(find.byType(Slider).last).onChanged!(5);
    await tester.pumpAndSettle();
    expect((await repository.load()).cache.prefetchCount, 5);

    await tester.ensureVisible(find.text('Clear cache'));
    await tester.tap(find.text('Clear cache'));
    await tester.pump();
    expect(find.text('Clear'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('plugins screen saves overlays and weather location', (
    tester,
  ) async {
    final repository = InMemorySettingsRepository();
    await _pump(
      tester,
      repository: repository,
      screen: const PluginsSettingsScreen(),
    );

    await tester.tap(find.widgetWithText(SwitchListTile, 'Weather'));
    await tester.pumpAndSettle();
    expect((await repository.load()).overlays.weather, isTrue);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Metadata'));
    await tester.pumpAndSettle();
    expect((await repository.load()).overlays.metadata, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('weather-location')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Berlin');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await repository.load()).overlays.weatherLocationLabel, 'Berlin');

    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Add plugin'))
          .enabled,
      isFalse,
    );
  });
}
