import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:photoframe/data/plugins/plugin_manifest.dart';

/// Loopback HTTP server for one sandboxed plugin instance.
///
/// The trusted host page and the plugin files share a random per-session
/// token in the URL. The plugin runs in an iframe without
/// `allow-same-origin`, so plugin responses carry a CSP that permits only the
/// loopback origin and blocks direct network access.
class PluginHostServer {
  HttpServer? _server;
  Uri? _hostUri;
  Uri? _entryUri;
  String? _token;
  String? _pluginRootPath;
  String? _pluginId;
  double _designWidth = 320;
  double _designHeight = 160;

  Future<void> start({
    required Directory pluginRoot,
    required String pluginId,
    required String entry,
    double designWidth = 320,
    double designHeight = 160,
  }) async {
    if (_server != null) {
      throw StateError('The plugin host server is already running.');
    }
    if (!_pluginIdPattern.hasMatch(pluginId)) {
      throw ArgumentError.value(pluginId, 'pluginId', 'Invalid plugin id');
    }

    final normalizedEntry = normalizePluginPath(entry, field: 'entry');
    for (final segment in normalizedEntry.split('/')) {
      if (!_isSafeSegment(segment)) {
        throw ArgumentError.value(entry, 'entry', 'Invalid plugin entry');
      }
    }

    final resolvedRoot = await pluginRoot.resolveSymbolicLinks();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final token = _generateToken();
    final hostUri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      pathSegments: <String>['t', token, 'host'],
    );

