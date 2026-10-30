import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/media/playback.dart';

/// Full video playback for a single slide.
class VideoSlide extends ConsumerStatefulWidget {
  const VideoSlide({
    super.key,
    required this.sourceBuilder,
    required this.muted,
    required this.playing,
    required this.fit,
    required this.fallback,
    this.loop = false,
    this.bounce = false,
    this.onCompleted,
    this.onError,
    this.fallbackSourceBuilder,
    this.preloadedPlayback,
  });

  final Future<PlaybackSource?> Function() sourceBuilder;
  final Future<PlaybackSource?> Function()? fallbackSourceBuilder;
  final bool muted;
  final bool playing;
  final BoxFit fit;
  final Widget fallback;
  final bool loop;
  /// Plays forward then backward while the slide is visible.
  final bool bounce;
  final VoidCallback? onCompleted;
  final ValueChanged<String>? onError;
  final MediaPlayback? preloadedPlayback;

  @override
  ConsumerState<VideoSlide> createState() => _VideoSlideState();
}

class _VideoSlideState extends ConsumerState<VideoSlide> {
  MediaPlayback? _playback;
  StreamSubscription<PlaybackSnapshot>? _subscription;
  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  bool _sourceError = false;
  bool _completedNotified = false;
  bool _errorNotified = false;
  bool _fallbackAttempted = false;
  bool _hasStarted = false;
  bool _preloaded = false;
  bool _reverse = false;
  bool _bouncing = false;

  @override
  void initState() {
    super.initState();
    // Defer player creation until after the first frame so the still/fallback
    // renders immediately instead of waiting on media_kit startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final playback =
          widget.preloadedPlayback ?? ref.read(mediaPlaybackFactoryProvider)();
      _preloaded = widget.preloadedPlayback != null;
      setState(() => _playback = playback);
      _subscription = playback.snapshots.listen(_onSnapshot);
      unawaited(_preloaded ? _startPreloaded(playback) : _open());
    });
  }

  Future<void> _startPreloaded(MediaPlayback playback) async {
    _reverse = false;
    await playback.setMuted(widget.muted);
    if (widget.playing) {
      await playback.play();
    }
  }

  Future<void> _open() async {
    final playback = _playback;
    if (playback == null) {
      return;
    }
    PlaybackSource? source;
    try {
      source = await widget.sourceBuilder();
    } on Object {
      source = null;
    }
    if (!mounted) {
      return;
    }
    if (source == null) {
      setState(() => _sourceError = true);
      return;
    }
    _sourceError = false;
    _completedNotified = false;
    _errorNotified = false;
    _fallbackAttempted = false;
    _reverse = false;
    try {
      await playback.open(
        source,
        muted: widget.muted,
        autoPlay: widget.playing,
      );
    } on Object {
      // The playback layer reports the failure through its snapshot stream.
    }
  }

  void _onSnapshot(PlaybackSnapshot snapshot) {
    if (!mounted) {
      return;
    }
    if (snapshot.phase == PlaybackPhase.playing ||
        snapshot.phase == PlaybackPhase.completed ||
        (_preloaded && snapshot.phase == PlaybackPhase.paused)) {
      _hasStarted = true;
    }
    setState(() => _snapshot = snapshot);
    if (snapshot.phase == PlaybackPhase.completed) {
      if (_completedNotified) {
        return;
      }
      _completedNotified = true;
      if (widget.bounce) {
        unawaited(_bounce());
      } else if (widget.loop) {
        final playback = _playback;
        if (playback != null) {
          unawaited(playback.seek(Duration.zero));
          unawaited(playback.play());
        }
      } else {
        widget.onCompleted?.call();
      }
    } else {
      _completedNotified = false;
      if (snapshot.phase == PlaybackPhase.failed && !_errorNotified) {
        if (!_fallbackAttempted && widget.fallbackSourceBuilder != null) {
          _fallbackAttempted = true;
          unawaited(_openFallback(snapshot.error ?? 'Playback failed'));
          return;
        }
        _errorNotified = true;
        widget.onError?.call(snapshot.error ?? 'Playback failed');
      }
    }
  }

  Future<void> _openFallback(String error) async {
    final playback = _playback;
    if (playback == null) {
      return;
    }
    PlaybackSource? source;
    try {
      source = await widget.fallbackSourceBuilder?.call();
    } on Object {
      source = null;
    }
    if (!mounted) {
      return;
    }
    if (source == null) {
      _errorNotified = true;
      widget.onError?.call(error);
      return;
    }
    try {
      await playback.open(
        source,
        muted: widget.muted,
        autoPlay: widget.playing,
      );
    } on Object {
      // The playback layer reports the failure through its snapshot stream.
    }
  }

  /// Steps backward frame by frame on completion, then plays forward again.
  Future<void> _bounce() async {
    if (_bouncing) {
      return;
    }
    _bouncing = true;
    try {
      final playback = _playback;
      if (playback == null) {
        return;
      }
      final duration = _snapshot.duration;
      if (duration == null || duration <= Duration.zero) {
        _reverse = false;
        await playback.seek(Duration.zero);
        if (widget.playing) {
          await playback.play();
        }
        return;
      }
      _reverse = true;
      await playback.pause();
      final target = duration - const Duration(milliseconds: 1);
      await playback.seek(target < Duration.zero ? Duration.zero : target);
      var steps = 0;
      final maxSteps = (duration.inMilliseconds / 33).ceil() + 20;
      while (mounted && _reverse) {
        if (!widget.playing) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          continue;
        }
        final ok = await playback.stepBackward();
        if (!ok) {
          // ponytail: no reverse frame stepping? restart forward from zero.
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 33));
        steps++;
        if (_snapshot.position <= const Duration(milliseconds: 50) ||
            steps > maxSteps) {
          break;
        }
      }
      _reverse = false;
      await playback.seek(Duration.zero);
      if (widget.playing) {
        await playback.play();
      }
    } finally {
      _bouncing = false;
    }
  }

  @override
  void didUpdateWidget(VideoSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    final playback = _playback;
    if (playback == null) {
      return;
    }
    if (oldWidget.muted != widget.muted) {
      unawaited(playback.setMuted(widget.muted));
    }
    if (oldWidget.playing != widget.playing) {
      unawaited(widget.playing ? playback.play() : playback.pause());
    }
  }

  @override
  void dispose() {
    final subscription = _subscription;
    final playback = _playback;
    _subscription = null;
    _playback = null;
    _reverse = false;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    if (playback != null) {
      unawaited(playback.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = _playback;
    if (playback == null ||
        _sourceError ||
        _snapshot.phase == PlaybackPhase.failed ||
        !_hasStarted) {
      return widget.fallback;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.fallback,
        SizedBox.expand(child: playback.video(fit: widget.fit)),
      ],
    );
  }
}
