import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photoframe/app/connection_providers.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/data/media/playback.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/weather/weather_service.dart';
import 'package:photoframe/domain/media/ken_burns.dart';
import 'package:photoframe/domain/media/media_filters.dart';
import 'package:photoframe/features/slideshow/live_photo_slide.dart';
import 'package:photoframe/features/slideshow/slideshow_controller.dart';
import 'package:photoframe/features/slideshow/video_slide.dart';
import 'package:photoframe/platform/paths.dart';

/// Full-screen slideshow with overlays, controls, and Ken Burns motion.
class SlideshowScreen extends ConsumerStatefulWidget {
  const SlideshowScreen({super.key});

  @override
  ConsumerState<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends ConsumerState<SlideshowScreen> {
  bool _controlsVisible = false;
  bool _weatherRequested = false;
  String? _derivationAssetId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _weatherRequested) {
        return;
      }
      final settings = ref.read(settingsControllerProvider).value;
      if (settings?.overlays.weather == true) {
        _weatherRequested = true;
        ref.read(slideshowControllerProvider.notifier).refreshWeather();
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
  }

  void _scheduleDerivation(CachedAsset? cached) {
    if (cached == null ||
        cached.type == MediaKind.video ||
        cached.isDecodableImage ||
        fileIfExists(cached.derivedImagePath) != null) {
      return;
    }
    if (_derivationAssetId == cached.id) {
      return;
    }
    _derivationAssetId = cached.id;
    final media = MediaQuery.maybeOf(context);
    final target = media == null
        ? 1920
        : (media.size.longestSide * media.devicePixelRatio).round();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref
          .read(slideshowControllerProvider.notifier)
          .ensureDerived(cached, targetLongSide: target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(settingsControllerProvider).value ?? const AppSettings();
    final asyncState = ref.watch(slideshowControllerProvider);
    if (!_weatherRequested &&
        settings.overlays.weather &&
        asyncState.hasValue) {
      _weatherRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(slideshowControllerProvider.notifier).refreshWeather();
        }
      });
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const Center(
          child: Text(
            'Unable to load slideshow',
            style: TextStyle(color: Colors.white70),
          ),
        ),
        data: (state) {
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.assets.isEmpty) {
            return _noItems(state);
          }
          return _slideshow(state, settings);
        },
      ),
    );
  }

  Widget _noItems(SlideshowViewState state) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.photo_library_outlined,
                size: 56,
                color: Colors.white54,
              ),
              const SizedBox(height: 16),
              Text(
                state.error ?? SlideshowController.noItemsMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    onPressed: () {
                      ref.read(slideshowControllerProvider.notifier).syncNow();
                    },
                    child: const Text('Sync now'),
                  ),
                  OutlinedButton(
                    onPressed: () => context.push('/settings'),
                    child: const Text('Settings'),
                  ),
                  OutlinedButton(
                    onPressed: () => context.go('/albums'),
                    child: const Text('Albums'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slideshow(SlideshowViewState state, AppSettings settings) {
    final current = state.current;
    final cached = _cachedFor(current?.id, state.cached);
    _scheduleDerivation(cached);
    final resolver = CustomizationResolver(
      defaultProfile: settings.defaultProfile,
      customizations: settings.customizations,
    );
    final profile = resolver.resolve(current);
    final fit = resolver.effectiveFit(current);
    final kind = cached?.type ?? current?.type ?? MediaKind.photo;
    final isVideo = kind == MediaKind.video;
    final showsOverlays =
        !state.nightMode || !settings.nightMode.hideOverlays;
    final motion =
        fit == ImageFit.cover &&
        profile.imageMotion &&
        profile.panStrength > 0;
    final media = _media(
      cached,
      fit,
      motion,
      profile,
      current,
      settings.playback.intervalSeconds,
      state.progress,
      settings,
      state.playing,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SizedBox.expand(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, animation) =>
                  _transition(settings.playback.transition, child, animation),
              child: KeyedSubtree(
                key: ValueKey<String>(current?.id ?? 'empty'),
                child: media,
              ),
            ),
          ),
          if (isVideo &&
              settings.playback.videoPlaybackMode != VideoPlaybackMode.full)
            const Positioned.fill(child: IgnorePointer(child: _VideoLabel())),
          if (showsOverlays)
            Positioned.fill(
              child: SafeArea(
                child: Stack(
                  children: [
                    if (settings.overlays.clock)
                      const Positioned(
                        top: 16,
                        left: 16,
                        child: _ClockOverlay(),
                      ),
                    if (settings.overlays.weather && state.weather != null)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: _weatherOverlay(state.weather!),
                      ),
                    if (settings.overlays.metadata && current?.exif != null)
                      Positioned(
                        left: 16,
                        bottom: 96,
                        child: _metadataOverlay(current!),
                      ),
                  ],
                ),
              ),
            ),
          if (state.nightMode)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(
                    alpha: settings.nightMode.dimOpacity,
                  ),
                  child: const Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Icon(
                        Icons.dark_mode,
                        size: 20,
                        color: Colors.white24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          _controls(state, settings),
        ],
      ),
    );
  }

  Widget _transition(
    TransitionType type,
    Widget child,
    Animation<double> animation,
  ) {
    switch (type) {
      case TransitionType.fade:
        return FadeTransition(opacity: animation, child: child);
      case TransitionType.zoom:
        return ScaleTransition(scale: animation, child: child);
      case TransitionType.slide:
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      case TransitionType.none:
        return child;
    }
  }

  Widget _media(
    CachedAsset? cached,
    ImageFit fit,
    bool motion,
    AspectProfile profile,
    ImmichAsset? current,
    int intervalSeconds,
    double progress,
    AppSettings settings,
    bool playing,
  ) {
    if (cached == null) {
      return _missingImage();
    }
    final display = displayFileFor(cached);
    if (display == null) {
      return _missingImage();
    }
    final thumbnail = fileIfExists(cached.thumbnailPath);
    final boxFit = fit == ImageFit.cover ? BoxFit.cover : BoxFit.contain;
    final imageAspect = _imageAspect(cached, current);
    final slideSeconds =
        cached.type == MediaKind.video &&
            settings.playback.videoPlaybackMode == VideoPlaybackMode.full &&
            (current?.duration ?? 0) > 0
        ? ((current!.duration! + 999) ~/ 1000).clamp(2, 300)
        : intervalSeconds;
    if (cached.type == MediaKind.video &&
        settings.playback.videoPlaybackMode == VideoPlaybackMode.full) {
      final video = VideoSlide(
        key: ValueKey<String>('video-${cached.id}'),
        sourceBuilder: () => _playbackSourceFor(cached),
        fallbackSourceBuilder: () => _videoFallbackSourceFor(cached),
        muted: settings.playback.muted,
        playing: playing,
        fit: boxFit,
        fallback: _SlideImage(file: display, thumbnail: thumbnail, fit: boxFit),
        onCompleted: () => ref
            .read(slideshowControllerProvider.notifier)
            .advanceIfCurrent(cached.id),
      );
      if (!motion) {
        return video;
      }
      return _KenBurns(
        key: ValueKey<String>(
          'ken-burns-video-${cached.id}-${profile.panStrength}-$imageAspect',
        ),
        enabled: motion,
        pan: profile.panStrength,
        imageAspect: imageAspect,
        imageFile: display,
        intervalSeconds: slideSeconds,
        progress: progress,
        child: video,
      );
    }
    if (cached.type == MediaKind.livePhoto &&
        settings.playback.livePhotoMode != LivePhotoMode.off) {
      return _KenBurns(
        key: ValueKey<String>(
          'ken-burns-live-${cached.id}-${profile.panStrength}-$imageAspect',
        ),
        enabled: motion,
        pan: profile.panStrength,
        imageAspect: imageAspect,
        imageFile: display,
        intervalSeconds: slideSeconds,
        progress: progress,
        child: LivePhotoSlide(
          key: ValueKey<String>('live-${cached.id}'),
          mode: settings.playback.livePhotoMode,
          sourceBuilder: () => _livePlaybackSourceFor(cached),
          muted: settings.playback.muted,
          playing: playing,
          fit: boxFit,
          still: _SlideImage(file: display, thumbnail: thumbnail, fit: boxFit),
        ),
      );
    }
    final foreground = _KenBurns(
      key: ValueKey<String>(
        'ken-burns-${current?.id ?? cached.id}-${profile.panStrength}-$imageAspect',
      ),
      enabled: motion,
      pan: profile.panStrength,
      imageAspect: imageAspect,
      imageFile: display,
      intervalSeconds: slideSeconds,
      progress: progress,
      child: _SlideImage(file: display, thumbnail: thumbnail, fit: boxFit),
    );
    final sigma = switch (profile.adaptiveBackground) {
      AdaptiveBackground.none => null,
      AdaptiveBackground.ambientGlow => 40.0,
      AdaptiveBackground.blurredCover => 24.0,
    };
    if (sigma == null) {
      return foreground;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: _SlideImage(
            file: display,
            thumbnail: thumbnail,
            fit: BoxFit.cover,
          ),
        ),
        const ColoredBox(color: Colors.black38),
        foreground,
      ],
    );
  }

  double _imageAspect(CachedAsset cached, ImmichAsset? current) {
    final cachedWidth = cached.width;
    final cachedHeight = cached.height;
    if (cachedWidth != null &&
        cachedHeight != null &&
        cachedWidth > 0 &&
        cachedHeight > 0) {
      return cachedWidth / cachedHeight;
    }
    final width = current?.width;
    final height = current?.height;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return 0;
  }

  Future<PlaybackSource?> _playbackSourceFor(CachedAsset asset) async {
    try {
      final local = fileIfExists(asset.originalPath);
      if (local != null) {
        return PlaybackSource(uri: local.path);
      }
      final client = await ref
          .read(connectionControllerProvider.notifier)
          .clientFromStoredCredentials();
      return PlaybackSource(
        uri:
            '${client.baseUri}/assets/${Uri.encodeComponent(asset.id)}/original',
        headers: client.authHeaders(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<PlaybackSource?> _videoFallbackSourceFor(CachedAsset asset) async {
    try {
      final client = await ref
          .read(connectionControllerProvider.notifier)
          .clientFromStoredCredentials();
      return PlaybackSource(
        uri:
            '${client.baseUri}/assets/${Uri.encodeComponent(asset.id)}/video/playback',
        headers: client.authHeaders(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<PlaybackSource?> _livePlaybackSourceFor(CachedAsset asset) async {
    try {
      final local = fileIfExists(asset.liveVideoPath);
      if (local != null) {
        return PlaybackSource(uri: local.path);
      }
      final videoId = asset.livePhotoVideoId;
      if (videoId == null || videoId.isEmpty) {
        return null;
      }
      final client = await ref
          .read(connectionControllerProvider.notifier)
          .clientFromStoredCredentials();
      return PlaybackSource(
        uri:
            '${client.baseUri}/assets/${Uri.encodeComponent(videoId)}/original',
        headers: client.authHeaders(),
      );
    } catch (_) {
      return null;
    }
  }

  Widget _missingImage() {
    return SizedBox.expand(
      child: ColoredBox(
        color: const Color(0xFF111111),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                size: 56,
                color: Colors.white38,
              ),
              const SizedBox(height: 12),
              const Text(
                'Image not cached',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () =>
                    ref.read(slideshowControllerProvider.notifier).syncNow(),
                child: const Text('Sync now'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _weatherOverlay(WeatherSnapshot weather) {
    final symbol = weather.unit.toLowerCase() == 'fahrenheit' ? '°F' : '°C';
    final location = weather.locationLabel.trim();
    return _overlayText(<String>[
      '${weather.temperature.round()}$symbol',
      weather.description,
      if (location.isNotEmpty) location,
    ]);
  }

  Widget _metadataOverlay(ImmichAsset asset) {
    final exif = asset.exif;
    final date = exif?.dateTimeOriginal ?? asset.fileCreatedAt;
    final location = exif?.city ?? exif?.state ?? exif?.country;
    final description = exif?.description;
    return _overlayText(<String>[
      if (date != null) _dateText(date),
      if (location != null && location.isNotEmpty) location,
      if (description != null && description.isNotEmpty) description,
    ]);
  }

  Widget _overlayText(List<String> lines) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Text(
            line,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              shadows: <Shadow>[Shadow(blurRadius: 8, color: Colors.black)],
            ),
          ),
      ],
    );
  }

  String _dateText(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Widget _controls(SlideshowViewState state, AppSettings settings) {
    final controller = ref.read(slideshowControllerProvider.notifier);
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedOpacity(
        key: const ValueKey<String>('slideshow-controls'),
        opacity: _controlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_controlsVisible,
          child: SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: state.progress,
                    backgroundColor: Colors.white24,
                    color: Colors.white,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip: 'Previous',
                        icon: const Icon(Icons.skip_previous),
                        color: Colors.white,
                        onPressed: controller.previous,
                      ),
                      IconButton(
                        tooltip: state.playing ? 'Pause' : 'Play',
                        icon: Icon(
                          state.playing ? Icons.pause : Icons.play_arrow,
                        ),
                        color: Colors.white,
                        onPressed: controller.togglePause,
                      ),
                      IconButton(
                        tooltip: 'Next',
                        icon: const Icon(Icons.skip_next),
                        color: Colors.white,
                        onPressed: controller.next,
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        icon: const Icon(Icons.settings_outlined),
                        color: Colors.white,
                        onPressed: () => context.push('/settings'),
                      ),
                      IconButton(
                        tooltip: 'Albums',
                        icon: const Icon(Icons.photo_library_outlined),
                        color: Colors.white,
                        onPressed: () => context.go('/albums'),
                      ),
                      IconButton(
                        tooltip: 'Sync',
                        icon: state.syncing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.sync),
                        color: Colors.white,
                        onPressed: state.syncing ? null : controller.syncNow,
                      ),
                      IconButton(
                        tooltip: 'Media selection',
                        icon: const Icon(Icons.checklist),
                        color: Colors.white,
                        onPressed: () => context.push('/media-selection'),
                      ),
                      IconButton(
                        tooltip: settings.playback.muted
                            ? 'Unmute audio'
                            : 'Mute audio',
                        icon: Icon(
                          settings.playback.muted
                              ? Icons.volume_off
                              : Icons.volume_up,
                        ),
                        color: Colors.white,
                        onPressed: () {
                          ref
                              .read(settingsControllerProvider.notifier)
                              .save(
                                (current) => current.copyWith(
                                  playback: current.playback.copyWith(
                                    muted: !current.playback.muted,
                                  ),
                                ),
                              );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  CachedAsset? _cachedFor(String? id, List<CachedAsset> cached) {
    if (id == null) {
      return null;
    }
    for (final asset in cached) {
      if (asset.id == id) {
        return asset;
      }
    }
    return null;
  }
}

/// Picks the file to render for [asset], preferring a decodable original.
File? displayFileFor(CachedAsset? asset) {
  if (asset == null) {
    return null;
  }
  final derived = fileIfExists(asset.derivedImagePath);
  if (derived != null) {
    return derived;
  }
  final original = fileIfExists(asset.originalPath);
  final thumbnail = fileIfExists(asset.thumbnailPath);
  if (asset.type == MediaKind.video) {
    return thumbnail;
  }
  if (asset.isDecodableImage) {
    return original ?? thumbnail;
  }
  return thumbnail;
}

class _SlideImage extends StatelessWidget {
  const _SlideImage({
    required this.file,
    required this.thumbnail,
    required this.fit,
  });

  final File file;
  final File? thumbnail;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Image.file(
        file,
        width: double.infinity,
        height: double.infinity,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          final fallback = thumbnail;
          if (fallback != null && fallback.path != file.path) {
            return Image.file(
              fallback,
              width: double.infinity,
              height: double.infinity,
              fit: fit,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) =>
                  const _ImagePlaceholder(),
            );
          }
          return const _ImagePlaceholder();
        },
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(
      child: ColoredBox(
        color: Color(0xFF111111),
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: 56,
            color: Colors.white38,
          ),
        ),
      ),
    );
  }
}

class _VideoLabel extends StatelessWidget {
  const _VideoLabel();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_outline, size: 48, color: Colors.white),
            SizedBox(height: 8),
            Text(
              'Video preview',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClockOverlay extends StatefulWidget {
  const _ClockOverlay();

  @override
  State<_ClockOverlay> createState() => _ClockOverlayState();
}

class _ClockOverlayState extends State<_ClockOverlay> {
  late DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hours = _now.hour.toString().padLeft(2, '0');
    final minutes = _now.minute.toString().padLeft(2, '0');
    return Text(
      '$hours:$minutes',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 32,
        fontWeight: FontWeight.w300,
        shadows: <Shadow>[Shadow(blurRadius: 8, color: Colors.black)],
      ),
    );
  }
}

class _KenBurns extends StatefulWidget {
  const _KenBurns({
    super.key,
    required this.enabled,
    required this.pan,
    required this.imageAspect,
    required this.imageFile,
    required this.intervalSeconds,
    required this.progress,
    required this.child,
  });

  final bool enabled;
  final int pan;
  final double imageAspect;
  final File imageFile;
  final int intervalSeconds;
  final double progress;
  final Widget child;

  @override
  State<_KenBurns> createState() => _KenBurnsState();
}

class _KenBurnsState extends State<_KenBurns>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _durationFor(widget.intervalSeconds),
  );

  static Duration _durationFor(int seconds) =>
      Duration(seconds: seconds.clamp(2, 300));

  double? _resolvedAspect;
  ImageStream? _imageStream;
  ImageStreamListener? _listener;
  bool _imageReady = false;
  bool _started = false;

  double get _effectiveAspect => _resolvedAspect ?? widget.imageAspect;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _resolveAspect();
    }
  }

  @override
  void didUpdateWidget(_KenBurns oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageFile.path != widget.imageFile.path) {
      _controller
        ..stop()
        ..value = 0;
      _started = false;
      _imageReady = false;
      _resolvedAspect = null;
      if (widget.enabled) {
        _resolveAspect();
      }
      return;
    }
    if (oldWidget.enabled != widget.enabled) {
      if (!widget.enabled) {
        _controller
          ..stop()
          ..value = 0;
        _started = false;
      } else if (_imageReady) {
        _startAnimation();
      } else {
        _resolveAspect();
      }
    }
    if (oldWidget.intervalSeconds != widget.intervalSeconds &&
        !_started &&
        _imageReady) {
      _startAnimation();
    }
  }

  void _resolveAspect() {
    _detachListener();
    _resolvedAspect = null;
    try {
      final stream = FileImage(
        widget.imageFile,
      ).resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener(
        (info, synchronousCall) {
          final aspect = info.image.width / info.image.height;
          if (!mounted) {
            return;
          }
          // ponytail: a synchronous callback fires during build, defer the rebuild
          if (synchronousCall) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              _imageReady = true;
              if (aspect != _resolvedAspect) {
                setState(() => _resolvedAspect = aspect);
              }
              _startAnimation();
            });
          } else {
            _imageReady = true;
            if (aspect != _resolvedAspect) {
              setState(() => _resolvedAspect = aspect);
            }
            _startAnimation();
          }
        },
        onError: (error, stackTrace) {
          if (!mounted) {
            return;
          }
          _imageReady = true;
          _startAnimation();
        },
      );
      stream.addListener(listener);
      _imageStream = stream;
      _listener = listener;
    } catch (_) {
      // ponytail: decode failures keep the cached aspect fallback
      _imageReady = true;
      _startAnimation();
    }
  }

  void _detachListener() {
    final stream = _imageStream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageStream = null;
    _listener = null;
  }

  void _startAnimation() {
    if (!widget.enabled || !_imageReady || _started) {
      return;
    }
    final remaining = (1 - widget.progress.clamp(0.0, 1.0)).clamp(0.05, 1.0);
    final millis = (widget.intervalSeconds * 1000 * remaining)
        .round()
        .clamp(500, 300000);
    _controller
      ..duration = Duration(milliseconds: millis)
      ..value = 0
      ..forward();
    _started = true;
  }

  @override
  void dispose() {
    _detachListener();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final viewportHeight = constraints.maxHeight;
        final viewportAspect = viewportWidth > 0 && viewportHeight > 0
            ? viewportWidth / viewportHeight
            : _effectiveAspect;
        return AnimatedBuilder(
          animation: _controller,
          child: widget.child,
          builder: (context, child) {
            final plan = kenBurnsPlan(
              imageAspect: _effectiveAspect,
              viewportAspect: viewportAspect,
              panStrength: widget.pan,
              progress: _controller.value,
            );
            if (plan.motion == PanMotion.zoom) {
              return Transform.scale(
                key: const ValueKey<String>('ken-burns-frame'),
                scale: plan.scale,
                child: child,
              );
            }
            final frame = frameSizeFor(
              imageAspect: _effectiveAspect,
              viewportWidth: viewportWidth,
              viewportHeight: viewportHeight,
              motion: plan.motion,
            );
            final dx = (plan.translateX * viewportWidth)
                .clamp(-frame.maxX, frame.maxX)
                .toDouble();
            final dy = (plan.translateY * viewportHeight)
                .clamp(-frame.maxY, frame.maxY)
                .toDouble();
            return ClipRect(
              child: OverflowBox(
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: Transform.translate(
                  key: const ValueKey<String>('ken-burns-frame'),
                  offset: Offset(dx, dy),
                  child: SizedBox(
                    key: const ValueKey<String>('ken-burns-display'),
                    width: frame.displayWidth,
                    height: frame.displayHeight,
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
