/// Connects the plugin bridge protocol to the snapshot builder, store, and
/// webview transport for one running plugin.
///
/// The session owns no UI and no native channel. A host supplies a JSON sender
/// (the webview's `sendMessage`) and listens to the callbacks for app actions,
/// links, placement requests, logs, and failures.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:photoframe/core/clock.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';
import 'package:photoframe/data/plugins/plugin_store.dart';
import 'package:photoframe/domain/plugins/plugin_snapshot.dart';
import 'package:photoframe/plugins/host/plugin_bridge.dart';

/// Sends one already-encoded bridge envelope to the plugin webview.
typedef PluginSessionSend = Future<void> Function(String json);

/// Receives a declared, granted action and its plugin payload.
typedef PluginSessionAction = void Function(
  PluginAction action,
  Map<String, dynamic> payload,
);

/// Receives a validated external link.
typedef PluginSessionLink = void Function(Uri uri);

/// Receives a plugin log line with its declared level.
typedef PluginSessionLog = void Function(String level, String message);

/// Receives a plugin failure. [disable] asks the host to hide/disable it.
typedef PluginSessionError = void Function(String message, bool disable);

/// Receives a validated placement request after it was persisted.
typedef PluginSessionPlacement = void Function(PluginPlacement placement);

/// One plugin's live bridge session.
///
/// Message handlers never throw to the caller: parse failures, invalid
/// payloads, denied capabilities, and store errors are turned into bounded,
/// secret-free bridge envelopes.
class PluginSession {
  PluginSession({
    required this.pluginId,
    required this.manifest,
    required PluginStore store,
    Clock clock = const SystemClock(),
    required PluginSessionSend sendMessage,
    PluginSessionAction? onAction,
    PluginSessionLink? onOpenLink,
    PluginSessionLog? onLog,
    PluginSessionError? onError,
    PluginSessionPlacement? onPlacementRequest,
    PluginLinkPolicy linkPolicy = const PluginLinkPolicy(),
    PluginNetworkPolicy networkPolicy = const PluginNetworkPolicy(),
  }) : _store = store,
       _clock = clock,
       _sendMessage = sendMessage,
       _onAction = onAction,
       _onOpenLink = onOpenLink,
       _onLog = onLog,
       _onError = onError,
       _onPlacementRequest = onPlacementRequest,
       _linkPolicy = linkPolicy,
       _networkPolicy = networkPolicy,
       _actionLimiter = PluginActionRateLimiter(clock: clock),
       _networkLimiter = PluginActionRateLimiter(
         limit: networkPolicy.requestsPerMinute,
         clock: clock,
       );

  final String pluginId;
  final PluginManifest manifest;

  final PluginStore _store;
  final Clock _clock;
  final PluginSessionSend _sendMessage;
  final PluginSessionAction? _onAction;
  final PluginSessionLink? _onOpenLink;
  final PluginSessionLog? _onLog;
  final PluginSessionError? _onError;
  final PluginSessionPlacement? _onPlacementRequest;
  final PluginLinkPolicy _linkPolicy;
  final PluginNetworkPolicy _networkPolicy;
  final PluginActionRateLimiter _actionLimiter;
  final PluginActionRateLimiter _networkLimiter;

  static const Duration _updateInterval = Duration(seconds: 1);
  static const Duration _failureWindow = Duration(minutes: 5);
  static const int _failureThreshold = 3;
  static const Duration _tickInterval = Duration(seconds: 1);

  static const Set<String> _blockedRequestHeaders = <String>{
    'authorization',
    'cookie',
    'proxy-authorization',
    'host',
    'content-length',
    'connection',
    'transfer-encoding',
  };

  static const Set<String> _allowedMethods = <String>{
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
    'OPTIONS',
  };

  PluginSnapshotSource? _source;
  Map<String, dynamic>? _config;
  PluginPlacement? _placement;
  Set<PluginAction> _grantedActions = const <PluginAction>{};

  Timer? _ticker;
  bool _visible = false;
  bool _appActive = true;
  bool _disposed = false;
  bool _failed = false;
  bool _stateInFlight = false;
  bool _statePending = false;
  DateTime? _lastRequestUpdate;
  final List<DateTime> _failures = <DateTime>[];

  bool get isFailed => _failed;

  /// Replaces the host snapshot inputs used for `state` envelopes.
  void setSnapshotSource(PluginSnapshotSource source) {
    _source = source;
  }

