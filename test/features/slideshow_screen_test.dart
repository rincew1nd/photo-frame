import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/data/media/playback.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/data/weather/weather_service.dart';
import 'package:photoframe/domain/media/ken_burns.dart';
import 'package:photoframe/features/slideshow/slideshow_controller.dart';
import 'package:photoframe/features/slideshow/slideshow_screen.dart';

import '../support/fake_media_playback.dart';

class _FakeSlideshowController extends SlideshowController {
  _FakeSlideshowController(this.initial);

  final SlideshowViewState initial;
  int nextCalls = 0;
  int previousCalls = 0;
  int syncCalls = 0;
  int weatherCalls = 0;
  int advanceCalls = 0;

  @override
  Future<SlideshowViewState> build() async => initial;

  @override
  void next() {
    nextCalls++;
  }

  @override
  void previous() {
    previousCalls++;
  }

  @override
  void togglePause() {}

  @override
  Future<void> syncNow() async {
    syncCalls++;
  }

  @override
  Future<WeatherSnapshot?> refreshWeather() async {
    weatherCalls++;
    return null;
  }

  @override
  void advanceIfCurrent(String assetId) {
    advanceCalls++;
  }
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
  final dir = Directory.systemTemp.createTempSync('slideshow_test');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

const String _landscapePngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAgCAYAAACinX6EAAAAAXNSR0IArs4c6QAAAARnQU1BAACx'
    'jwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAeSURBVGhD7cEBDQAAAMKg909tDwcUAAAAAAAA'
    'APBuICAAAWbYvZgAAAAASUVORK5CYII=';

File _image(Directory dir, String name) {
  final file = File('${dir.path}/$name.png');
  file.writeAsBytesSync(base64Decode(base64Encode(_png)));
  return file;
}

File _landscapeImage(Directory dir) {
  final file = File('${dir.path}/landscape.png');
  file.writeAsBytesSync(base64Decode(_landscapePngBase64));
  return file;
}

Future<File> _sizedImage(
  Directory dir,
  String name,
  int width,
  int height,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${dir.path}/$name.png');
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
  return file;
}

CachedAsset _cached(String id, File file) {
  return CachedAsset(
    id: id,
    originalPath: file.path,
    thumbnailPath: file.path,
    cachedAt: DateTime.utc(2026),
    lastAccessedAt: DateTime.utc(2026),
  );
}

AppSettings _settings() {
  return const AppSettings(
    overlays: OverlaySettings(clock: false),
    defaultProfile: AspectProfile(imageMotion: false),
  );
}

Future<_FakeSlideshowController> _pump(
  WidgetTester tester,
  SlideshowViewState state, {
  Size size = const Size(800, 600),
  AppSettings? settings,
  InMemorySettingsRepository? repository,
  List<Override> overrides = const <Override>[],
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  late _FakeSlideshowController controller;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        slideshowControllerProvider.overrideWith(() {
          controller = _FakeSlideshowController(state);
          return controller;
        }),
        settingsRepositoryProvider.overrideWithValue(
          repository ?? InMemorySettingsRepository(settings ?? _settings()),
        ),
        ...overrides,
      ],
      child: const MaterialApp(home: SlideshowScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

SlideshowViewState _fullVideoState({
  required File videoFile,
  required File thumbnail,
}) {
  return SlideshowViewState(
    assets: const <ImmichAsset>[ImmichAsset(id: 'v1', type: MediaKind.video)],
    current: const ImmichAsset(id: 'v1', type: MediaKind.video),
    playing: true,
    loading: false,
    cached: <CachedAsset>[
      CachedAsset(
        id: 'v1',
        type: MediaKind.video,
        originalMimeType: 'video/mp4',
        originalPath: videoFile.path,
        thumbnailPath: thumbnail.path,
        cachedAt: DateTime.utc(2026),
        lastAccessedAt: DateTime.utc(2026),
      ),
    ],
  );
}

void main() {
  testWidgets('renders current image, progress, and controls', (tester) async {
    final dir = _tempDir();
    final first = _image(dir, 'first');
    final second = _image(dir, 'second');
    final controller = await _pump(
      tester,
      SlideshowViewState(
        assets: const <ImmichAsset>[
          ImmichAsset(id: 'a1', aspectBucket: AspectBucket.sixteenNine),
          ImmichAsset(id: 'a2', aspectBucket: AspectBucket.fourThree),
        ],
        current: const ImmichAsset(
          id: 'a1',
          aspectBucket: AspectBucket.sixteenNine,
        ),
        currentIndex: 0,
        playing: true,
        loading: false,
        progress: 0.4,
        total: 2,
        cached: <CachedAsset>[_cached('a1', first), _cached('a2', second)],
      ),
    );

    expect(find.byKey(const ValueKey<String>('a1')), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as FileImage).file.path, first.path);

    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, 0.4);

    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey<String>('slideshow-controls')),
          )
          .opacity,
      0,
    );

    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey<String>('slideshow-controls')),
          )
          .opacity,
      1,
    );
    expect(find.byTooltip('Sync'), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsOneWidget);
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(controller.nextCalls, 1);
  });

  test(
    'displayFileFor returns null for an unsupported mime without a preview',
    () {
      final dir = _tempDir();
      final original = File('${dir.path}/photo.heic')
        ..writeAsBytesSync(<int>[0, 1, 2]);
      final asset = CachedAsset(
        id: 'heic-missing',
        originalMimeType: 'image/heic',
        originalPath: original.path,
        cachedAt: DateTime.utc(2026),
        lastAccessedAt: DateTime.utc(2026),
      );

      expect(displayFileFor(asset), isNull);
    },
  );

  test('displayFileFor returns the preview for an unsupported mime', () {
    final dir = _tempDir();
    final original = File('${dir.path}/photo.heic')
      ..writeAsBytesSync(<int>[0, 1, 2]);
    final preview = _image(dir, 'preview');
    final asset = CachedAsset(
      id: 'heic-preview',
      originalMimeType: 'image/heic',
      originalPath: original.path,
      thumbnailPath: preview.path,
      cachedAt: DateTime.utc(2026),
      lastAccessedAt: DateTime.utc(2026),
    );

    expect(displayFileFor(asset)?.path, preview.path);
  });

  test('displayFileFor prefers a usable derived image', () {
    final dir = _tempDir();
    final original = File('${dir.path}/photo.heic')
      ..writeAsBytesSync(<int>[0, 1, 2]);
    final thumbnail = _image(dir, 'thumb');
    final derived = _image(dir, 'derived');
    final asset = CachedAsset(
      id: 'heic-derived',
      originalMimeType: 'image/heic',
      originalPath: original.path,
      thumbnailPath: thumbnail.path,
      derivedImagePath: derived.path,
      cachedAt: DateTime.utc(2026),
      lastAccessedAt: DateTime.utc(2026),
    );

    expect(displayFileFor(asset)!.path, derived.path);
  });

  test('displayFileFor falls back to the thumbnail for a missing derived image', () {
    final dir = _tempDir();
    final original = File('${dir.path}/photo.heic')
      ..writeAsBytesSync(<int>[0, 1, 2]);
    final thumbnail = _image(dir, 'thumb');
    final asset = CachedAsset(
      id: 'heic-derived-missing',
      originalMimeType: 'image/heic',
      originalPath: original.path,
      thumbnailPath: thumbnail.path,
      derivedImagePath: '${dir.path}/missing-derived.png',
      cachedAt: DateTime.utc(2026),
      lastAccessedAt: DateTime.utc(2026),
    );

    expect(displayFileFor(asset)?.path, thumbnail.path);
  });

  testWidgets(
    'unsupported original without a preview shows the no-cache state',
    (tester) async {
      final dir = _tempDir();
      final original = File('${dir.path}/photo.heic')
        ..writeAsBytesSync(<int>[0, 1, 2]);
      await _pump(
        tester,
        SlideshowViewState(
          assets: const <ImmichAsset>[ImmichAsset(id: 'h1')],
          current: const ImmichAsset(id: 'h1'),
          loading: false,
          cached: <CachedAsset>[
            CachedAsset(
              id: 'h1',
              originalMimeType: 'image/heic',
              originalPath: original.path,
              cachedAt: DateTime.utc(2026),
              lastAccessedAt: DateTime.utc(2026),
            ),
          ],
        ),
      );

      expect(find.text('Image not cached'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets('shows the no-items state and hides controls', (tester) async {
    final controller = await _pump(
      tester,
      const SlideshowViewState(
        loading: false,
        error: SlideshowController.noItemsMessage,
      ),
    );

    expect(find.text(SlideshowController.noItemsMessage), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();
    expect(controller.syncCalls, 1);
  });

  testWidgets('shows the video state instead of photo playback', (
    tester,
  ) async {
    final dir = _tempDir();
    final thumbnail = _image(dir, 'video-thumb');
    await _pump(
      tester,
      SlideshowViewState(
        assets: const <ImmichAsset>[
          ImmichAsset(id: 'v1', type: MediaKind.video),
        ],
        current: const ImmichAsset(id: 'v1', type: MediaKind.video),
        loading: false,
        cached: <CachedAsset>[
          CachedAsset(
            id: 'v1',
            type: MediaKind.video,
            originalMimeType: 'video/mp4',
            thumbnailPath: thumbnail.path,
            cachedAt: DateTime.utc(2026),
            lastAccessedAt: DateTime.utc(2026),
          ),
        ],
      ),
    );

    expect(find.text('Video preview'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as FileImage).file.path, thumbnail.path);
    expect(find.byKey(const ValueKey<String>('ken-burns-frame')), findsNothing);
  });

  testWidgets('full video mode renders the player and hides the preview label', (
    tester,
  ) async {
    final dir = _tempDir();
    final thumbnail = _image(dir, 'video-thumb');
    final videoFile = File('${dir.path}/video.mp4')
      ..writeAsBytesSync(<int>[0, 1, 2, 3]);
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);
    final controller = await _pump(
      tester,
      _fullVideoState(videoFile: videoFile, thumbnail: thumbnail),
      repository: InMemorySettingsRepository(
        const AppSettings(
          overlays: OverlaySettings(clock: false),
          defaultProfile: AspectProfile(imageMotion: false),
          playback: PlaybackSettings(
            videoPlaybackMode: VideoPlaybackMode.full,
          ),
        ),
      ),
      overrides: [
        mediaPlaybackFactoryProvider.overrideWithValue(() => fake),
      ],
    );

    expect(find.text('fake-video'), findsOneWidget);
    expect(find.text('Video preview'), findsNothing);

    fake.emit(const PlaybackSnapshot(phase: PlaybackPhase.completed));
    await tester.pump();

    expect(controller.advanceCalls, 1);
  });

  testWidgets('mute control saves the muted setting', (tester) async {
    final dir = _tempDir();
    final thumbnail = _image(dir, 'video-thumb');
    final videoFile = File('${dir.path}/video.mp4')
      ..writeAsBytesSync(<int>[0, 1, 2, 3]);
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);
    final repository = InMemorySettingsRepository(
      const AppSettings(
        overlays: OverlaySettings(clock: false),
        defaultProfile: AspectProfile(imageMotion: false),
        playback: PlaybackSettings(
          videoPlaybackMode: VideoPlaybackMode.full,
          muted: true,
        ),
      ),
    );
    await _pump(
      tester,
      _fullVideoState(videoFile: videoFile, thumbnail: thumbnail),
      repository: repository,
      overrides: [
        mediaPlaybackFactoryProvider.overrideWithValue(() => fake),
      ],
    );

    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Unmute audio'));
    await tester.pumpAndSettle();

    expect((await repository.load()).playback.muted, isFalse);
    expect(find.byTooltip('Mute audio'), findsOneWidget);
  });

  testWidgets('unsupported originals fall back to the thumbnail', (
    tester,
  ) async {
    final dir = _tempDir();
    final original = File('${dir.path}/original.heic')
      ..writeAsBytesSync(<int>[0, 1, 2, 3]);
    final thumbnail = _image(dir, 'thumb');
    await _pump(
      tester,
      SlideshowViewState(
        assets: const <ImmichAsset>[ImmichAsset(id: 'h1')],
        current: const ImmichAsset(id: 'h1'),
        loading: false,
        cached: <CachedAsset>[
          CachedAsset(
            id: 'h1',
            originalMimeType: 'image/heic',
            originalPath: original.path,
            thumbnailPath: thumbnail.path,
            cachedAt: DateTime.utc(2026),
            lastAccessedAt: DateTime.utc(2026),
          ),
        ],
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as FileImage).file.path, thumbnail.path);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pan strength animates wide current image horizontally', (
    tester,
  ) async {
    final dir = _tempDir();
    final first = (await tester.runAsync(() => _sizedImage(dir, 'first', 1600, 900)))!;
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          slideshowControllerProvider.overrideWith(
            () => _FakeSlideshowController(
              SlideshowViewState(
                assets: const <ImmichAsset>[ImmichAsset(id: 'p1')],
                current: const ImmichAsset(id: 'p1'),
                loading: false,
                cached: <CachedAsset>[
                  _cached('p1', first).copyWith(width: 1600, height: 900),
                ],
              ),
            ),
          ),
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const AppSettings(
                overlays: OverlaySettings(clock: false),
                defaultProfile: AspectProfile(
                  fit: ImageFit.cover,
                  panStrength: 80,
                ),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SlideshowScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final frame = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('ken-burns-frame')),
    );
    expect(frame.transform.getTranslation().y, 0);
    expect(frame.transform.getTranslation().x, isNot(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pan uses an image box wider than the viewport', (tester) async {
    final dir = _tempDir();
    final first = (await tester.runAsync(() => _sizedImage(dir, 'wide', 3000, 1000)))!;
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          slideshowControllerProvider.overrideWith(
            () => _FakeSlideshowController(
              SlideshowViewState(
                assets: const <ImmichAsset>[ImmichAsset(id: 'w1')],
                current: const ImmichAsset(id: 'w1'),
                loading: false,
                cached: <CachedAsset>[
                  _cached('w1', first).copyWith(width: 3000, height: 1000),
                ],
              ),
            ),
          ),
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const AppSettings(
                overlays: OverlaySettings(clock: false),
                defaultProfile: AspectProfile(
                  fit: ImageFit.cover,
                  panStrength: 100,
                ),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SlideshowScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final display = find.byKey(const ValueKey<String>('ken-burns-display'));
    expect(display, findsOneWidget);
    final size = tester.getSize(display);
    expect(size.width, greaterThan(800));
    expect(size.height, 600);
    expect(tester.getSize(find.byType(Image)).width, greaterThan(800));

    final frame = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('ken-burns-frame')),
    );
    final dx = frame.transform.getTranslation().x;
    expect(dx.abs(), lessThanOrEqualTo((size.width - 800) / 2 + 1e-6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pan strength animates tall current image vertically', (
    tester,
  ) async {
    final dir = _tempDir();
    final first = (await tester.runAsync(() => _sizedImage(dir, 'first', 900, 1600)))!;
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          slideshowControllerProvider.overrideWith(
            () => _FakeSlideshowController(
              SlideshowViewState(
                assets: const <ImmichAsset>[ImmichAsset(id: 'p2')],
                current: const ImmichAsset(id: 'p2'),
                loading: false,
                cached: <CachedAsset>[
                  _cached('p2', first).copyWith(width: 900, height: 1600),
                ],
              ),
            ),
          ),
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const AppSettings(
                overlays: OverlaySettings(clock: false),
                defaultProfile: AspectProfile(
                  fit: ImageFit.cover,
                  panStrength: 80,
                ),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SlideshowScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final frame = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('ken-burns-frame')),
    );
    expect(frame.transform.getTranslation().x, 0);
    expect(frame.transform.getTranslation().y, isNot(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pan strength zooms a matching aspect without translation', (
    tester,
  ) async {
    final dir = _tempDir();
    final first = (await tester.runAsync(() => _sizedImage(dir, 'first', 1600, 1200)))!;
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          slideshowControllerProvider.overrideWith(
            () => _FakeSlideshowController(
              SlideshowViewState(
                assets: const <ImmichAsset>[ImmichAsset(id: 'p3')],
                current: const ImmichAsset(id: 'p3'),
                loading: false,
                cached: <CachedAsset>[
                  _cached('p3', first).copyWith(width: 1600, height: 1200),
                ],
              ),
            ),
          ),
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const AppSettings(
                overlays: OverlaySettings(clock: false),
                defaultProfile: AspectProfile(
                  fit: ImageFit.cover,
                  panStrength: 80,
                ),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SlideshowScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final frame = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('ken-burns-frame')),
    );
    expect(frame.transform.getTranslation().x, 0);
    expect(frame.transform.getTranslation().y, 0);
    expect(tester.takeException(), isNull);
  });

  test('pan frame uses the decoded image aspect over cached exif', () {
    final decoded = frameSizeFor(
      imageAspect: 144 / 192,
      viewportWidth: 800,
      viewportHeight: 600,
      motion: PanMotion.vertical,
    );
    final cached = frameSizeFor(
      imageAspect: 4032 / 3024,
      viewportWidth: 800,
      viewportHeight: 600,
      motion: PanMotion.vertical,
    );
    expect(decoded.displayHeight, greaterThan(600));
    expect(decoded.displayHeight, greaterThan(cached.displayHeight));
    expect(decoded.maxY, greaterThan(cached.maxY));
  });

  testWidgets('contain keeps pan enabled portrait images contained', (
    tester,
  ) async {
    final dir = _tempDir();
    final portrait = _image(dir, 'portrait');
    await _pump(
      tester,
      SlideshowViewState(
        assets: const <ImmichAsset>[ImmichAsset(id: 'p4')],
        current: const ImmichAsset(id: 'p4'),
        loading: false,
        cached: <CachedAsset>[
          _cached('p4', portrait).copyWith(width: 900, height: 1600),
        ],
      ),
      size: const Size(800, 600),
      settings: const AppSettings(
        overlays: OverlaySettings(clock: false),
        defaultProfile: AspectProfile(
          fit: ImageFit.contain,
          imageMotion: true,
          panStrength: 80,
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
    expect(find.byKey(const ValueKey<String>('ken-burns-frame')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('contain letterboxes a landscape image in a portrait viewport', (
    tester,
  ) async {
    final dir = _tempDir();
    final landscape = _landscapeImage(dir);
    await _pump(
      tester,
      SlideshowViewState(
        assets: const <ImmichAsset>[
          ImmichAsset(id: 'l1', aspectBucket: AspectBucket.sixteenNine),
        ],
        current: const ImmichAsset(
          id: 'l1',
          aspectBucket: AspectBucket.sixteenNine,
        ),
        loading: false,
        cached: <CachedAsset>[_cached('l1', landscape)],
      ),
      size: const Size(400, 800),
      settings: const AppSettings(
        overlays: OverlaySettings(clock: false),
        defaultProfile: AspectProfile(
          fit: ImageFit.contain,
          panStrength: 0,
          imageMotion: false,
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
    expect(tester.getSize(find.byType(Image)), const Size(400, 800));
  });

  testWidgets('cover fills and crops in a portrait viewport', (tester) async {
    final dir = _tempDir();
    final landscape = _landscapeImage(dir);
    await _pump(
      tester,
      SlideshowViewState(
        assets: const <ImmichAsset>[
          ImmichAsset(id: 'l1', aspectBucket: AspectBucket.sixteenNine),
        ],
        current: const ImmichAsset(
          id: 'l1',
          aspectBucket: AspectBucket.sixteenNine,
        ),
        loading: false,
        cached: <CachedAsset>[_cached('l1', landscape)],
      ),
      size: const Size(400, 800),
      settings: const AppSettings(
        overlays: OverlaySettings(clock: false),
        defaultProfile: AspectProfile(
          fit: ImageFit.cover,
          panStrength: 0,
          imageMotion: false,
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.cover);
    expect(tester.getSize(find.byType(Image)), const Size(400, 800));
  });

  testWidgets('plays live photo motion for loop mode', (tester) async {
    final dir = _tempDir();
    final first = _image(dir, 'live');
    final motion = File('${dir.path}/motion.mov')
      ..writeAsBytesSync(<int>[0, 1, 2]);
    final fake = FakeMediaPlayback();
    await _pump(
      tester,
      SlideshowViewState(
        assets: const <ImmichAsset>[
          ImmichAsset(id: 'lp1', type: MediaKind.livePhoto),
        ],
        current: const ImmichAsset(id: 'lp1', type: MediaKind.livePhoto),
        playing: true,
        loading: false,
        cached: <CachedAsset>[
          _cached(
            'lp1',
            first,
          ).copyWith(type: MediaKind.livePhoto, liveVideoPath: motion.path),
        ],
      ),
      settings: const AppSettings(
        overlays: OverlaySettings(clock: false),
        defaultProfile: AspectProfile(imageMotion: false),
        playback: PlaybackSettings(livePhotoMode: LivePhotoMode.loop),
      ),
      overrides: [mediaPlaybackFactoryProvider.overrideWithValue(() => fake)],
    );
    expect(find.text('fake-video'), findsOneWidget);
    expect(find.text('Live Photo motion in Phase 3'), findsNothing);
    expect(fake.openedSource?.uri, motion.path);
  });

  testWidgets('live photo loop pans the still in cover mode', (tester) async {
    final dir = _tempDir();
    final still = (await tester.runAsync(
      () => _sizedImage(dir, 'live-pan', 1600, 900),
    ))!;
    final motion = File('${dir.path}/motion.mov')
      ..writeAsBytesSync(<int>[0, 1, 2]);
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);
    await _pump(
      tester,
      SlideshowViewState(
        assets: const <ImmichAsset>[
          ImmichAsset(id: 'lp2', type: MediaKind.livePhoto),
        ],
        current: const ImmichAsset(id: 'lp2', type: MediaKind.livePhoto),
        playing: true,
        loading: false,
        cached: <CachedAsset>[
          _cached('lp2', still).copyWith(
            type: MediaKind.livePhoto,
            liveVideoPath: motion.path,
            width: 1600,
            height: 900,
          ),
        ],
      ),
      settings: const AppSettings(
        overlays: OverlaySettings(clock: false),
        defaultProfile: AspectProfile(
          fit: ImageFit.cover,
          imageMotion: true,
          panStrength: 80,
        ),
        playback: PlaybackSettings(
          livePhotoMode: LivePhotoMode.loop,
          intervalSeconds: 2,
        ),
      ),
      overrides: [mediaPlaybackFactoryProvider.overrideWithValue(() => fake)],
    );
    expect(find.text('fake-video'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('ken-burns-frame')),
      findsOneWidget,
    );
  });

  testWidgets('shows the still when the live photo mode is off', (tester) async {
    final dir = _tempDir();
    final first = _image(dir, 'live');
    final motion = File('${dir.path}/motion.mov')
      ..writeAsBytesSync(<int>[0, 1, 2]);
    final fake = FakeMediaPlayback();
    await _pump(
      tester,
      SlideshowViewState(
        assets: const <ImmichAsset>[
          ImmichAsset(id: 'lp1', type: MediaKind.livePhoto),
        ],
        current: const ImmichAsset(id: 'lp1', type: MediaKind.livePhoto),
        loading: false,
        cached: <CachedAsset>[
          _cached(
            'lp1',
            first,
          ).copyWith(type: MediaKind.livePhoto, liveVideoPath: motion.path),
        ],
      ),
      settings: const AppSettings(
        overlays: OverlaySettings(clock: false),
        defaultProfile: AspectProfile(imageMotion: false),
        playback: PlaybackSettings(livePhotoMode: LivePhotoMode.off),
      ),
      overrides: [mediaPlaybackFactoryProvider.overrideWithValue(() => fake)],
    );
    expect(find.text('fake-video'), findsNothing);
    expect(find.text('Live Photo motion in Phase 3'), findsNothing);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('live photo plays once then returns to the still', (tester) async {
    final dir = _tempDir();
    final first = _image(dir, 'live');
    final motion = File('${dir.path}/motion.mov')
      ..writeAsBytesSync(<int>[0, 1, 2]);
    final fake = FakeMediaPlayback();
    await _pump(
      tester,
      SlideshowViewState(
        assets: const <ImmichAsset>[
          ImmichAsset(id: 'lp1', type: MediaKind.livePhoto),
        ],
        current: const ImmichAsset(id: 'lp1', type: MediaKind.livePhoto),
        playing: true,
        loading: false,
        cached: <CachedAsset>[
          _cached(
            'lp1',
            first,
          ).copyWith(type: MediaKind.livePhoto, liveVideoPath: motion.path),
        ],
      ),
      settings: const AppSettings(
        overlays: OverlaySettings(clock: false),
        defaultProfile: AspectProfile(imageMotion: false),
        playback: PlaybackSettings(livePhotoMode: LivePhotoMode.live),
      ),
      overrides: [mediaPlaybackFactoryProvider.overrideWithValue(() => fake)],
    );
    expect(find.text('fake-video'), findsOneWidget);

    fake.emit(const PlaybackSnapshot(phase: PlaybackPhase.completed));
    await tester.pump();
    await tester.pump();

    expect(find.text('fake-video'), findsNothing);
    expect(find.byType(Image), findsWidgets);
    expect(find.text('Live Photo motion in Phase 3'), findsNothing);
  });

  testWidgets('requests weather on first frame when enabled', (tester) async {
    final dir = _tempDir();
    final first = _image(dir, 'first');
    late _FakeSlideshowController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          slideshowControllerProvider.overrideWith(() {
            controller = _FakeSlideshowController(
              SlideshowViewState(
                assets: const <ImmichAsset>[ImmichAsset(id: 'a1')],
                current: const ImmichAsset(id: 'a1'),
                loading: false,
                cached: <CachedAsset>[_cached('a1', first)],
              ),
            );
            return controller;
          }),
          settingsRepositoryProvider.overrideWithValue(
            InMemorySettingsRepository(
              const AppSettings(
                overlays: OverlaySettings(
                  clock: false,
                  weather: true,
                  weatherLatitude: 1,
                  weatherLongitude: 2,
                ),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SlideshowScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.weatherCalls, 1);
  });

  testWidgets('adaptive background none renders no filtered layer', (
    tester,
  ) async {
    final dir = _tempDir();
    final first = _image(dir, 'plain');
    await _pump(
      tester,
      SlideshowViewState(
        assets: const <ImmichAsset>[ImmichAsset(id: 'bg1')],
        current: const ImmichAsset(id: 'bg1'),
        loading: false,
        cached: <CachedAsset>[_cached('bg1', first)],
      ),
      settings: const AppSettings(
        overlays: OverlaySettings(clock: false),
        defaultProfile: AspectProfile(
          imageMotion: false,
          adaptiveBackground: AdaptiveBackground.none,
        ),
      ),
    );

    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('adaptive background blurred cover renders a filtered layer', (
    tester,
  ) async {
    final dir = _tempDir();
    final first = _image(dir, 'blurred');
    await _pump(
      tester,
      SlideshowViewState(
        assets: const <ImmichAsset>[ImmichAsset(id: 'bg2')],
        current: const ImmichAsset(id: 'bg2'),
        loading: false,
        cached: <CachedAsset>[_cached('bg2', first)],
      ),
      settings: const AppSettings(
        overlays: OverlaySettings(clock: false),
        defaultProfile: AspectProfile(
          imageMotion: false,
          adaptiveBackground: AdaptiveBackground.blurredCover,
        ),
      ),
    );

    expect(find.byType(ImageFiltered), findsOneWidget);
  });
}
