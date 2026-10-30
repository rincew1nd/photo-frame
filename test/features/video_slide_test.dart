import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/media/playback.dart';
import 'package:photoframe/features/slideshow/video_slide.dart';

import '../support/fake_media_playback.dart';

Future<void> _pump(
  WidgetTester tester,
  FakeMediaPlayback fake,
  VideoSlide slide,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mediaPlaybackFactoryProvider.overrideWithValue(() => fake),
      ],
      child: MaterialApp(home: Scaffold(body: slide)),
    ),
  );
  await tester.pump();
}

VideoSlide _slide({
  Future<PlaybackSource?> Function()? sourceBuilder,
  Future<PlaybackSource?> Function()? fallbackSourceBuilder,
  bool muted = true,
  bool playing = false,
  bool loop = false,
  VoidCallback? onCompleted,
  ValueChanged<String>? onError,
}) {
  return VideoSlide(
    sourceBuilder:
        sourceBuilder ??
        () async => const PlaybackSource(uri: 'file:///video.mp4'),
    fallbackSourceBuilder: fallbackSourceBuilder,
    muted: muted,
    playing: playing,
    fit: BoxFit.cover,
    fallback: const Text('fallback'),
    loop: loop,
    onCompleted: onCompleted,
    onError: onError,
  );
}

