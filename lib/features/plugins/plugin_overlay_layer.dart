import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';
import 'package:photoframe/data/plugins/plugin_store.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/domain/plugins/plugin_placement_editor.dart';
import 'package:photoframe/domain/plugins/plugin_snapshot.dart';
import 'package:photoframe/features/slideshow/slideshow_controller.dart';
import 'package:photoframe/platform/media_session.dart';
import 'package:photoframe/plugins/host/host_server.dart';
import 'package:photoframe/plugins/host/plugin_session.dart';
import 'package:photoframe/plugins/host/plugin_webview.dart';
import 'package:url_launcher/url_launcher.dart';

/// Transparent, interactive plugin boxes drawn above the media and below the
/// built-in overlays and controls.
///
/// Each visible plugin owns a loopback host server, a bridge session, and one
/// webview. A failed plugin is removed from the layer; clicks outside a box
/// pass through because only the boxes are hit-testable.
class PluginOverlayLayer extends ConsumerWidget {
  const PluginOverlayLayer({
    super.key,
    required this.state,
    required this.settings,
    required this.editMode,
    required this.media,
    this.onEditRequested,
    this.appActive = true,
    this.controlsVisible = false,
    this.slideshowVisible = true,
  });

  final SlideshowViewState state;
  final AppSettings settings;
  final bool editMode;
  final BackgroundMediaState media;
  final VoidCallback? onEditRequested;
  final bool appActive;

  /// On Android native views cannot be drawn below app controls, so the layer
  /// is hidden while the controls are shown.
  final bool controlsVisible;
  final bool slideshowVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!slideshowVisible) {
      return const SizedBox.shrink();
    }
    // Keep the boxes alive but out of the way while the controls are open.
    // Disposing them restarts each host server and causes reload flicker.
    final plugins =
        ref.watch(installedPluginsProvider).value ??
        const <InstalledPlugin>[];
    final appVersion = ref.watch(hostAppVersionProvider).value ?? '0.0.0';
    final visible = <InstalledPlugin>[
      for (final plugin in plugins)
        if (_isVisible(plugin, state)) plugin,
    ]..sort((a, b) => a.placement.zOrder.compareTo(b.placement.zOrder));
    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }

    final padding = MediaQuery.paddingOf(context);
    final insets = PluginInsets(
      top: padding.top,
      right: padding.right,
      bottom: padding.bottom,
      left: padding.left,
    );
    return Visibility(
      visible: !controlsVisible || editMode,
      maintainState: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              for (final plugin in visible)
                _PluginBox(
                  key: ValueKey<String>('plugin-box-${plugin.id}'),
                  plugin: plugin,
                  viewport: viewport,
                  safeArea: insets,
                  slideshow: state,
                  settings: settings,
                  appVersion: appVersion,
                  editMode: editMode,
                  media: media,
                  onEditRequested: onEditRequested,
                  appActive: appActive,
                ),
            ],
          );
        },
      ),
    );
  }

  static bool _isVisible(InstalledPlugin plugin, SlideshowViewState state) {
    if (!plugin.enabled || !plugin.visible) {
      return false;
    }
    if (state.nightMode && !plugin.placement.showDuringNight) {
      return false;
    }
    return true;
  }
}

class _PluginBox extends ConsumerStatefulWidget {
  const _PluginBox({
    super.key,
    required this.plugin,
    required this.viewport,
    required this.safeArea,
    required this.slideshow,
    required this.settings,
    required this.appVersion,
    required this.editMode,
    required this.media,
    this.onEditRequested,
    required this.appActive,
  });

  final InstalledPlugin plugin;
  final Size viewport;
  final PluginInsets safeArea;
  final SlideshowViewState slideshow;
  final AppSettings settings;
  final String appVersion;
  final bool editMode;
  final BackgroundMediaState media;
  final VoidCallback? onEditRequested;
  final bool appActive;

  @override
  ConsumerState<_PluginBox> createState() => _PluginBoxState();
}

class _PluginBoxState extends ConsumerState<_PluginBox> {
  final GlobalKey<PluginWebViewState> _webViewKey =
      GlobalKey<PluginWebViewState>();

  late PluginPlacementGeometry _geometry;
  PluginHostServer? _server;
  PluginSession? _session;
  Timer? _ticker;
  bool _failed = false;
  bool _interacting = false;
  String? _weatherKey;

