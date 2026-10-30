import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoframe/data/media/playback.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/features/slideshow/video_slide.dart';

/// Live Photo motion playback: a still frame plus optional motion clip.
class LivePhotoSlide extends ConsumerStatefulWidget {
  const LivePhotoSlide({
    super.key,
    required this.mode,
    required this.sourceBuilder,
    required this.muted,
    required this.playing,
    required this.fit,
    required this.still,
  });

  final LivePhotoMode mode;
  final Future<PlaybackSource?> Function() sourceBuilder;
  final bool muted;
  final bool playing;
  final BoxFit fit;
  final Widget still;

  @override
  ConsumerState<LivePhotoSlide> createState() => _LivePhotoSlideState();
}

class _LivePhotoSlideState extends ConsumerState<LivePhotoSlide> {
  late bool _showStill = widget.mode == LivePhotoMode.off;

  @override
  void didUpdateWidget(LivePhotoSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode == widget.mode) {
      return;
    }
    if (widget.mode == LivePhotoMode.off) {
      _showStill = true;
    } else if (oldWidget.mode == LivePhotoMode.off) {
      _showStill = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == LivePhotoMode.off || _showStill) {
      return widget.still;
    }
    if (widget.mode == LivePhotoMode.loop) {
      return VideoSlide(
        key: const ValueKey<String>('live-loop'),
        sourceBuilder: widget.sourceBuilder,
        loop: true,
        muted: widget.muted,
        playing: widget.playing,
        fit: widget.fit,
        fallback: widget.still,
      );
    }
    return VideoSlide(
      key: const ValueKey<String>('live-once'),
      sourceBuilder: widget.sourceBuilder,
      loop: false,
      muted: widget.muted,
      playing: widget.playing,
      fit: widget.fit,
      fallback: widget.still,
      onCompleted: () {
        if (mounted) {
          setState(() => _showStill = true);
        }
      },
    );
  }
}
