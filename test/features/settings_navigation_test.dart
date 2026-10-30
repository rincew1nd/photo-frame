import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/data/cache/cache_store.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/features/settings/settings_shell.dart';
import 'package:photoframe/l10n/app_localizations.dart';

Future<void> _pump(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/slideshow',
    routes: [
      GoRoute(
        path: '/slideshow',
        builder: (context, state) => Scaffold(
          body: Column(
            children: [
              const Text('Slideshow page'),
              FilledButton(
                key: const ValueKey<String>('slideshow-settings'),
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
  addTearDown(router.dispose);
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(),
        ),
        cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
        appLoggerProvider.overrideWithValue(AppLogger()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Back from slideshow settings returns to the slideshow', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const ValueKey<String>('slideshow-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsShell), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Slideshow page'), findsOneWidget);
    expect(find.byType(SettingsShell), findsNothing);
  });
}
