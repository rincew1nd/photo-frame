/// Validated plugin bridge protocol and capability policies for plugin API v1.
///
/// Everything here is pure Dart over host-provided strings. It does not touch
/// the network, render UI, or open platform channels; M3b wires it to the
/// webview and slideshow.
library;

import 'dart:convert';
import 'dart:io';

import 'package:photoframe/core/clock.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';

/// A validated protocol envelope received from, or sent to, a plugin.
class PluginBridgeMessage {
  const PluginBridgeMessage({
    required this.type,
    this.id,
    this.payload = const <String, dynamic>{},
  });

  /// Parses and validates a JSON bridge message.
  ///
  /// Throws [PluginValidationException] with a readable, secret-free reason on
  /// oversize, malformed, wrong-shape, or unsupported-type input. The raw
  /// message is never included in the error.
  factory PluginBridgeMessage.parse(String raw) {
    if (utf8.encode(raw).length > PluginBridgeProtocol.maxMessageBytes) {
      throw const PluginValidationException(
        'Plugin bridge message exceeds the 65536-byte limit.',
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const PluginValidationException(
        'Plugin bridge message is not valid JSON.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const PluginValidationException(
        'Plugin bridge message must be a JSON object.',
      );
    }

    final rawType = decoded['type'];
    if (rawType is! String || rawType.trim().isEmpty) {
      throw const PluginValidationException(
        'Plugin bridge message type must be a non-empty string.',
      );
    }
    if (!PluginBridgeProtocol.inboundTypes.contains(rawType)) {
      throw const PluginValidationException(
        'Unsupported plugin bridge message type.',
      );
    }

    final rawId = decoded['id'];
    String? id;
    if (rawId != null) {
      if (rawId is! String || rawId.isEmpty) {
        throw const PluginValidationException(
          'Plugin bridge message id must be a non-empty string.',
        );
      }
      id = rawId;
    }

    final rawPayload = decoded['payload'];
    var payload = const <String, dynamic>{};
    if (rawPayload != null) {
      if (rawPayload is! Map<String, dynamic>) {
        throw const PluginValidationException(
          'Plugin bridge message payload must be an object.',
        );
      }
      payload = rawPayload;
    }

    return PluginBridgeMessage(type: rawType, id: id, payload: payload);
  }

  final String type;
  final String? id;
  final Map<String, dynamic> payload;
}

/// Versioned message types and outbound encoders for the plugin bridge.
abstract final class PluginBridgeProtocol {
  /// Maximum inbound JSON message size in UTF-8 bytes.
  static const int maxMessageBytes = 64 * 1024;

  static const Set<String> inboundTypes = <String>{
    'ready',
    'getState',
    'getConfig',
    'requestUpdate',
    'requestPlacement',
    'action',
    'openLink',
    'storage.get',
    'storage.set',
    'storage.remove',
    'storage.clear',
    'network.request',
    'log',
    'reportError',
  };

  static const Set<String> outboundTypes = <String>{
    'state',
    'event',
    'config',
    'placement',
    'actionResult',
    'storageResult',
    'networkResult',
    'log',
    'error',
  };

  /// Actions the host understands, mirroring the manifest [PluginAction] enum.
  static final Set<String> allowedActions = Set<String>.unmodifiable(
    PluginAction.values.map((action) => action.name),
  );

  static PluginBridgeMessage parse(String raw) =>
      PluginBridgeMessage.parse(raw);

  static bool isAllowedAction(String action) => allowedActions.contains(action);

  static String state(Map<String, dynamic> snapshot, {String? id}) {
    return encode('state', id: id, payload: snapshot);
  }

  static String event(Map<String, dynamic> event, {String? id}) {
    return encode('event', id: id, payload: event);
  }

  static String config(Map<String, dynamic> config, {String? id}) {
    return encode('config', id: id, payload: config);
  }

