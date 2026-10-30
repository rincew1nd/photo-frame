import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/weather/weather_service.dart';
import 'package:photoframe/features/media_selection/media_selection_screen.dart';
import 'package:photoframe/features/slideshow/slideshow_controller.dart';
import 'package:photoframe/platform/services.dart';

class _FakeSettingsController extends SettingsController {
  _FakeSettingsController(this.initial);

  AppSettings initial;
  AppSettings? saved;

  @override
  Future<AppSettings> build() async => initial;

  @override
  Future<void> save(AppSettings Function(AppSettings) update) async {
    final next = update(initial);
    initial = next;
    saved = next;
    state = AsyncData(next);
  }
}

class _FakeSlideshowController extends SlideshowController {
  _FakeSlideshowController(this.initial);

  final SlideshowViewState initial;

  @override
  Future<SlideshowViewState> build() async => initial;

  @override
  Future<WeatherSnapshot?> refreshWeather() async => null;
}

class _NoBiometrics implements BiometricsService {
  @override
  Future<bool> get canAuthenticate async => false;

  @override
  Future<bool> authenticate(String reason) async => true;
}

class _NoopKeepAwake implements KeepAwakeService {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}

  @override
  Future<bool> get isEnabled async => false;
}

class _NoopSingleInstance implements SingleInstanceService {
  @override
  Future<bool> acquire() async => true;

  @override
  Future<void> release() async {}
}

PlatformServices _services() {
  return PlatformServices(
    keepAwake: _NoopKeepAwake(),
    fullscreen: const UnsupportedFullscreen(),
    biometrics: _NoBiometrics(),
    singleInstance: _NoopSingleInstance(),
    livePhotoMotion: const PlatformLivePhotoMotionSupport(),
  );
}

const List<int> _png = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('media_selection_test');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

File _image(Directory dir, String name) {
  final file = File('${dir.path}/$name.png');
  file.writeAsBytesSync(base64Decode(base64Encode(_png)));
  return file;
}

CachedAsset _cached(String id, File file, {MediaKind type = MediaKind.photo}) {
  return CachedAsset(
    id: id,
    type: type,
    aspectBucket: AspectBucket.sixteenNine,
    thumbnailPath: file.path,
    cachedAt: DateTime.utc(2026),
    lastAccessedAt: DateTime.utc(2026),
  );
}

void main() {
  testWidgets('lists cached assets, toggles selection, and saves', (
    tester,
  ) async {
    final dir = _tempDir();
    final one = _image(dir, 'one');
    final two = _image(dir, 'two');
    final three = _image(dir, 'three');

    late _FakeSettingsController settings;
    final router = GoRouter(
      initialLocation: '/media-selection',
      routes: [
        GoRoute(
          path: '/media-selection',
          builder: (context, state) => const MediaSelectionScreen(),
        ),
        GoRoute(
          path: '/slideshow',
          builder: (context, state) =>
              const Scaffold(body: Text('Slideshow')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(() {
            settings = _FakeSettingsController(const AppSettings());
            return settings;
          }),
          slideshowControllerProvider.overrideWith(
            () => _FakeSlideshowController(
              SlideshowViewState(
                loading: false,
                cached: <CachedAsset>[
                  _cached('a1', one),
                  _cached('a2', two),
                  _cached('a3', three, type: MediaKind.video),
                ],
              ),
            ),
          ),
          platformServicesProvider.overrideWithValue(_services()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Media selection'), findsOneWidget);
    expect(find.text('0 / 3 assets selected'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(3));

    await tester.tap(find.byKey(const ValueKey<String>('a1')));
    await tester.pumpAndSettle();

    final firstBox = tester.widget<Checkbox>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('a1')),
        matching: find.byType(Checkbox),
      ),
    );
    expect(firstBox.value, isTrue);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(settings.saved?.filters.selectedAssetIds, <String>{'a1'});
    expect(find.text('Slideshow'), findsOneWidget);
  });

  testWidgets('shows all cached assets and selects all', (tester) async {
    final dir = _tempDir();
    final one = _image(dir, 'one');
    final two = _image(dir, 'two');

    final router = GoRouter(
      initialLocation: '/media-selection',
      routes: [
        GoRoute(
          path: '/media-selection',
          builder: (context, state) => const MediaSelectionScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _FakeSettingsController(const AppSettings()),
          ),
          slideshowControllerProvider.overrideWith(
            () => _FakeSlideshowController(
              SlideshowViewState(
                loading: false,
                cached: <CachedAsset>[
                  _cached('a1', one),
                  _cached('a2', two, type: MediaKind.video),
                ],
              ),
            ),
          ),
          platformServicesProvider.overrideWithValue(_services()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0 / 2 assets selected'), findsOneWidget);

    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();

    final photoBox = tester.widget<Checkbox>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('a1')),
        matching: find.byType(Checkbox),
      ),
    );
    final videoBox = tester.widget<Checkbox>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('a2')),
        matching: find.byType(Checkbox),
      ),
    );
    expect(photoBox.value, isTrue);
    expect(videoBox.value, isTrue);
    expect(find.text('2 / 2 assets selected'), findsOneWidget);
  });
}
