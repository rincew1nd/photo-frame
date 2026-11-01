import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/cache/cache_store.dart';
import 'package:photoframe/data/plugins/plugin_store.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/features/settings/about_settings_screen.dart';
import 'package:photoframe/features/settings/automation_settings_screen.dart';
import 'package:photoframe/features/settings/cache_settings_screen.dart';
import 'package:photoframe/features/settings/playback_settings_screen.dart';
import 'package:photoframe/features/settings/plugins_settings_screen.dart';
import 'package:photoframe/features/settings/slideshow_settings_screen.dart';
import 'package:photoframe/l10n/app_localizations.dart';
import 'package:photoframe/platform/services.dart';

class _FakeAutostart implements AutostartService {
  @override
  Future<bool> get supported async => true;

  @override
  Future<void> setEnabled(bool enabled) async {}
}

Future<void> _pump(
  WidgetTester tester, {
  required InMemorySettingsRepository repository,
  required Widget screen,
  CacheStore? cacheStore,
  AppLogger? logger,
  List<Override> overrides = const <Override>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repository),
        cacheStoreProvider.overrideWithValue(cacheStore ?? MemoryCacheStore()),
        appLoggerProvider.overrideWithValue(logger ?? AppLogger()),
        installedPluginsProvider.overrideWith(
          (ref) async => <InstalledPlugin>[],
        ),
        ...overrides,
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

  testWidgets('playback screen disables only bounce without support', (
    tester,
  ) async {
    final repository = InMemorySettingsRepository(
      const AppSettings(
        playback: PlaybackSettings(livePhotoMode: LivePhotoMode.bounce),
      ),
    );
    await _pump(
      tester,
      repository: repository,
      screen: const PlaybackSettingsScreen(),
      overrides: [
        livePhotoBounceSupportProvider.overrideWith(
          (ref) => Future<bool>.value(false),
        ),
      ],
    );

    expect(find.text('Device is not supported'), findsOneWidget);

    expect(
      tester
          .widget<RadioListTile<LivePhotoMode>>(
            find.byKey(const ValueKey<String>('live-photo-mode-bounce')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<RadioListTile<LivePhotoMode>>(
            find.byKey(const ValueKey<String>('live-photo-mode-live')),
          )
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<RadioListTile<LivePhotoMode>>(
            find.byKey(const ValueKey<String>('live-photo-mode-loop')),
          )
          .enabled,
      isTrue,
    );
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

    expect(find.widgetWithText(ListTile, 'Customizations'), findsOneWidget);
  });

  testWidgets('automation screen saves automation and night mode', (
    tester,
  ) async {
    final repository = InMemorySettingsRepository();
    await _pump(
      tester,
      repository: repository,
      screen: const AutomationSettingsScreen(),
      overrides: [
        autostartServiceProvider.overrideWithValue(_FakeAutostart()),
        permissionsServiceProvider.overrideWithValue(
          const UnsupportedPermissions(),
        ),
      ],
    );

    final startOnBoot = find.widgetWithText(SwitchListTile, 'Start on boot');
    expect(find.text('Starts the slideshow after reboot.'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(startOnBoot).onChanged, isNotNull);
    await tester.tap(startOnBoot);
    await tester.pumpAndSettle();
    expect((await repository.load()).automation.startOnBoot, isTrue);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Fullscreen'));
    await tester.pumpAndSettle();
    expect((await repository.load()).automation.fullscreen, isTrue);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Fullscreen'));
    await tester.pumpAndSettle();
    expect((await repository.load()).automation.fullscreen, isFalse);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Kiosk mode'));
    await tester.pumpAndSettle();
    final automation = (await repository.load()).automation;
    expect(automation.kiosk, isTrue);
    expect(automation.fullscreen, isTrue);

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
    expect((await repository.load()).cache.quotaBytes, 2048 * 1024 * 1024);

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

  testWidgets('about screen shows platform, cache, licenses, and errors', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'Photo Frame',
      packageName: 'com.rincew1nd.photoframe',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
    );
    final store = MemoryCacheStore();
    final cachedAt = DateTime.utc(2026, 1, 2, 3, 4);
    await store.upsertAsset(
      CachedAsset(
        id: 'photo-1',
        sizeBytes: 1024,
        cachedAt: cachedAt,
        lastAccessedAt: cachedAt,
      ),
    );
    final logger = AppLogger()..error('sync failed');

    await _pump(
      tester,
      repository: InMemorySettingsRepository(),
      screen: const AboutSettingsScreen(),
      cacheStore: store,
      logger: logger,
    );

    expect(find.text('Platform'), findsOneWidget);
    expect(find.text(Platform.operatingSystem), findsOneWidget);
    expect(find.text(Platform.operatingSystemVersion), findsOneWidget);
    expect(find.text('Cache'), findsOneWidget);
    expect(find.text('1 · 1.0 KB'), findsOneWidget);
    expect(find.text('1.0 KB'), findsOneWidget);
    expect(find.text('Never synced'), findsOneWidget);
    expect(find.text('Licenses'), findsOneWidget);
    expect(find.text('Crash reports'), findsOneWidget);
    expect(find.text('1 error logged'), findsOneWidget);
  });

  testWidgets('plugins screen lists installed plugins and add action', (
    tester,
  ) async {
    final repository = InMemorySettingsRepository();
    await _pump(
      tester,
      repository: repository,
      screen: const PluginsSettingsScreen(),
    );

    expect(find.text('Installed plugins'), findsOneWidget);
    expect(find.text('No plugins installed'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('add-plugin')), findsOneWidget);
  });
}
