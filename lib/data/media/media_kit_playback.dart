import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:photoframe/data/media/playback.dart';

class MediaKitPlayback implements MediaPlayback {
  MediaKitPlayback() {
    MediaKit.ensureInitialized();
    _player = Player();
    // Android reference device fails to configure HEVC on the hardware path; use software decode.
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: !Platform.isAndroid,
      ),
    );
    final platform = _player.platform;
    if (platform is NativePlayer) {
      // ponytail: fixed SDR target; expose a tuning knob if HDR looks flat.
      unawaited(platform.setProperty('tone-mapping', 'bt.2446a'));
      unawaited(platform.setProperty('hdr-compute-peak', 'yes'));
      unawaited(platform.setProperty('target-peak', '100'));
      // ponytail: lets reverse seeking land cleanly for bounce playback.
      unawaited(platform.setProperty('hr-seek', 'yes'));
    }
    _subscriptions.addAll(<StreamSubscription<Object?>>[
      _player.stream.playing.listen((playing) {
        _playing = playing;
        _emit();
      }),
      _player.stream.position.listen((position) {
        _position = position;
        _emit();
      }),
      _player.stream.duration.listen((duration) {
        _duration = duration;
        _emit();
      }),
      _player.stream.buffering.listen((buffering) {
        _buffering = buffering;
        _emit();
      }),
      _player.stream.completed.listen((completed) {
        _completed = completed;
        _emit();
      }),
      _player.stream.error.listen((error) {
        _error = error;
        _emit();
      }),
    ]);
  }

  final StreamController<PlaybackSnapshot> _snapshots =
      StreamController<PlaybackSnapshot>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  late final Player _player;
  late final VideoController _controller;

  bool _opened = false;
  bool _disposed = false;
  bool _playing = false;
  bool _buffering = false;
  bool _completed = false;
  String? _error;
  Duration _position = Duration.zero;
  Duration? _duration;

  @override
  Stream<PlaybackSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<void> open(
    PlaybackSource source, {
    required bool muted,
    required bool autoPlay,
  }) async {
    _opened = true;
    _playing = false;
    _buffering = false;
    _completed = false;
    _error = null;
    _position = Duration.zero;
    _duration = null;
    _emit();

    await _player.setVolume(muted ? 0 : 100);
    try {
      await _player.open(
        Media(source.uri, httpHeaders: source.headers),
        play: autoPlay,
      );
    } on Object catch (error) {
      _error = error.toString();
      _emit();
      rethrow;
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> setMuted(bool muted) => _player.setVolume(muted ? 0 : 100);

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<bool> stepBackward() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) {
      return false;
    }
    try {
      await platform.command(<String>['frame-back-step']);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget video({required BoxFit fit}) {
    return Video(
      controller: _controller,
      fit: fit,
      // ponytail: media_kit's NoVideoControls is untyped null in 2.0.1; strict-casts rejects it.
      controls: null,
      wakelock: false,
      pauseUponEnteringBackgroundMode: true,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _snapshots.close();
    await _player.dispose();
  }

  void _emit() {
    if (_disposed || _snapshots.isClosed) {
      return;
    }
    _snapshots.add(
      PlaybackSnapshot(
        phase: _phase,
        position: _position,
        duration: _duration,
        error: _error,
      ),
    );
  }

  PlaybackPhase get _phase {
    if (_error != null) {
      return PlaybackPhase.failed;
    }
    if (!_opened) {
      return PlaybackPhase.idle;
    }
    if (_completed) {
      return PlaybackPhase.completed;
    }
    if (_buffering) {
      return PlaybackPhase.loading;
    }
    if (_playing) {
      return PlaybackPhase.playing;
    }
    return PlaybackPhase.paused;
  }
}
