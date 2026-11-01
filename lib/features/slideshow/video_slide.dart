import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/media/playback.dart';
import 'package:photoframe/platform/services.dart';

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
  late final AudioFocusService _audioFocus;
  StreamSubscription<AudioFocusEvent>? _focusSubscription;
  bool _hasFocus = false;
  bool _resumeAfterFocusGain = false;

  @override
  void initState() {
    super.initState();
    _audioFocus = ref.read(audioFocusServiceProvider);
    _focusSubscription = _audioFocus.events.listen(_onAudioFocus);
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
      await _ensureAudioFocus();
      await playback.play();
    }
  }

  Future<void> _ensureAudioFocus() async {
    if (widget.muted || !widget.playing || _hasFocus) {
      return;
    }
    _hasFocus = await _audioFocus.request();
  }

  void _releaseAudioFocus() {
    if (!_hasFocus) {
      return;
    }
    _hasFocus = false;
    unawaited(_audioFocus.abandon());
  }

  void _onAudioFocus(AudioFocusEvent event) {
    final playback = _playback;
    switch (event) {
      case AudioFocusEvent.transient:
        if (!_hasFocus) {
          return;
        }
        _resumeAfterFocusGain = widget.playing;
        if (playback != null) {
          unawaited(playback.pause());
        }
      case AudioFocusEvent.lost:
        if (!_hasFocus) {
          _resumeAfterFocusGain = false;
          return;
        }
        _hasFocus = false;
        _resumeAfterFocusGain = false;
        if (playback != null) {
          unawaited(playback.pause());
        }
      case AudioFocusEvent.gain:
        if (!_hasFocus) {
          _resumeAfterFocusGain = false;
          return;
        }
        if (_resumeAfterFocusGain && widget.playing && !widget.muted) {
          _resumeAfterFocusGain = false;
          if (playback != null) {
            unawaited(playback.play());
          }
        }
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
    await _ensureAudioFocus();
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
        _releaseAudioFocus();
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
      _releaseAudioFocus();
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

  /// Seeks backward in short steps on completion, then plays forward again.
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
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final target = duration - const Duration(milliseconds: 300);
      await playback.seek(target < Duration.zero ? Duration.zero : target);
      var reversePosition = target;
      while (mounted && _reverse && reversePosition > Duration.zero) {
        if (!widget.playing) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          continue;
        }
        reversePosition -= const Duration(milliseconds: 100);
        if (reversePosition < Duration.zero) reversePosition = Duration.zero;
        await playback.seek(reversePosition);
        await Future<void>.delayed(const Duration(milliseconds: 100));
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

  Future<void> _applyPlaybackChanges(
    MediaPlayback playback,
    VideoSlide oldWidget,
  ) async {
    if (oldWidget.muted != widget.muted) {
      await playback.setMuted(widget.muted);
    }
    if (widget.playing && !widget.muted) {
      await _ensureAudioFocus();
    } else {
      _resumeAfterFocusGain = false;
      _releaseAudioFocus();
    }
    if (oldWidget.playing != widget.playing) {
      if (widget.playing) {
        await playback.play();
      } else {
        await playback.pause();
      }
    }
  }

  @override
  void didUpdateWidget(VideoSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    final playback = _playback;
    if (playback == null) {
      return;
    }
    if (oldWidget.muted != widget.muted ||
        oldWidget.playing != widget.playing) {
      unawaited(_applyPlaybackChanges(playback, oldWidget));
    }
  }

  @override
  void dispose() {
    final subscription = _subscription;
    final focusSubscription = _focusSubscription;
    final playback = _playback;
    _subscription = null;
    _focusSubscription = null;
    _playback = null;
    _reverse = false;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    if (focusSubscription != null) {
      unawaited(focusSubscription.cancel());
    }
    _releaseAudioFocus();
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