  /// Sets the app actions the user/host has granted to this plugin.
  void setGrantedActions(Set<PluginAction> actions) {
    _grantedActions = Set<PluginAction>.of(actions);
  }

  /// Loads stored config/placement and sends the first `state` envelope.
  Future<void> start() async {
    if (_disposed) {
      return;
    }
    await _loadConfig();
    await _loadPlacement();
    await _sendState();
  }

  /// Parses and handles one inbound message.
  Future<void> handleMessage(String raw) async {
    if (_disposed) {
      return;
    }

    late final PluginBridgeMessage message;
    try {
      message = PluginBridgeProtocol.parse(raw);
    } on PluginValidationException catch (error) {
      await _sendError(error.message, code: 'invalid_message');
      return;
    } on Object {
      await _sendError(
        'The plugin message could not be read.',
        code: 'invalid_message',
      );
      return;
    }

    try {
      await _dispatch(message);
    } on Object {
      await _sendError(
        'The host could not handle the plugin request.',
        code: 'internal_error',
        id: message.id,
      );
    }
  }

  /// Starts the 1 Hz state ticker.
  void startTicker() {
    if (_disposed || _failed) {
      return;
    }
    _ticker ??= Timer.periodic(_tickInterval, (_) {
      unawaited(tick());
    });
  }

  /// Stops the 1 Hz state ticker.
  void stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Sets whether the plugin is on screen.
  void setVisible(bool visible) {
    _visible = visible;
  }

  /// Sets whether the app is in the foreground and the screen is on.
  void setAppActive(bool active) {
    _appActive = active;
  }

  /// Runs one tick immediately.
  ///
  /// This is the test seam for [startTicker]; it applies the same visibility,
  /// activity, failure, and in-flight coalescing rules as the timer.
  Future<void> tick() async {
    if (!_shouldTick) {
      return;
    }
    await _sendState();
  }

  /// Cancels timers and ignores later messages.
  void dispose() {
    _disposed = true;
    stopTicker();
  }

  bool get _shouldTick =>
      !_disposed && !_failed && _visible && _appActive;

  Future<void> _dispatch(PluginBridgeMessage message) async {
    switch (message.type) {
      case 'ready':
      case 'getState':
        await _sendState(id: message.id);
      case 'requestUpdate':
        await _handleRequestUpdate(message);
      case 'getConfig':
        await _sendConfig(message);
      case 'requestPlacement':
        await _handlePlacementRequest(message);
      case 'action':
        await _handleAction(message);
      case 'openLink':
        await _handleOpenLink(message);
      case 'storage.get':
      case 'storage.set':
      case 'storage.remove':
      case 'storage.clear':
        await _handleStorage(message);
      case 'network.request':
        await _handleNetwork(message);
      case 'log':
        _handleLog(message);
      case 'reportError':
        _handleReportError(message);
      default:
        await _sendError(
          'Unsupported plugin bridge message type.',
          code: 'unsupported_type',
          id: message.id,
        );
    }
  }

  Future<void> _handleRequestUpdate(PluginBridgeMessage message) async {
    final now = _clock.now();
    final last = _lastRequestUpdate;
    if (last != null && now.difference(last) < _updateInterval) {
      return;
    }
    _lastRequestUpdate = now;
    await _sendState(id: message.id);
  }

  Future<void> _sendConfig(PluginBridgeMessage message) async {
    try {
      final config = await _store.getConfig(pluginId);
      _config = config;
      await _send(PluginBridgeProtocol.config(config, id: message.id));
    } on Object {
      await _sendError(
        'Plugin configuration could not be read.',
        code: 'config_error',
        id: message.id,
      );
    }
  }

  Future<void> _sendState({String? id}) async {
    if (_disposed) {
      return;
    }
    if (_stateInFlight) {
      _statePending = true;
      return;
    }

    final source = _source;
    if (source == null) {
      await _sendError(
        'Plugin state is not available yet.',
        code: 'state_unavailable',
        id: id,
      );
      return;
    }

    _stateInFlight = true;
    try {
      final snapshot = _buildSnapshot(source);
      await _send(PluginBridgeProtocol.state(snapshot, id: id));
    } on Object {
      await _sendError(
        'Plugin state could not be built.',
        code: 'state_error',
        id: id,
      );
    } finally {
      _stateInFlight = false;
      if (_statePending && !_disposed) {
        _statePending = false;
        unawaited(_sendState());
      }
    }
  }