    _server = server;
    _token = token;
    _pluginRootPath = resolvedRoot;
    _pluginId = pluginId;
    _designWidth = designWidth > 0 ? designWidth : 320;
    _designHeight = designHeight > 0 ? designHeight : 160;
    _hostUri = hostUri;
    _entryUri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      pathSegments: <String>[
        't',
        token,
        'p',
        pluginId,
        ...normalizedEntry.split('/'),
      ],
    );

    server.listen((request) async {
      try {
        await _handle(request);
      } catch (_) {
        try {
          await _sendText(
            request,
            request.response,
            HttpStatus.internalServerError,
            'Internal server error.',
          );
        } catch (_) {
          // The response may already be closed.
        }
      }
    });
  }

  Uri get hostUri {
    final uri = _hostUri;
    if (uri == null) {
      throw StateError('The plugin host server is not running.');
    }
    return uri;
  }

  Uri get entryUri {
    final uri = _entryUri;
    if (uri == null) {
      throw StateError('The plugin host server is not running.');
    }
    return uri;
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    _hostUri = null;
    _entryUri = null;
    _token = null;
    _pluginRootPath = null;
    _pluginId = null;
    _designWidth = 320;
    _designHeight = 160;
    if (server != null) {
      await server.close(force: true);
    }
  }

  String get _origin => 'http://127.0.0.1:${_server!.port}';

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.headers.set('Cache-Control', 'no-store');

    if (request.method == 'OPTIONS') {
      await _handleOptions(request);
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await _sendText(
        request,
        response,
        HttpStatus.methodNotAllowed,
        'Method not allowed.',
      );
      return;
    }

    final segments = request.uri.pathSegments;
    if (segments.length < 3 || segments[0] != 't') {
      await _sendText(request, response, HttpStatus.notFound, 'Not found.');
      return;
    }
    if (segments[1] != _token) {
      await _sendText(request, response, HttpStatus.forbidden, 'Forbidden.');
      return;
    }

    if (segments.length == 3 && segments[2] == 'host') {
      _applyCors(request, response);
      await _send(
        request,
        response,
        HttpStatus.ok,
        'text/html; charset=utf-8',
        utf8.encode(_hostPage),
        csp: _hostCsp,
      );
      return;
    }

    if (segments.length == 3 && segments[2] == 'sdk.js') {
      _applyCors(request, response);
      await _send(
        request,
        response,
        HttpStatus.ok,
        'text/javascript; charset=utf-8',
        utf8.encode(_sdkScript),
        csp: _pluginCsp,
      );
      return;
    }

    if (segments.length >= 5 &&
        segments[2] == 'p' &&
        segments[3] == _pluginId) {
      final file = await _resolveFile(segments.sublist(4));
      if (file == null) {
        await _sendText(request, response, HttpStatus.notFound, 'Not found.');
        return;
      }
      _applyCors(request, response);
      await _sendFile(request, response, file);
      return;
    }

    await _sendText(request, response, HttpStatus.notFound, 'Not found.');
  }

  Future<void> _handleOptions(HttpRequest request) async {
    final response = request.response;
    final origin = request.headers.value('origin');
    if (origin != null && origin == _origin) {
      response.headers.set('Access-Control-Allow-Origin', origin);
      response.headers.set(
        'Access-Control-Allow-Methods',
        'GET, HEAD, OPTIONS',
      );
      response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
      response.headers.set('Access-Control-Max-Age', '600');
      response.headers.set('Vary', 'Origin');
      response.statusCode = HttpStatus.noContent;
    } else {
      response.statusCode = HttpStatus.forbidden;
    }
    await response.close();
  }

  void _applyCors(HttpRequest request, HttpResponse response) {
    final origin = request.headers.value('origin');
    if (origin != null && origin == _origin) {
      response.headers.set('Access-Control-Allow-Origin', origin);
      response.headers.set('Vary', 'Origin');
    }
  }

  /// Resolves a plugin-relative request path to a regular file.
  ///
  /// Rejects empty, dot, traversal, backslash, absolute, and drive-qualified
  /// segments, symlinks (including symlinked parents), directories, and
  /// anything outside the canonical plugin root.
  Future<File?> _resolveFile(List<String> segments) async {
    final root = _pluginRootPath;
    if (root == null || segments.isEmpty) {
      return null;
    }
    for (final segment in segments) {
      if (!_isSafeSegment(segment)) {
        return null;
      }
    }

    final candidate = p.normalize(p.joinAll(<String>[root, ...segments]));
    if (candidate == root || !p.isWithin(root, candidate)) {
      return null;
    }

    var current = root;
    for (var index = 0; index < segments.length; index++) {
      current = p.join(current, segments[index]);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link ||
          type == FileSystemEntityType.notFound) {
        return null;
      }
      final isLast = index == segments.length - 1;
      if (isLast
          ? type != FileSystemEntityType.file
          : type != FileSystemEntityType.directory) {
        return null;
      }
    }

    final resolved = await File(candidate).resolveSymbolicLinks();
    if (!p.isWithin(root, resolved)) {
      return null;
    }
    return File(candidate);
  }

  Future<void> _sendFile(
    HttpRequest request,
    HttpResponse response,
    File file,
  ) async {
    response.statusCode = HttpStatus.ok;
    final mime = _mimeType(file.path);
    response.headers.contentType = ContentType.parse(mime);
    response.headers.set('Content-Security-Policy', _pluginCsp);
    if (mime.startsWith('text/html')) {
      final html = utf8.decode(await file.readAsBytes());
      final body = _injectSdk(html);
      response.contentLength = utf8.encode(body).length;
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }
      response.add(utf8.encode(body));
      await response.close();
      return;
    }
    response.contentLength = await file.length();
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    await response.addStream(file.openRead());
    await response.close();
  }

  String get _sdkPath => '/t/$_token/sdk.js';

  String _injectSdk(String html) {
    final tag = '<script src="$_sdkPath"></script>';
    if (html.contains(tag)) {
      return html;
    }
    // Load the SDK before any plugin script so `host` exists in the plugin.
    final head = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(html);
    if (head != null) {
      return html.replaceRange(head.end, head.end, tag);
    }
    final script = RegExp(r'<script\b', caseSensitive: false).firstMatch(html);
    if (script != null) {
      return html.replaceRange(script.start, script.start, tag);
    }
    return '$tag$html';
  }

  Future<void> _sendText(
    HttpRequest request,
    HttpResponse response,
    int status,
    String message,
  ) {
    return _send(
      request,
      response,
      status,
      'text/plain; charset=utf-8',
      utf8.encode(message),
    );
  }

  Future<void> _send(
    HttpRequest request,
    HttpResponse response,
    int status,
    String contentType,
    List<int> body, {
    String? csp,
  }) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.parse(contentType);
    if (csp != null) {
      response.headers.set('Content-Security-Policy', csp);
    }
    response.contentLength = body.length;
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    response.add(body);
    await response.close();
  }

  String get _hostPage {
    final entry = const HtmlEscape(HtmlEscapeMode.attribute)
        .convert(entryUri.toString());
    return _hostPageTemplate
        .replaceFirst('__ENTRY__', entry)
        .replaceAll('__DESIGN_W__', _designWidth.toStringAsFixed(2))
        .replaceAll('__DESIGN_H__', _designHeight.toStringAsFixed(2));
  }

  String get _pluginCsp {
    final source = _origin;
    return "default-src 'none'; "
        "script-src 'self' $source; "
        "style-src 'self' 'unsafe-inline' $source; "
        "img-src 'self' data: $source; "
        "font-src 'self' $source; "
        "connect-src 'none'; "
        "base-uri 'none'; form-action 'none';";
  }
}

