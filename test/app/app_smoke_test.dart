import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/app/app.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/app/router.dart';
import 'package:photoframe/data/cache/cache_store.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/features/slideshow/slideshow_screen.dart';
import 'package:photoframe/main.dart';
import 'package:photoframe/platform/services.dart';

class _NoopKeepAwake implements KeepAwakeService {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}

  @override
  Future<bool> get isEnabled async => false;
}

class _NoopBiometrics implements BiometricsService {
  @override
  Future<bool> get canAuthenticate async => false;

  @override
  Future<bool> authenticate(String reason) async => true;
}

class _NoopSingleInstance implements SingleInstanceService {
  @override
  Future<bool> acquire() async => true;

  @override
  Future<void> release() async {}
}

void main() {
  testWidgets('unconfigured app starts in settings', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(),
          ),
          cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
          routerProvider.overrideWithValue(
            createAppRouter(initialLocation: '/settings'),
          ),
          platformServicesProvider.overrideWithValue(
            PlatformServices(
              keepAwake: _NoopKeepAwake(),
              fullscreen: const UnsupportedFullscreen(),
              biometrics: _NoopBiometrics(),
              singleInstance: _NoopSingleInstance(),
              livePhotoMotion: const PlatformLivePhotoMotionSupport(),
            ),
          ),
        ],
        child: const PhotoFrameApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('configured app starts in the slideshow', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(),
          ),
          cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
          routerProvider.overrideWithValue(
            createAppRouter(initialLocation: '/slideshow'),
          ),
          platformServicesProvider.overrideWithValue(
            PlatformServices(
              keepAwake: _NoopKeepAwake(),
              fullscreen: const UnsupportedFullscreen(),
              biometrics: _NoopBiometrics(),
              singleInstance: _NoopSingleInstance(),
              livePhotoMotion: const PlatformLivePhotoMotionSupport(),
            ),
          ),
        ],
        child: const PhotoFrameApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(SlideshowScreen), findsOneWidget);
  });

  testWidgets('bootstrap error app renders localized retry', (tester) async {
    await tester.pumpWidget(const BootstrapErrorApp());
    await tester.pump();
    expect(find.text('Photo Frame'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