void main() {
  testWidgets('fallback renders on the first frame before playback is created', (
    tester,
  ) async {
    final fake = FakeMediaPlayback()..emitOnOpen = false;
    addTearDown(fake.dispose);
    var created = 0;
    var createdAtFirstFallbackBuild = -1;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaPlaybackFactoryProvider.overrideWithValue(() {
            created++;
            return fake;
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: VideoSlide(
              sourceBuilder: () async =>
                  const PlaybackSource(uri: 'file:///video.mp4'),
              muted: true,
              playing: false,
              fit: BoxFit.cover,
              fallback: Builder(
                builder: (_) {
                  if (createdAtFirstFallbackBuild == -1) {
                    createdAtFirstFallbackBuild = created;
                  }
                  return const Text('fallback');
                },
              ),
            ),
          ),
        ),
      ),
    );

    // The still is built on the first frame, before the post-frame callback
    // creates the playback.
    expect(createdAtFirstFallbackBuild, 0);
    expect(created, 1);
    expect(find.text('fallback'), findsOneWidget);
    expect(find.text('fake-video'), findsNothing);
  });

  testWidgets('opens the source and renders the video surface', (
    tester,
  ) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);

    await _pump(tester, fake, _slide(muted: false, playing: true));

    expect(fake.openedSource?.uri, 'file:///video.mp4');
    expect(fake.openedMuted, isFalse);
    expect(fake.openedAutoPlay, isTrue);
    expect(fake.muted, isFalse);
    expect(find.text('fake-video'), findsOneWidget);
  });

  testWidgets('fallback stays visible until playback starts', (tester) async {
    final fake = FakeMediaPlayback()..emitOnOpen = false;
    addTearDown(fake.dispose);

    await _pump(tester, fake, _slide());

    expect(find.text('fallback'), findsOneWidget);
    expect(find.text('fake-video'), findsNothing);

    fake.emit(const PlaybackSnapshot(phase: PlaybackPhase.playing));
    // Stream delivery is async; give the snapshot a frame to arrive.
    await tester.pump();
    await tester.pump();
    expect(find.text('fallback'), findsOneWidget);
    expect(find.text('fake-video'), findsOneWidget);
  });

  testWidgets('completion notifies exactly once', (tester) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);
    var completions = 0;

    await _pump(tester, fake, _slide(onCompleted: () => completions++));

    fake.emit(const PlaybackSnapshot(phase: PlaybackPhase.completed));
    await tester.pump();
    fake.emit(const PlaybackSnapshot(phase: PlaybackPhase.completed));
    await tester.pump();

    expect(completions, 1);
  });

  testWidgets('loop seeks to zero and plays instead of completing', (
    tester,
  ) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);
    var completions = 0;

    await _pump(
      tester,
      fake,
      _slide(playing: true, loop: true, onCompleted: () => completions++),
    );

    fake.emit(const PlaybackSnapshot(phase: PlaybackPhase.completed));
    await tester.pump();

    expect(completions, 0);
    expect(fake.seekCalls, 1);
    expect(fake.lastSeek, Duration.zero);
    expect(fake.playCalls, 1);
    expect(fake.playing, isTrue);
  });

  testWidgets('failed playback renders fallback and reports the error', (
    tester,
  ) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);
    final errors = <String>[];

    await _pump(tester, fake, _slide(onError: errors.add));

    fake.emit(
      const PlaybackSnapshot(phase: PlaybackPhase.failed, error: 'boom'),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('fallback'), findsOneWidget);
    expect(find.text('fake-video'), findsNothing);
    expect(errors, <String>['boom']);
  });

  testWidgets('failed playback retries with fallback source', (tester) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);
    var completions = 0;
    var fallbackCalls = 0;

    await _pump(
      tester,
      fake,
      _slide(
        playing: true,
        fallbackSourceBuilder: () async {
          fallbackCalls++;
          return const PlaybackSource(uri: 'file:///playback.mp4');
        },
        onCompleted: () => completions++,
      ),
    );

    fake.emit(
      const PlaybackSnapshot(phase: PlaybackPhase.failed, error: 'boom'),
    );
    await tester.pump();
    await tester.pump();

    expect(fallbackCalls, 1);
    expect(fake.openedSources, hasLength(2));
    expect(fake.openedSources.last.uri, 'file:///playback.mp4');
    expect(find.text('fake-video'), findsOneWidget);

    fake.emit(const PlaybackSnapshot(phase: PlaybackPhase.completed));
    await tester.pump();
    expect(completions, 1);
  });

  testWidgets('fallback source returning null reports the error once', (
    tester,
  ) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);
    final errors = <String>[];

    await _pump(
      tester,
      fake,
      _slide(fallbackSourceBuilder: () async => null, onError: errors.add),
    );

    fake.emit(
      const PlaybackSnapshot(phase: PlaybackPhase.failed, error: 'boom'),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('fallback'), findsOneWidget);
    expect(find.text('fake-video'), findsNothing);
    expect(errors, <String>['boom']);
  });

  testWidgets('fallback playback failure reports the error once', (
    tester,
  ) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);
    final errors = <String>[];

    await _pump(
      tester,
      fake,
      _slide(
        fallbackSourceBuilder: () async =>
            const PlaybackSource(uri: 'file:///playback.mp4'),
        onError: errors.add,
      ),
    );

    fake.emit(
      const PlaybackSnapshot(phase: PlaybackPhase.failed, error: 'boom'),
    );
    await tester.pump();
    await tester.pump();
    fake.emit(
      const PlaybackSnapshot(phase: PlaybackPhase.failed, error: 'no fallback'),
    );
    fake.emit(
      const PlaybackSnapshot(phase: PlaybackPhase.failed, error: 'no fallback'),
    );
    await tester.pump();
    await tester.pump();

    expect(fake.openedSources, hasLength(2));
    expect(find.text('fallback'), findsOneWidget);
    expect(find.text('fake-video'), findsNothing);
    expect(errors, <String>['no fallback']);
  });

  testWidgets('null source renders fallback without opening playback', (
    tester,
  ) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);

    await _pump(tester, fake, _slide(sourceBuilder: () async => null));

    expect(fake.openedSource, isNull);
    expect(find.text('fallback'), findsOneWidget);
    expect(find.text('fake-video'), findsNothing);
  });

  testWidgets('didUpdateWidget forwards mute and playing changes', (
    tester,
  ) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);

    await _pump(tester, fake, _slide(muted: true, playing: false));
    expect(fake.muted, isTrue);

    await _pump(tester, fake, _slide(muted: false, playing: true));
    await tester.pump();
    expect(fake.muted, isFalse);
    expect(fake.playCalls, 1);

    await _pump(tester, fake, _slide(muted: false, playing: false));
    await tester.pump();
    expect(fake.pauseCalls, 1);
  });

  testWidgets('disposing the widget disposes the playback', (tester) async {
    final fake = FakeMediaPlayback();
    addTearDown(fake.dispose);

    await _pump(tester, fake, _slide());
    expect(fake.disposed, isFalse);

    await tester.pumpWidget(const SizedBox());
    expect(fake.disposed, isTrue);
  });
}