  @override
  void initState() {
    super.initState();
    _geometry = _resolve(widget.plugin.placement);
    _session = PluginSession(
      pluginId: widget.plugin.id,
      manifest: widget.plugin.manifest,
      store: ref.read(pluginStoreProvider),
      sendMessage: _send,
      onAction: _handleAction,
      onOpenLink: _openLink,
      onLog: _log,
      onError: _handleError,
      onPlacementRequest: _handlePlacement,
    )..setGrantedActions(widget.plugin.manifest.actions);
    _pushSource();
    _requestPluginWeather();
    unawaited(_startServer());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant _PluginBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_interacting) {
      final next = _resolve(widget.plugin.placement);
      if (next != _geometry) {
        _geometry = next;
      }
    }
    if (oldWidget.media != widget.media) {
      unawaited(_session?.tick() ?? Future<void>.value());
    }
    _pushSource();
    _requestPluginWeather();
  }

  void _requestPluginWeather() {
    if (!widget.plugin.manifest.inputs.contains(PluginInput.weather)) {
      return;
    }
    final config = widget.plugin.config;
    final latitude = (config['latitude'] as num?)?.toDouble();
    final longitude = (config['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) {
      return;
    }
    // 0,0 is the manifest default; wait for the user to set a real location.
    if (latitude == 0 && longitude == 0) {
      return;
    }
    final unit = config['unit'] is String
        ? config['unit'] as String
        : 'celsius';
    final label = config['locationLabel'] is String
        ? config['locationLabel'] as String
        : '';
    final key = '$latitude:$longitude:$unit:$label';
    if (_weatherKey == key) {
      return;
    }
    _weatherKey = key;
    unawaited(
      ref
          .read(slideshowControllerProvider.notifier)
          .refreshWeatherAt(
            latitude: latitude,
            longitude: longitude,
            unit: unit,
            locationLabel: label,
          ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _session?.dispose();
    _session = null;
    final server = _server;
    _server = null;
    if (server != null) {
      unawaited(server.close());
    }
    super.dispose();
  }

  PluginPlacementGeometry _resolve(PluginPlacement placement) {
    return resolvePluginPlacement(
      placement: placement,
      viewportWidth: widget.viewport.width,
      viewportHeight: widget.viewport.height,
      safeArea: widget.safeArea,
      snapToGrid: widget.settings.plugins.gridSnap,
      gridSize: widget.settings.plugins.gridSize.toDouble(),
    );
  }

  Future<void> _startServer() async {
    final server = PluginHostServer();
    try {
      await server.start(
        pluginRoot: Directory(widget.plugin.bundlePath),
        pluginId: widget.plugin.id,
        entry: widget.plugin.manifest.entry,
        designWidth: widget.plugin.placement.width,
        designHeight: widget.plugin.placement.height,
      );
    } on Object catch (error) {
      _log('error', 'Plugin host failed to start: $error');
      if (mounted) {
        setState(() => _failed = true);
      }
      return;
    }
    if (!mounted) {
      await server.close();
      return;
    }
    _server = server;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      _pushSource();
      await _session?.start();
    });
  }

  Future<void> _send(String json) async {
    final view = _webViewKey.currentState;
    if (view == null) {
      return;
    }
    await view.sendMessage(json);
  }

  void _tick() {
    if (!mounted || _failed) {
      return;
    }
    _pushSource();
    unawaited(_session?.tick() ?? Future<void>.value());
  }

  void _pushSource() {
    final session = _session;
    if (session == null) {
      return;
    }
    session
      ..setSnapshotSource(_snapshotSource())
      ..setVisible(!_failed)
      ..setAppActive(widget.appActive);
  }

  PluginSnapshotSource _snapshotSource() {
    final slideshow = widget.slideshow;
    final current = slideshow.current;
    final cached = _cachedFor(current?.id);
    return PluginSnapshotSource(
      appVersion: widget.appVersion,
      pluginApiVersion: supportedPluginApiVersion,
      locale: WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
      timeZone: DateTime.now().timeZoneName,
      theme: widget.settings.display.theme,
      viewportWidth: widget.viewport.width,
      viewportHeight: widget.viewport.height,
      safeArea: widget.safeArea,
      nightMode: slideshow.nightMode,
      now: DateTime.now(),
      weather: _weather(),
      playback: PluginPlaybackSnapshot(
        playing: slideshow.playing,
        index: slideshow.currentIndex,
        total: slideshow.total == 0 ? slideshow.assets.length : slideshow.total,
        intervalSeconds: widget.settings.playback.intervalSeconds,
        progress: slideshow.progress,
        muted: widget.settings.playback.muted,
        slideshowRunning: slideshow.assets.isNotEmpty && !slideshow.loading,
      ),
      media: _media(),
      image: current == null ? null : _image(current, cached),
      placement: _geometry.placement,
      enabled: widget.plugin.enabled,
      visible: !_failed,
    );
  }

  PluginMediaSnapshot? _media() {
    final media = widget.media;
    if (!media.hasSession) {
      return null;
    }
    return PluginMediaSnapshot(
      hasSession: true,
      title: media.title,
      artist: media.artist,
      album: media.album,
      packageName: media.packageName,
      playing: media.playing,
      canPrevious: media.canPrevious,
      canNext: media.canNext,
      positionSeconds: media.positionSeconds,
      durationSeconds: media.durationSeconds,
    );
  }

  PluginWeatherSnapshot? _weather() {
    final weather = widget.slideshow.weather;
    if (weather == null) {
      return null;
    }
    return PluginWeatherSnapshot(
      temperature: weather.temperature,
      unit: weather.unit,
      code: weather.code,
      description: weather.description,
      locationLabel: weather.locationLabel,
      fetchedAt: weather.fetchedAt,
    );
  }

  PluginImageSnapshot _image(ImmichAsset asset, CachedAsset? cached) {
    final exif = asset.exif;
    final kind = cached?.type ?? asset.type;
    return PluginImageSnapshot(
      id: asset.id,
      type: kind.name,
      livePhoto: kind == MediaKind.livePhoto,
      width: cached?.width ?? asset.width ?? exif?.width,
      height: cached?.height ?? asset.height ?? exif?.height,
      aspectBucket: asset.aspectBucket?.jsonName,
      aspectLabel: asset.aspectBucket?.label,
      mimeType: asset.originalMimeType.isEmpty
          ? cached?.originalMimeType
          : asset.originalMimeType,
      cached: cached != null,
      exifDate: exif?.dateTimeOriginal ?? asset.fileCreatedAt,
      description: exif?.description ?? cached?.description,
      location: _location(asset) ?? cached?.location,
      tags: cached?.tags ?? const <String>[],
    );
  }

  String? _location(ImmichAsset asset) {
    final exif = asset.exif;
    for (final value in <String?>[exif?.city, exif?.state, exif?.country]) {
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  CachedAsset? _cachedFor(String? id) {
    if (id == null) {
      return null;
    }
    for (final asset in widget.slideshow.cached) {
      if (asset.id == id) {
        return asset;
      }
    }
    return null;
  }

  void _handleMessage(String raw) {
    unawaited(_session?.handleMessage(raw) ?? Future<void>.value());
  }

  void _handleAction(PluginAction action, Map<String, dynamic> payload) {
    final controller = ref.read(slideshowControllerProvider.notifier);
    final current = ref.read(slideshowControllerProvider).value;
    switch (action) {
      case PluginAction.next:
        controller.next();
      case PluginAction.previous:
        controller.previous();
      case PluginAction.pause:
        if (current?.playing ?? false) {
          controller.togglePause();
        }
      case PluginAction.resume:
        if (!(current?.playing ?? false)) {
          controller.togglePause();
        }
      case PluginAction.togglePause:
        controller.togglePause();
      case PluginAction.mute:
        unawaited(_setMuted(true));
      case PluginAction.unmute:
        unawaited(_setMuted(false));
      case PluginAction.toggleMute:
        unawaited(_setMuted(!widget.settings.playback.muted));
      case PluginAction.mediaNext:
        unawaited(_mediaControl(MediaControl.next));
      case PluginAction.mediaPrevious:
        unawaited(_mediaControl(MediaControl.previous));
      case PluginAction.mediaPlayPause:
        unawaited(_mediaControl(MediaControl.toggle));
      case PluginAction.openSettings:
        if (mounted) {
          unawaited(context.push('/settings'));
        }
      case PluginAction.openMediaSelection:
        if (mounted) {
          unawaited(context.push('/media-selection'));
        }
    }
  }

  Future<void> _mediaControl(MediaControl control) async {
    await ref.read(mediaSessionServiceProvider).control(control);
  }

  Future<void> _setMuted(bool muted) async {
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .save(
            (current) => current.copyWith(
              playback: current.playback.copyWith(muted: muted),
            ),
          );
    } on Object {
      // A settings write failure must not escape the plugin bridge.
    }
  }

  Future<void> _openLink(Uri uri) async {
    if (!mounted) {
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open external link?'),
        content: Text('${widget.plugin.manifest.name} wants to open:\n$uri'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      // Opening a link is best effort.
    }
  }

  void _log(String level, String message) {
    final logger = ref.read(appLoggerProvider);
    final text = 'Plugin ${widget.plugin.id}: $message';
    switch (level) {
      case 'error':
        logger.error(text);
      case 'warn' || 'warning':
        logger.warning(text);
      default:
        logger.info(text);
    }
  }

  void _handleError(String message, bool disable) {
    _log('error', message);
    if (disable && mounted) {
      setState(() => _failed = true);
      _pushSource();
    }
  }

  void _handleWebViewError() {
    _log('error', 'Plugin view failed to load.');
    if (mounted) {
      setState(() => _failed = true);
      _pushSource();
    }
  }

  void _handlePlacement(PluginPlacement placement) {
    if (!mounted) {
      return;
    }
    setState(() => _geometry = _resolve(placement));
    unawaited(
      Future<void>.microtask(() {
        if (mounted) {
          ref.invalidate(installedPluginsProvider);
        }
      }),
    );
  }

  void _handleDrag(DragUpdateDetails details) {
    if (!widget.editMode) {
      return;
    }
    setState(() {
      _geometry = movePluginPlacement(
        geometry: _geometry,
        dx: details.delta.dx,
        dy: details.delta.dy,
        viewportWidth: widget.viewport.width,
        viewportHeight: widget.viewport.height,
        safeArea: widget.safeArea,
        snapToGrid: widget.settings.plugins.gridSnap,
        gridSize: widget.settings.plugins.gridSize.toDouble(),
      );
    });
  }

  void _handleResize(DragUpdateDetails details) {
    if (!widget.editMode) {
      return;
    }
    setState(() {
      _geometry = resizePluginPlacement(
        geometry: _geometry,
        dw: details.delta.dx,
        dh: details.delta.dy,
        viewportWidth: widget.viewport.width,
        viewportHeight: widget.viewport.height,
        safeArea: widget.safeArea,
        snapToGrid: widget.settings.plugins.gridSnap,
        gridSize: widget.settings.plugins.gridSize.toDouble(),
        preserveAspectRatio: true,
      );
    });
  }

  void _endInteraction() {
    if (!_interacting) {
      return;
    }
    _interacting = false;
    unawaited(_persistPlacement());
  }

  Future<void> _persistPlacement() async {
    try {
      await ref
          .read(pluginStoreProvider)
          .setPlacement(widget.plugin.id, _geometry.placement);
      ref.invalidate(installedPluginsProvider);
    } on Object catch (error) {
      _log('error', 'Could not save plugin placement: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const SizedBox.shrink();
    }
    final geometry = _geometry;
    final server = _server;
    return Positioned(
      left: geometry.left,
      top: geometry.top,
      width: geometry.width,
      height: geometry.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: server == null
                ? const SizedBox.expand()
                : PluginWebView.server(
                    key: _webViewKey,
                    server: server,
                    onLog: (line) => _log('info', line),
                    onMessage: _handleMessage,
                    onError: _handleWebViewError,
                  ),
          ),
          if (!widget.editMode && widget.onEditRequested != null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onLongPress: widget.onEditRequested,
              ),
            ),
          if (widget.editMode)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) {
                  _interacting = true;
                  _geometry = _resolve(widget.plugin.placement);
                },
                onPanUpdate: _handleDrag,
                onPanEnd: (_) => _endInteraction(),
                onPanCancel: _endInteraction,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.lightBlueAccent,
                      width: 2,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        widget.plugin.manifest.name,
                        style: const TextStyle(
                          color: Colors.lightBlueAccent,
                          fontSize: 12,
                          shadows: <Shadow>[
                            Shadow(blurRadius: 6, color: Colors.black),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.editMode)
            Positioned(
              right: 0,
              bottom: 0,
              width: 28,
              height: 28,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => _interacting = true,
                onPanUpdate: _handleResize,
                onPanEnd: (_) => _endInteraction(),
                onPanCancel: _endInteraction,
                child: const DecoratedBox(
                  decoration: BoxDecoration(color: Colors.lightBlueAccent),
                  child: Icon(
                    Icons.open_in_full,
                    size: 16,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