  Map<String, dynamic> _buildSnapshot(PluginSnapshotSource source) {
    final config = _config;
    final effective = config == null
        ? source
        : _sourceWithConfig(source, config);
    return PluginSnapshotBuilder.build(manifest: manifest, source: effective);
  }

  Future<void> _handlePlacementRequest(PluginBridgeMessage message) async {
    try {
      final placement = _parsePlacement(message.payload);
      await _store.setPlacement(pluginId, placement);
      _placement = placement;
      _onPlacementRequest?.call(placement);
      await _send(
        PluginBridgeProtocol.placement(
          _placementJson(placement),
          id: message.id,
        ),
      );
    } on PluginValidationException catch (error) {
      await _sendError(error.message, code: 'invalid_placement', id: message.id);
    } on Object {
      await _sendError(
        'Plugin placement could not be saved.',
        code: 'placement_error',
        id: message.id,
      );
    }
  }

  Future<void> _handleAction(PluginBridgeMessage message) async {
    final rawName = message.payload['name'];
    final name = rawName is String ? rawName : '';
    final action = PluginAction.tryParse(rawName);

    if (action == null || !manifest.actions.contains(action)) {
      await _sendActionResult(
        action: name,
        ok: false,
        error: 'Action is not declared by the plugin manifest.',
        id: message.id,
      );
      return;
    }
    if (!_grantedActions.contains(action)) {
      await _sendActionResult(
        action: name,
        ok: false,
        error: 'Action is not granted.',
        id: message.id,
      );
      return;
    }
    if (!_actionLimiter.allow(pluginId)) {
      await _sendActionResult(
        action: name,
        ok: false,
        error: 'Action rate limit exceeded.',
        id: message.id,
      );
      return;
    }

    final rawPayload = message.payload['payload'];
    if (rawPayload != null && rawPayload is! Map<String, dynamic>) {
      await _sendActionResult(
        action: name,
        ok: false,
        error: 'Action payload must be an object.',
        id: message.id,
      );
      return;
    }
    final payload = rawPayload is Map<String, dynamic>
        ? rawPayload
        : const <String, dynamic>{};

    try {
      _onAction?.call(action, payload);
    } on Object {
      await _sendActionResult(
        action: name,
        ok: false,
        error: 'Action failed.',
        id: message.id,
      );
      return;
    }

    await _sendActionResult(action: name, ok: true, id: message.id);
  }

  Future<void> _handleOpenLink(PluginBridgeMessage message) async {
    final raw = message.payload['url'];
    final uri = raw is String ? _linkPolicy.normalize(raw) : null;
    if (uri == null) {
      await _sendActionResult(
        action: 'openLink',
        ok: false,
        error: 'Link is not allowed.',
        id: message.id,
      );
      return;
    }

    try {
      _onOpenLink?.call(uri);
    } on Object {
      await _sendActionResult(
        action: 'openLink',
        ok: false,
        error: 'Link could not be opened.',
        id: message.id,
      );
      return;
    }

    await _sendActionResult(action: 'openLink', ok: true, id: message.id);
  }

  Future<void> _handleStorage(PluginBridgeMessage message) async {
    final id = message.id;
    try {
      switch (message.type) {
        case 'storage.get':
          final key = _storageKey(message.payload);
          final value = await _store.storageGet(pluginId, key);
          await _send(
            PluginBridgeProtocol.storageResult(
              ok: true,
              key: key,
              value: value,
              id: id,
            ),
          );
        case 'storage.set':
          final key = _storageKey(message.payload);
          if (!message.payload.containsKey('value')) {
            await _send(
              PluginBridgeProtocol.storageResult(
                ok: false,
                key: key,
                error: 'Storage value is required.',
                id: id,
              ),
            );
            return;
          }
          final raw = message.payload['value'];
          final value = raw is String ? raw : jsonEncode(raw);
          await _store.storageSet(pluginId, key, value);
          await _send(
            PluginBridgeProtocol.storageResult(
              ok: true,
              key: key,
              value: value,
              id: id,
            ),
          );
        case 'storage.remove':
          final key = _storageKey(message.payload);
          await _store.storageRemove(pluginId, key);
          await _send(
            PluginBridgeProtocol.storageResult(
              ok: true,
              key: key,
              id: id,
            ),
          );
        case 'storage.clear':
          await _store.storageClear(pluginId);
          await _send(
            PluginBridgeProtocol.storageResult(ok: true, id: id),
          );
      }
    } on PluginValidationException catch (error) {
      await _send(
        PluginBridgeProtocol.storageResult(
          ok: false,
          error: error.message,
          id: id,
        ),
      );
    } on Object {
      await _send(
        PluginBridgeProtocol.storageResult(
          ok: false,
          error: 'Plugin storage operation failed.',
          id: id,
        ),
      );
    }
  }