  static String placement(Map<String, dynamic> placement, {String? id}) {
    return encode('placement', id: id, payload: placement);
  }

  static String actionResult({
    required String action,
    required bool ok,
    Object? result,
    String? error,
    String? id,
  }) {
    return encode(
      'actionResult',
      id: id,
      payload: <String, dynamic>{
        'action': action,
        'ok': ok,
        'result': result,
        'error': error,
      },
    );
  }

  static String storageResult({
    required bool ok,
    String? key,
    String? value,
    String? error,
    String? id,
  }) {
    return encode(
      'storageResult',
      id: id,
      payload: <String, dynamic>{
        'ok': ok,
        'key': key,
        'value': value,
        'error': error,
      },
    );
  }

  static String networkResult({
    required bool ok,
    int? status,
    Map<String, String>? headers,
    String? body,
    String? error,
    String? id,
  }) {
    return encode(
      'networkResult',
      id: id,
      payload: <String, dynamic>{
        'ok': ok,
        'status': status,
        'headers': headers,
        'body': body,
        'error': error,
      },
    );
  }

  static String log({
    required String level,
    required String message,
    String? id,
  }) {
    return encode(
      'log',
      id: id,
      payload: <String, dynamic>{'level': level, 'message': message},
    );
  }

  static String error({required String message, String? code, String? id}) {
    return encode(
      'error',
      id: id,
      payload: <String, dynamic>{'message': message, 'code': code},
    );
  }

  static String encode(
    String type, {
    String? id,
    Map<String, dynamic>? payload,
  }) {
    return jsonEncode(<String, dynamic>{
      'type': type,
      'id': ?id,
      'payload': ?payload,
    });
  }
}

/// Per-plugin sliding-window action rate limiter.
class PluginActionRateLimiter {
  PluginActionRateLimiter({
    this.limit = 10,
    this.window = const Duration(minutes: 1),
    Clock clock = const SystemClock(),
  }) : _clock = clock {
    if (limit < 0) {
      throw ArgumentError.value(limit, 'limit', 'Must not be negative.');
    }
    if (window <= Duration.zero) {
      throw ArgumentError.value(window, 'window', 'Must be positive.');
    }
  }

  final int limit;
  final Duration window;
  final Clock _clock;
  final Map<String, List<DateTime>> _calls = <String, List<DateTime>>{};

  /// Records one call when under [limit], returning false when denied.
  bool allow(String pluginId) {
    if (pluginId.isEmpty) {
      throw ArgumentError.value(pluginId, 'pluginId', 'Must not be empty.');
    }
    final now = _clock.now();
    final calls = _calls.putIfAbsent(pluginId, () => <DateTime>[]);
    calls.removeWhere((call) => now.difference(call) >= window);
    if (calls.length >= limit) {
      return false;
    }
    calls.add(now);
    return true;
  }

  /// Clears the window for one plugin.
  void reset(String pluginId) {
    _calls.remove(pluginId);
  }

  /// Clears every plugin window.
  void resetAll() {
    _calls.clear();
  }
}

/// External-link allowlist: normalizes http/https URLs and rejects everything
/// else, including credentials, `file`, `javascript`, `intent`, and `data`.
class PluginLinkPolicy {
  const PluginLinkPolicy({this.maxLength = 2048});

  final int maxLength;

  Uri? normalize(String raw) {
    return _normalizeHttpUri(
      raw.trim(),
      maxLength: maxLength,
      rejectCredentials: true,
      rejectLocalHosts: false,
    );
  }

  bool isAllowed(String raw) => normalize(raw) != null;
}

/// Host-proxy network policy. It does not perform HTTP itself; M3b will use
/// [validate] plus the exposed limits around its own client.
class PluginNetworkPolicy {
  const PluginNetworkPolicy({
    this.timeout = defaultTimeout,
    this.maxResponseBytes = defaultMaxResponseBytes,
    this.requestsPerMinute = defaultRequestsPerMinute,
    this.maxUrlLength = 2048,
  });

