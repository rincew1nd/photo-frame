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
    this.onCompleted,
    this.onError,
  });

  final Future<PlaybackSource?> Function() sourceBuilder;
  final bool muted;
  final bool playing;
  final BoxFit fit;
  final Widget fallback;
  final bool loop;
  final VoidCallback? onCompleted;
  final ValueChanged<String>? onError;

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

  @override
  void initState() {
    super.initState();
    final playback = ref.read(mediaPlaybackFactoryProvider)();
    _playback = playback;
    _subscription = playback.snapshots.listen(_onSnapshot);
    unawaited(_open());
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
    setState(() => _snapshot = snapshot);
    if (snapshot.phase == PlaybackPhase.completed) {
      if (_completedNotified) {
        return;
      }
      _completedNotified = true;
      if (widget.loop) {
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
        _errorNotified = true;
        widget.onError?.call(snapshot.error ?? 'Playback failed');
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
        _snapshot.phase == PlaybackPhase.failed) {
      return widget.fallback;
    }
    return SizedBox.expand(child: playback.video(fit: widget.fit));
  }
}