  Future<void> _handleNetwork(PluginBridgeMessage message) async {
    final id = message.id;
    if (!manifest.permissions.network) {
      await _sendError(
        'Network access is not granted.',
        code: 'network_denied',
        id: id,
      );
      return;
    }

    final rawUrl = message.payload['url'];
    final uri = rawUrl is String ? _networkPolicy.validate(rawUrl) : null;
    if (uri == null) {
      await _send(
        PluginBridgeProtocol.networkResult(
          ok: false,
          error: 'Network URL is not allowed.',
          id: id,
        ),
      );
      return;
    }
    if (!_networkLimiter.allow(pluginId)) {
      await _send(
        PluginBridgeProtocol.networkResult(
          ok: false,
          error: 'Network rate limit exceeded.',
          id: id,
        ),
      );
      return;
    }

    final envelope = await _performNetworkRequest(uri, message.payload, id);
    if (utf8.encode(envelope).length > PluginBridgeProtocol.maxMessageBytes) {
      await _send(
        PluginBridgeProtocol.networkResult(
          ok: false,
          error: 'Network response is too large for the bridge.',
          id: id,
        ),
      );
      return;
    }
    await _send(envelope);
  }

  Future<String> _performNetworkRequest(
    Uri uri,
    Map<String, dynamic> payload,
    String? id,
  ) async {
    final rawMethod = payload['method'];
    final method = rawMethod is String ? rawMethod.toUpperCase() : 'GET';
    if (!_allowedMethods.contains(method)) {
      return PluginBridgeProtocol.networkResult(
        ok: false,
        error: 'HTTP method is not allowed.',
        id: id,
      );
    }

    final client = HttpClient()
      ..connectionTimeout = _networkPolicy.timeout
      ..findProxy = ((_) => 'DIRECT');

    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(_networkPolicy.timeout);
      request.followRedirects = false;

      final rawHeaders = payload['headers'];
      if (rawHeaders is Map<String, dynamic>) {
        for (final entry in rawHeaders.entries) {
          final name = entry.key.toLowerCase();
          final value = entry.value;
          if (_blockedRequestHeaders.contains(name) || value is! String) {
            continue;
          }
          request.headers.set(name, value);
        }
      }

      final body = payload['body'];
      if (body is String && method != 'GET' && method != 'HEAD') {
        request.write(body);
      }

      final response = await request.close().timeout(_networkPolicy.timeout);
      final bytes = <int>[];
      await for (final chunk in response.timeout(_networkPolicy.timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > _networkPolicy.maxResponseBytes) {
          client.close(force: true);
          return PluginBridgeProtocol.networkResult(
            ok: false,
            status: response.statusCode,
            error: 'Network response exceeds the byte limit.',
            id: id,
          );
        }
      }

      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name] = values.join(', ');
      });

      return PluginBridgeProtocol.networkResult(
        ok: true,
        status: response.statusCode,
        headers: headers,
        body: utf8.decode(bytes, allowMalformed: true),
        id: id,
      );
    } on TimeoutException {
      return PluginBridgeProtocol.networkResult(
        ok: false,
        error: 'Network request timed out.',
        id: id,
      );
    } on Object {
      return PluginBridgeProtocol.networkResult(
        ok: false,
        error: 'Network request failed.',
        id: id,
      );
    } finally {
      client.close(force: true);
    }
  }

  void _handleLog(PluginBridgeMessage message) {
    final rawLevel = message.payload['level'];
    final level = rawLevel is String ? rawLevel : 'info';
    final rawMessage = message.payload['message'];
    final text = rawMessage is String ? rawMessage : '';
    _onLog?.call(level, text);
  }

  void _handleReportError(PluginBridgeMessage message) {
    final rawMessage = message.payload['message'];
    final text = rawMessage is String && rawMessage.isNotEmpty
        ? rawMessage
        : 'Plugin reported an error.';
    _onLog?.call('error', text);
    _recordFailure(text);
  }

  void _recordFailure(String message) {
    if (_disposed) {
      return;
    }
    final now = _clock.now();
    _failures.removeWhere(
      (time) => now.difference(time) >= _failureWindow,
    );
    _failures.add(now);
    final disable = _failures.length >= _failureThreshold;
    if (disable && !_failed) {
      _failed = true;
      stopTicker();
    }
    _onError?.call(message, disable);
  }

  Future<void> _sendActionResult({
    required String action,
    required bool ok,
    String? error,
    String? id,
  }) {
    return _send(
      PluginBridgeProtocol.actionResult(
        action: action,
        ok: ok,
        error: error,
        id: id,
      ),
    );
  }

  Future<void> _sendError(
    String message, {
    String? code,
    String? id,
  }) {
    return _send(
      PluginBridgeProtocol.error(message: message, code: code, id: id),
    );
  }

  Future<void> _send(String json) async {
    if (_disposed) {
      return;
    }
    try {
      await _sendMessage(json);
    } on Object {
      // A transport failure must not escape into the slideshow.
    }
  }

  Future<void> _loadConfig() async {
    try {
      _config = await _store.getConfig(pluginId);
    } on Object {
      _config = null;
    }
  }

  Future<void> _loadPlacement() async {
    try {
      _placement = await _store.getPlacement(pluginId);
    } on Object {
      _placement = null;
    }
  }

  String _storageKey(Map<String, dynamic> payload) {
    final key = payload['key'];
    if (key is! String || key.isEmpty) {
      throw const PluginValidationException(
        'Plugin storage key must be a non-empty string.',
      );
    }
    return key;
  }

  PluginPlacement _parsePlacement(Map<String, dynamic> payload) {
    final current = _currentPlacement;
    return PluginPlacement(
      anchor: payload.containsKey('anchor')
          ? _anchor(payload['anchor'])
          : current.anchor,
      x: payload.containsKey('x') ? _coordinate(payload['x']) : current.x,
      y: payload.containsKey('y') ? _coordinate(payload['y']) : current.y,
      width: payload.containsKey('width')
          ? _positive(payload['width'], 'width')
          : current.width,
      height: payload.containsKey('height')
          ? _positive(payload['height'], 'height')
          : current.height,
      zOrder: payload.containsKey('zOrder')
          ? _integer(payload['zOrder'])
          : current.zOrder,
      showDuringNight: payload.containsKey('showDuringNight')
          ? _boolean(payload['showDuringNight'])
          : current.showDuringNight,
    );
  }

  PluginPlacement get _currentPlacement =>
      _placement ??
      _source?.placement ??
      manifest.placement ??
      const PluginPlacement(width: 320, height: 160);

  PluginAnchor _anchor(Object? value) {
    final anchor = PluginAnchor.tryParse(value);
    if (anchor == null) {
      throw const PluginValidationException(
        'Placement anchor is not valid.',
      );
    }
    return anchor;
  }

  double? _coordinate(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num && value.isFinite && value >= 0 && value <= 1) {
      return value.toDouble();
    }
    throw const PluginValidationException(
      'Placement coordinates must be between 0 and 1.',
    );
  }

  double _positive(Object? value, String field) {
    if (value is num && value.isFinite && value > 0) {
      return value.toDouble();
    }
    throw PluginValidationException(
      'Placement $field must be a positive number.',
    );
  }

  int _integer(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    throw const PluginValidationException(
      'Placement zOrder must be an integer.',
    );
  }

  bool _boolean(Object? value) {
    if (value is bool) {
      return value;
    }
    throw const PluginValidationException(
      'Placement showDuringNight must be a boolean.',
    );
  }

  Map<String, dynamic> _placementJson(PluginPlacement placement) {
    return <String, dynamic>{
      'anchor': placement.anchor.jsonName,
      'x': placement.x,
      'y': placement.y,
      'width': placement.width,
      'height': placement.height,
      'zOrder': placement.zOrder,
      'showDuringNight': placement.showDuringNight,
    };
  }

  PluginSnapshotSource _sourceWithConfig(
    PluginSnapshotSource source,
    Map<String, dynamic> config,
  ) {
    return PluginSnapshotSource(
      appVersion: source.appVersion,
      pluginApiVersion: source.pluginApiVersion,
      locale: source.locale,
      timeZone: source.timeZone,
      theme: source.theme,
      viewportWidth: source.viewportWidth,
      viewportHeight: source.viewportHeight,
      safeArea: source.safeArea,
      nightMode: source.nightMode,
      now: source.now,
      weather: source.weather,
      playback: source.playback,
      media: source.media,
      image: source.image,
      config: config,
      placement: source.placement,
      enabled: source.enabled,
      visible: source.visible,
    );
  }
}
