import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photoframe/data/media/playback.dart';

/// In-memory [MediaPlayback] for widget tests.
class FakeMediaPlayback implements MediaPlayback {
  final StreamController<PlaybackSnapshot> _controller =
      StreamController<PlaybackSnapshot>.broadcast();

  PlaybackSource? openedSource;
  final List<PlaybackSource> openedSources = <PlaybackSource>[];
  bool? openedMuted;
  bool? openedAutoPlay;
  bool muted = false;
  bool playing = false;
  int playCalls = 0;
  int pauseCalls = 0;
  int seekCalls = 0;
  Duration position = Duration.zero;
  bool disposed = false;
  bool emitOnOpen = true;
  Duration? lastSeek;

  @override
  Stream<PlaybackSnapshot> get snapshots => _controller.stream;

  @override
  Future<void> open(
    PlaybackSource source, {
    required bool muted,
    required bool autoPlay,
  }) async {
    openedSource = source;
    openedSources.add(source);
    openedMuted = muted;
    openedAutoPlay = autoPlay;
    this.muted = muted;
    playing = autoPlay;
    if (emitOnOpen) {
      emit(
        PlaybackSnapshot(
          phase: autoPlay ? PlaybackPhase.playing : PlaybackPhase.paused,
        ),
      );
    }
  }

  @override
  Future<void> play() async {
    _checkDisposed();
    playCalls++;
    playing = true;
    emit(const PlaybackSnapshot(phase: PlaybackPhase.playing));
  }

  @override
  Future<void> pause() async {
    _checkDisposed();
    pauseCalls++;
    playing = false;
    emit(const PlaybackSnapshot(phase: PlaybackPhase.paused));
  }

  @override
  Future<void> setMuted(bool muted) async {
    this.muted = muted;
    emit(
      PlaybackSnapshot(
        phase: playing ? PlaybackPhase.playing : PlaybackPhase.paused,
      ),
    );
  }

  @override
  Future<void> seek(Duration position) async {
    _checkDisposed();
    seekCalls++;
    lastSeek = position;
    this.position = position;
    emit(
      PlaybackSnapshot(
        phase: playing ? PlaybackPhase.playing : PlaybackPhase.paused,
        position: position,
      ),
    );
  }

  void _checkDisposed() {
    if (disposed) {
      throw StateError('"[Player] has been disposed"');
    }
  }

  void emit(PlaybackSnapshot snapshot) {
    if (!_controller.isClosed) {
      _controller.add(snapshot);
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    // ponytail: closing in a widget test zone can leave the done future pending
    unawaited(_controller.close());
  }

  @override
  Widget video({required BoxFit fit}) {
    return ColoredBox(
      color: const Color(0xFF000000),
      child: const Center(child: Text('fake-video')),
    );
  }
}