  static const Duration defaultTimeout = Duration(seconds: 10);
  static const int defaultMaxResponseBytes = 1024 * 1024;
  static const int defaultRequestsPerMinute = 30;

  final Duration timeout;
  final int maxResponseBytes;
  final int requestsPerMinute;
  final int maxUrlLength;

  /// Returns the normalized URL, or null when the request must be rejected.
  Uri? validate(String raw) {
    return _normalizeHttpUri(
      raw,
      maxLength: maxUrlLength,
      rejectCredentials: true,
      rejectLocalHosts: true,
    );
  }

  bool isAllowed(String raw) => validate(raw) != null;
}

Uri? _normalizeHttpUri(
  String raw, {
  required int maxLength,
  required bool rejectCredentials,
  required bool rejectLocalHosts,
}) {
  if (raw.isEmpty || raw.length > maxLength) {
    return null;
  }
  // Literal whitespace and control characters are not valid in a URL.
  // Do not trim: a URL with surrounding whitespace is not the URL the caller
  // asked for, and accepting it hides malformed input.
  for (final code in raw.codeUnits) {
    if (code <= 0x20 || code == 0x7f) {
      return null;
    }
  }

  final uri = Uri.tryParse(raw);
  if (uri == null) {
    return null;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return null;
  }
  if (uri.host.isEmpty) {
    return null;
  }
  if (rejectCredentials && uri.userInfo.isNotEmpty) {
    return null;
  }
  if (rejectLocalHosts && _isLocalHost(uri.host)) {
    return null;
  }
  return uri.normalizePath();
}

bool _isLocalHost(String host) {
  var name = host.toLowerCase();
  if (name.endsWith('.')) {
    name = name.substring(0, name.length - 1);
  }
  if (name == 'localhost' ||
      name.endsWith('.localhost') ||
      name == 'local' ||
      name.endsWith('.local') ||
      name.contains('%')) {
    return true;
  }

  final address = InternetAddress.tryParse(name);
  if (address == null) {
    return false;
  }
  return _isBlockedAddress(address);
}

bool _isBlockedAddress(InternetAddress address) {
  final raw = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return _isBlockedIpv4(raw[0], raw[1]);
  }
  if (address.type == InternetAddressType.IPv6 && raw.length == 16) {
    if (_isIpv4Mapped(raw)) {
      return _isBlockedIpv4(raw[12], raw[13]);
    }
    if (raw.every((byte) => byte == 0)) {
      return true; // ::
    }
    if (_isIpv6Loopback(raw)) {
      return true; // ::1
    }
    if (raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80) {
      return true; // fe80::/10 link-local
    }
    if ((raw[0] & 0xfe) == 0xfc) {
      return true; // fc00::/7 unique local
    }
    return false;
  }
  return true;
}

bool _isIpv4Mapped(List<int> raw) {
  for (var index = 0; index < 10; index++) {
    if (raw[index] != 0) {
      return false;
    }
  }
  return raw[10] == 0xff && raw[11] == 0xff;
}

bool _isIpv6Loopback(List<int> raw) {
  for (var index = 0; index < 15; index++) {
    if (raw[index] != 0) {
      return false;
    }
  }
  return raw[15] == 1;
}

bool _isBlockedIpv4(int first, int second) {
  if (first == 0 || first == 10 || first == 127) {
    return true; // 0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8
  }
  if (first == 169 && second == 254) {
    return true; // 169.254.0.0/16 link-local
  }
  if (first == 172 && second >= 16 && second <= 31) {
    return true; // 172.16.0.0/12
  }
  if (first == 192 && second == 168) {
    return true; // 192.168.0.0/16
  }
  if (first == 100 && second >= 64 && second <= 127) {
    return true; // 100.64.0.0/10 carrier-grade NAT
  }
  return false;
}
