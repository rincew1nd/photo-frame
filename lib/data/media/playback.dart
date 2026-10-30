import 'package:flutter/widgets.dart';

class PlaybackSource {
  const PlaybackSource({
    required this.uri,
    this.headers = const <String, String>{},
  });

  final String uri;
  final Map<String, String> headers;
}

enum PlaybackPhase { idle, loading, playing, paused, completed, failed }

class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.phase = PlaybackPhase.idle,
    this.position = Duration.zero,
    this.duration,
    this.error,
  });

  final PlaybackPhase phase;
  final Duration position;
  final Duration? duration;
  final String? error;
}

abstract class MediaPlayback {
  Stream<PlaybackSnapshot> get snapshots;

  Future<void> open(
    PlaybackSource source, {
    required bool muted,
    required bool autoPlay,
  });

  Future<void> play();

  Future<void> pause();

  Future<void> setMuted(bool muted);

  Future<void> seek(Duration position);

  /// Switches playback direction. Returns true when reverse is active.
  Future<bool> setReverse(bool reverse) async => false;

  Future<void> dispose();

  Widget video({required BoxFit fit});
}

typedef MediaPlaybackFactory = MediaPlayback Function();
