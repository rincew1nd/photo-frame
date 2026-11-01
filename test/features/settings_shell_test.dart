import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/data/cache/cache_store.dart';
import 'package:photoframe/data/plugins/plugin_store.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/features/settings/settings_shell.dart';
import 'package:photoframe/l10n/app_localizations.dart';

const AppSettings _sample = AppSettings(
  playback: PlaybackSettings(
    intervalSeconds: 15,
    shuffle: false,
    transition: TransitionType.zoom,
    videoPlaybackMode: VideoPlaybackMode.staticPreview,
  ),
  defaultProfile: AspectProfile(
    fit: ImageFit.cover,
    adaptiveBackground: AdaptiveBackground.ambientGlow,
    panStrength: 30,
  ),
  filters: FilterSettings(selectedAssetIds: <String>{'a', 'b'}),
  cache: CacheSettings(
    quotaBytes: 4 * 1024 * 1024 * 1024,
    prefetchCount: 3,
  ),
  display: DisplaySettings(keepScreenOn: true),
  automation: AutomationSettings(fullscreen: true),
  nightMode: NightModeSettings(enabled: true),
  connection: ConnectionSettings(
    serverUrl: 'https://photos.example.com/api',
    userName: 'Alice',
    permissions: <String, String>{'user.read': 'granted'},
  ),
);

const AppSettings _configured = AppSettings(
  connection: ConnectionSettings(
    serverUrl: 'https://photos.example.com/api',
    albumIds: <String>{'album-1'},
  ),
);

Widget _app(InMemorySettingsRepository repository, GoRouter router) {
  return ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(repository),
      cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
      appLoggerProvider.overrideWithValue(AppLogger()),
      installedPluginsProvider.overrideWith(
        (ref) async => <InstalledPlugin>[],
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  InMemorySettingsRepository repository,
  GoRouter router,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(router.dispose);
  await tester.pumpWidget(_app(repository, router));
  await tester.pumpAndSettle();
}

GoRouter _settingsRouter({String initialLocation = '/settings'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsShell(),
      ),
      GoRoute(
        path: '/slideshow',
        builder: (context, state) =>
            const Scaffold(body: Text('Slideshow page')),
      ),
    ],
  );
}

void main() {
  testWidgets('root list shows sections, rows, and summaries', (tester) async {
    await _pump(
      tester,
      InMemorySettingsRepository(_sample),
      _settingsRouter(),
    );

    for (final section in <String>['Media', 'Appearance', 'About']) {
      expect(find.text(section), findsOneWidget);
    }
    for (final section in <String>[
      'Playback',
      'Slideshow',
      'Plugins',
      'Automation',
      'Connection',
    ]) {
      expect(find.text(section), findsNWidgets(2));
    }

    for (final row in <String>[
      'Albums',
      'Select media',
      'Cache',
      'Playback',
      'Slideshow',
      'Plugins',
      'Automation',
      'Connection',
      'About & diagnostics',
    ]) {
      expect(find.widgetWithText(ListTile, row), findsOneWidget);
    }

    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('4 GB limit · prefetch 3'), findsOneWidget);
    expect(
      find.text('15s · In order · Zoom · Static preview'),
      findsOneWidget,
    );
    expect(find.text('Cover · Ambient glow · Pan 30'), findsOneWidget);
    expect(find.text('0 plugins · 0 enabled'), findsOneWidget);
    expect(
      find.text('Fullscreen · Keep awake · Night mode on'),
      findsOneWidget,
    );
    expect(
      find.text('photos.example.com · Alice · Connected'),
      findsOneWidget,
    );

    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('back falls back to the slideshow when there is no stack', (
    tester,
  ) async {
    await _pump(
      tester,
      InMemorySettingsRepository(_configured),
      _settingsRouter(),
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Slideshow page'), findsOneWidget);
  });

  testWidgets('back stays on settings when the connection is unconfigured', (
    tester,
  ) async {
    await _pump(tester, InMemorySettingsRepository(), _settingsRouter());

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Slideshow page'), findsNothing);
    expect(find.byType(SettingsShell), findsOneWidget);
  });

  testWidgets('back pops to the previous screen when pushed', (tester) async {
    final router = GoRouter(
      initialLocation: '/slideshow',
      routes: <RouteBase>[
        GoRoute(
          path: '/slideshow',
          builder: (context, state) => Scaffold(
            body: Column(
              children: <Widget>[
                const Text('Slideshow page'),
                FilledButton(
                  onPressed: () => context.push('/settings'),
                  child: const Text('Open settings'),
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsShell(),
        ),
      ],
    );

    await _pump(tester, InMemorySettingsRepository(), router);

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsShell), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Slideshow page'), findsOneWidget);
    expect(find.byType(SettingsShell), findsNothing);
  });

  testWidgets('theme toggle saves dark', (tester) async {
    final repository = InMemorySettingsRepository();
    await _pump(tester, repository, _settingsRouter());

    await tester.tap(find.byTooltip('Switch to dark theme'));
    await tester.pumpAndSettle();

    expect((await repository.load()).display.theme, 'dark');
  });

  testWidgets('follow system theme switch saves system and light', (
    tester,
  ) async {
    final repository = InMemorySettingsRepository(
      const AppSettings(display: DisplaySettings(theme: 'dark')),
    );
    await _pump(tester, repository, _settingsRouter());

    await tester.tap(find.text('Follow system theme'));
    await tester.pumpAndSettle();
    expect((await repository.load()).display.theme, 'system');

    await tester.tap(find.text('Follow system theme'));
    await tester.pumpAndSettle();
    final theme = (await repository.load()).display.theme;
    expect(theme, isNot('system'));
    expect(theme, 'light');
  });

  testWidgets('root rows navigate to their routes', (tester) async {
    const pages = <String, String>{
      'Albums': 'Albums page',
      'Select media': 'Media page',
      'Cache': 'Cache page',
      'Playback': 'Playback page',
      'Slideshow': 'Slideshow page',
      'Plugins': 'Plugins page',
      'Automation': 'Automation page',
      'Connection': 'Connection page',
      'About & diagnostics': 'About page',
    };
    const routes = <String, String>{
      '/settings': 'Settings',
      '/albums': 'Albums page',
      '/media-selection': 'Media page',
      '/settings/cache': 'Cache page',
      '/settings/playback': 'Playback page',
      '/settings/slideshow': 'Slideshow page',
      '/settings/plugins': 'Plugins page',
      '/settings/automation': 'Automation page',
      '/settings/connection': 'Connection page',
      '/settings/about': 'About page',
    };

    final router = GoRouter(
      initialLocation: '/settings',
      routes: <RouteBase>[
        for (final entry in routes.entries)
          GoRoute(
            path: entry.key,
            builder: (context, state) => entry.key == '/settings'
                ? const SettingsShell()
                : Scaffold(appBar: AppBar(), body: Text(entry.value)),
          ),
      ],
    );

    await _pump(tester, InMemorySettingsRepository(_sample), router);

    for (final entry in pages.entries) {
      final row = find.widgetWithText(ListTile, entry.key);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    }
  });
}