const String _hostCsp =
    "default-src 'none'; script-src 'unsafe-inline'; "
    "style-src 'unsafe-inline'; img-src 'self' data:; "
    "frame-src 'self'; connect-src 'none'; base-uri 'none'; "
    "form-action 'none'; frame-ancestors 'none';";

const String _hostPageTemplate = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>Photo Frame Plugin Host</title>
<style>
html, body { margin: 0; width: 100%; height: 100%; background: transparent; overflow: hidden; }
#plugin { position: absolute; left: 0; top: 0; border: 0; display: block;
  width: __DESIGN_W__px; height: __DESIGN_H__px; background: transparent;
  transform-origin: top left; }
</style>
</head>
<body>
<iframe id="plugin" sandbox="allow-scripts" referrerpolicy="no-referrer" src="__ENTRY__"></iframe>
<script>
(function () {
  'use strict';
  var iframe = document.getElementById('plugin');
  var queue = [];
  var MAX_MESSAGE = 65536;

  function sendToDart(message) {
    var text;
    try { text = JSON.stringify(message); } catch (error) { return; }
    if (text.length > MAX_MESSAGE) { return; }
    var channel = window.PhotoFrameHost;
    if (channel && typeof channel.postMessage === 'function') {
      try { channel.postMessage(text); return; } catch (error) { /* queue */ }
    }
    queue.push(text);
    if (queue.length > 100) { queue.shift(); }
  }

  function flush() {
    var channel = window.PhotoFrameHost;
    if (!channel || typeof channel.postMessage !== 'function') { return; }
    while (queue.length) {
      var text = queue[0];
      try { channel.postMessage(text); queue.shift(); } catch (error) { break; }
    }
  }
  setInterval(flush, 100);

  window.pluginHostBridge = {
    post: function (message) {
      if (!iframe.contentWindow) { return; }
      var text = typeof message === 'string' ? message : JSON.stringify(message);
      if (text.length > MAX_MESSAGE) { return; }
      iframe.contentWindow.postMessage(message, '*');
    },
    receive: function (message) {
      var parsed = typeof message === 'string' ? JSON.parse(message) : message;
      if (!parsed || typeof parsed !== 'object' || parsed.type === 'bridgeReady') {
        return;
      }
      window.pluginHostBridge.post(parsed);
    }
  };

  window.addEventListener('message', function (event) {
    if (event.source !== iframe.contentWindow) { return; }
    var message = event.data;
    if (!message || typeof message !== 'object') { return; }
    sendToDart(message);
  });

  function fit() {
    var designWidth = __DESIGN_W__;
    var designHeight = __DESIGN_H__;
    var scale = Math.min(
      window.innerWidth / designWidth,
      window.innerHeight / designHeight
    );
    var left = (window.innerWidth - designWidth * scale) / 2;
    var top = (window.innerHeight - designHeight * scale) / 2;
    iframe.style.transform =
      'translate(' + left + 'px,' + top + 'px) scale(' + scale + ')';
  }
  window.addEventListener('resize', fit);
  fit();

  iframe.addEventListener('load', function () {
    try { iframe.contentWindow.postMessage({type: 'bridgeReady'}, '*'); } catch (error) {}
    flush();
  });
})();
</script>
</body>
</html>
''';

const String _sdkScript = r'''
(function () {
  'use strict';
  var seq = 0;
  var pending = {};
  var stateListeners = [];
  var eventListeners = [];
  var lastState = null;
  var lastConfig = {};
  var resolveReady;
  var ready = new Promise(function (resolve) { resolveReady = resolve; });

  function send(type, payload, callback) {
    var id = 'p' + (++seq);
    if (callback) { pending[id] = callback; }
    parent.postMessage({type: type, id: id, payload: payload || {}}, '*');
    return id;
  }

  function request(type, payload) {
    return new Promise(function (resolve, reject) {
      send(type, payload, function (message) {
        if (message.type === 'error') {
          reject(new Error((message.payload && message.payload.message) || 'Plugin host error'));
        } else {
          resolve(message.payload);
        }
      });
    });
  }

  window.addEventListener('message', function (event) {
    if (event.source !== window.parent) { return; }
    var message = event.data;
    if (!message || typeof message !== 'object') { return; }
    if (message.id && pending[message.id]) {
      var callback = pending[message.id];
      delete pending[message.id];
      callback(message);
    }
    if (message.type === 'state') {
      lastState = message.payload;
      if (resolveReady) { resolveReady(lastState); resolveReady = null; }
      for (var i = 0; i < stateListeners.length; i++) {
        try { stateListeners[i](lastState); } catch (error) { console.error(error); }
      }
    } else if (message.type === 'event') {
      for (var j = 0; j < eventListeners.length; j++) {
        try { eventListeners[j](message.payload); } catch (error) { console.error(error); }
      }
    } else if (message.type === 'config') {
      lastConfig = message.payload || {};
    }
  });

  window.host = {
    ready: ready,
    getState: function () {
      return lastState ? Promise.resolve(lastState) : request('getState');
    },
    onState: function (callback) {
      if (typeof callback !== 'function') { return; }
      stateListeners.push(callback);
      if (lastState) { callback(lastState); }
    },
    onEvent: function (callback) {
      if (typeof callback === 'function') { eventListeners.push(callback); }
    },
    getConfig: function () {
      return request('getConfig');
    },
    requestUpdate: function () {
      return request('requestUpdate');
    },
    requestPlacement: function (placement) {
      return request('requestPlacement', placement);
    },
    action: function (name, payload) {
      return request('action', {name: name, payload: payload || {}});
    },
    openLink: function (url) {
      return request('openLink', {url: url});
    },
    storage: {
      get: function (key) { return request('storage.get', {key: key}); },
      set: function (key, value) { return request('storage.set', {key: key, value: value}); },
      remove: function (key) { return request('storage.remove', {key: key}); },
      clear: function () { return request('storage.clear'); }
    },
    network: {
      request: function (options) { return request('network.request', options); }
    },
    log: function (level, message) {
      parent.postMessage({type: 'log', payload: {level: level, message: message}}, '*');
    },
    reportError: function (message, details) {
      parent.postMessage({type: 'reportError', payload: {message: message, details: details}}, '*');
    }
  };

  parent.postMessage({type: 'ready'}, '*');
})();
''';

final RegExp _pluginIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

bool _isSafeSegment(String segment) {
  if (segment.isEmpty || segment == '.' || segment == '..') {
    return false;
  }
  // ':' is invalid in Windows filenames and would also admit drive paths.
  if (segment.contains('/') ||
      segment.contains('\\') ||
      segment.contains(':')) {
    return false;
  }
  for (final rune in segment.runes) {
    if (rune < 0x20 || rune == 0x7f) {
      return false;
    }
  }
  return true;
}

String _generateToken() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var index = 0; index < 16; index++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

String _mimeType(String path) {
  return switch (p.extension(path).toLowerCase()) {
    '.html' || '.htm' => 'text/html; charset=utf-8',
    '.css' => 'text/css; charset=utf-8',
    '.js' || '.mjs' => 'text/javascript; charset=utf-8',
    '.png' => 'image/png',
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.webp' => 'image/webp',
    '.svg' => 'image/svg+xml',
    '.json' => 'application/json; charset=utf-8',
    _ => 'text/plain; charset=utf-8',
  };
}
