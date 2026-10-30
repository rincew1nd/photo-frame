import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/media/playback.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/features/slideshow/live_photo_slide.dart';

import '../support/fake_media_playback.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget slide,
  MediaPlaybackFactory factory,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mediaPlaybackFactoryProvider.overrideWithValue(factory),
      ],
      child: MaterialApp(home: Scaffold(body: slide)),
    ),
  );
  await tester.pump();
}

LivePhotoSlide _slide({
  required LivePhotoMode mode,
  Future<PlaybackSource?> Function()? sourceBuilder,
  bool muted = true,
  bool playing = true,
}) {
  return LivePhotoSlide(
    mode: mode,
    sourceBuilder:
        sourceBuilder ??
        () async => const PlaybackSource(uri: 'file:///live.mov'),
    muted: muted,
    playing: playing,
    fit: BoxFit.cover,
    still: const Text('still'),
  );
}

void main() {
  testWidgets('off renders the still without creating playback', (
    tester,
  ) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);
    var created = 0;

    await _pump(tester, _slide(mode: LivePhotoMode.off), () {
      created++;
      return fake;
    });

    expect(find.text('still'), findsOneWidget);
    expect(find.text('fake-video'), findsNothing);
    expect(created, 0);
    expect(fake.openedSource, isNull);
  });

  testWidgets('live plays motion once then falls back to the still', (
    tester,
  ) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);

    await _pump(tester, _slide(mode: LivePhotoMode.live), () => fake);

    expect(fake.openedSource?.uri, 'file:///live.mov');
    expect(fake.openedMuted, isTrue);
    expect(fake.openedAutoPlay, isTrue);
    expect(find.text('fake-video'), findsOneWidget);
    expect(find.text('still'), findsNothing);

    fake.emit(const PlaybackSnapshot(phase: PlaybackPhase.completed));
    await tester.pump();
    await tester.pump();

    expect(find.text('still'), findsOneWidget);
    expect(find.text('fake-video'), findsNothing);
  });

  testWidgets('loop restarts motion on completion and keeps the still hidden', (
    tester,
  ) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);

    await _pump(tester, _slide(mode: LivePhotoMode.loop), () => fake);

    expect(find.text('fake-video'), findsOneWidget);

    fake.emit(const PlaybackSnapshot(phase: PlaybackPhase.completed));
    await tester.pump();
    await tester.pump();

    expect(fake.seekCalls, 1);
    expect(fake.lastSeek, Duration.zero);
    expect(fake.playCalls, 1);
    expect(find.text('fake-video'), findsOneWidget);
    expect(find.text('still'), findsNothing);
  });

  testWidgets('null source renders the still without opening', (tester) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);

    await _pump(
      tester,
      _slide(mode: LivePhotoMode.live, sourceBuilder: () async => null),
      () => fake,
    );
    await tester.pump();

    expect(fake.openedSource, isNull);
    expect(find.text('still'), findsOneWidget);
    expect(find.text('fake-video'), findsNothing);
  });

  testWidgets('failed playback renders the still', (tester) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);

    await _pump(tester, _slide(mode: LivePhotoMode.live), () => fake);

    fake.emit(
      const PlaybackSnapshot(phase: PlaybackPhase.failed, error: 'boom'),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('still'), findsOneWidget);
    expect(find.text('fake-video'), findsNothing);
  });

  testWidgets('mute and playing are forwarded to video playback', (
    tester,
  ) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);

    await _pump(
      tester,
      _slide(mode: LivePhotoMode.live, muted: true, playing: false),
      () => fake,
    );

    expect(fake.openedMuted, isTrue);
    expect(fake.openedAutoPlay, isFalse);
    expect(fake.muted, isTrue);
    expect(fake.playing, isFalse);
  });
}
