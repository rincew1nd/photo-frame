import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/data/cache/cache_store.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/features/settings/customizations_screen.dart';
import 'package:photoframe/l10n/app_localizations.dart';

Widget _app(InMemorySettingsRepository repository, GoRouter router) {
  return ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(repository),
      cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
      appLoggerProvider.overrideWithValue(AppLogger()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/settings/slideshow/customizations',
    routes: <RouteBase>[
      GoRoute(
        path: '/settings',
        builder: (context, state) => const Scaffold(body: Text('Settings')),
      ),
      GoRoute(
        path: '/settings/slideshow/customizations',
        builder: (context, state) => const CustomizationsScreen(),
      ),
      GoRoute(
        path: '/settings/slideshow/customizations/:id',
        builder: (context, state) => CustomizationEditorScreen(
          customizationId: state.pathParameters['id'],
        ),
      ),
    ],
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

void main() {
  testWidgets('adds, edits, and removes a customization', (tester) async {
    final repository = InMemorySettingsRepository(const AppSettings());
    await _pump(tester, repository, _router());

    expect(find.text('No customizations yet'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('customization-add')));
    await tester.pumpAndSettle();

    expect(find.byType(CustomizationEditorScreen), findsOneWidget);
    expect((await repository.load()).customizations, hasLength(1));
    final id = (await repository.load()).customizations.single.id;

    await tester.enterText(
      find.byKey(const ValueKey<String>('customization-name')),
      'Wide photos',
    );
    await tester.pump();
    expect(
      (await repository.load()).customizations.single.name,
      'Wide photos',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('customization-aspect-sixteenNine')),
    );
    await tester.pump();
    expect(
      (await repository.load()).customizations.single.aspects,
      contains(AspectBucket.sixteenNine),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('customization-media-photo')),
    );
    await tester.pump();
    expect(
      (await repository.load()).customizations.single.mediaTypes,
      contains(MediaKind.photo),
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('customization-background-blurredCover'),
      ),
    );
    await tester.pump();
    expect(
      (await repository.load()).customizations.single.profile.adaptiveBackground,
      AdaptiveBackground.blurredCover,
    );

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(
              const ValueKey<String>('customization-image-motion'),
            ),
          )
          .onChanged,
      isNull,
    );

    await tester.tap(find.text('Cover'));
    await tester.pumpAndSettle();
    expect(
      (await repository.load()).customizations.single.profile.fit,
      ImageFit.cover,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('customization-image-motion')),
    );
    await tester.pump();
    expect(
      (await repository.load()).customizations.single.profile.imageMotion,
      isFalse,
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    final row = find.byKey(ValueKey<String>('customization-profile-$id'));
    expect(row, findsOneWidget);
    expect(find.text('Wide photos'), findsOneWidget);
    for (final fragment in <String>['16:9', 'Photos', 'Blurred cover']) {
      expect(
        find.descendant(of: row, matching: find.textContaining(fragment)),
        findsOneWidget,
      );
    }

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(CustomizationEditorScreen), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('customization-delete')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect((await repository.load()).customizations, isEmpty);
    expect(find.text('No customizations yet'), findsOneWidget);
  });
}
