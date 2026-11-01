import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/plugins/host/host_server.dart';

const String _pluginId = 'com.example.test';

const List<int> _pngBytes = <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
];

void main() {
  late Directory temporary;
  late Directory pluginRoot;
  late PluginHostServer server;
  late String pluginBase;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('photoframe_host_');
    pluginRoot = Directory(p.join(temporary.path, 'plugin'));
    await pluginRoot.create(recursive: true);
    await File(p.join(pluginRoot.path, 'index.html'))
        .writeAsString('<!DOCTYPE html><html><body>Plugin</body></html>');
    await File(p.join(pluginRoot.path, 'styles.css'))
        .writeAsString('body { color: white; }');
    await File(p.join(pluginRoot.path, 'logo.png')).writeAsBytes(_pngBytes);
    await Directory(p.join(pluginRoot.path, 'assets')).create(recursive: true);
    await File(p.join(pluginRoot.path, 'assets', 'nested.png'))
        .writeAsBytes(_pngBytes);

    server = PluginHostServer();
    await server.start(
      pluginRoot: pluginRoot,
      pluginId: _pluginId,
      entry: 'index.html',
    );
    pluginBase =
        '${server.hostUri.origin}/t/${server.hostUri.pathSegments[1]}'
        '/p/$_pluginId';
  });

  tearDown(() async {
    await server.close();
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('serves the host page with a sandboxed iframe and strict CSP', () async {
    final response = await _get(server.hostUri);

    expect(response.statusCode, HttpStatus.ok);
    expect(response.contentType, 'text/html');
    expect(response.text, contains('sandbox="allow-scripts"'));
    expect(response.text, isNot(contains('allow-same-origin')));
    expect(response.text, contains(server.entryUri.toString()));
    expect(response.text, isNot(contains('__DESIGN_')));
    expect(response.text, contains('scale('));

    final csp = response.header('content-security-policy');
    expect(csp, contains("default-src 'none'"));
    expect(csp, contains("connect-src 'none'"));
    expect(csp, contains("frame-src 'self'"));
    expect(response.header('x-content-type-options'), 'nosniff');
  });

  test('serves the entry and local assets with plugin CSP', () async {
    final entry = await _get(server.entryUri);
    expect(entry.statusCode, HttpStatus.ok);
    expect(entry.contentType, 'text/html');
    expect(entry.text, contains('Plugin'));
    final csp = entry.header('content-security-policy');
    expect(csp, contains("default-src 'none'"));
    expect(csp, contains("script-src 'self'"));
    expect(csp, contains("connect-src 'none'"));

    final style = await _get(Uri.parse('$pluginBase/styles.css'));
    expect(style.statusCode, HttpStatus.ok);
    expect(style.contentType, 'text/css');

    final image = await _get(Uri.parse('$pluginBase/logo.png'));
    expect(image.statusCode, HttpStatus.ok);
    expect(image.contentType, 'image/png');
    expect(image.body, _pngBytes);
  });

  test('injects the host SDK into plugin HTML and serves it', () async {
    final entry = await _get(server.entryUri);
    final match = RegExp(
      r'<script src="([^"]*sdk\.js)"></script>',
    ).firstMatch(entry.text);

    expect(match, isNotNull);
    final sdkPath = match!.group(1)!;
    expect(sdkPath, startsWith('/t/'));
    expect(sdkPath, endsWith('/sdk.js'));

    final sdk = await _get(
      Uri.parse('${server.entryUri.origin}$sdkPath'),
    );
    expect(sdk.statusCode, HttpStatus.ok);
    expect(sdk.contentType, 'text/javascript');
    expect(sdk.text, contains('window.host'));
    expect(sdk.text, contains('requestPlacement'));
    expect(sdk.text, contains('storage.get'));

    final host = await _get(server.hostUri);
    expect(host.text, contains('pluginHostBridge'));
    expect(host.text, contains('PhotoFrameHost'));
    expect(host.text, isNot(contains('sdk.js')));
  });

  test('serves supported MIME types and falls back to text/plain', () async {
    const cases = <String, String>{
      'script.js': 'text/javascript',
      'photo.jpg': 'image/jpeg',
      'photo.webp': 'image/webp',
      'glyph.svg': 'image/svg+xml',
      'data.json': 'application/json',
      'README': 'text/plain',
    };
    for (final name in cases.keys) {
      await File(p.join(pluginRoot.path, name)).writeAsString('test');
    }

    for (final entry in cases.entries) {
      final response = await _get(Uri.parse('$pluginBase/${entry.key}'));
      expect(response.statusCode, HttpStatus.ok, reason: entry.key);
      expect(response.contentType, entry.value, reason: entry.key);
    }
  });

  test('rejects wrong and missing tokens', () async {
    final token = server.hostUri.pathSegments[1];
    final origin = server.hostUri.origin;

    final wrongHost = await _get(Uri.parse('$origin/t/${'0' * 32}/host'));
    expect(
      wrongHost.statusCode,
      anyOf(HttpStatus.forbidden, HttpStatus.notFound),
    );

    final wrongAsset = await _get(
      Uri.parse('$origin/t/${'0' * 32}/p/$_pluginId/index.html'),
    );
    expect(
      wrongAsset.statusCode,
      anyOf(HttpStatus.forbidden, HttpStatus.notFound),
    );

    final missingHost = await _get(Uri.parse('$origin/host'));
    expect(
      missingHost.statusCode,
      anyOf(HttpStatus.forbidden, HttpStatus.notFound),
    );

    final missingAsset = await _get(
      Uri.parse('$origin/p/$_pluginId/index.html'),
    );
    expect(
      missingAsset.statusCode,
      anyOf(HttpStatus.forbidden, HttpStatus.notFound),
    );

    expect(token, isNot('0' * 32));
  });

  test(
    'rejects traversal, encoded traversal, absolute, and directories',
    () async {
      final outside = await File(p.join(temporary.path, 'secret.txt'))
          .writeAsString('secret');

      final requests = <String>[
        '$pluginBase/../secret.txt',
        '$pluginBase/%2e%2e/secret.txt',
        '$pluginBase/%2e%2e%2fsecret.txt',
        '$pluginBase/%2Fetc%2Fpasswd',
        '$pluginBase/C:%5CWindows%5Cwin.ini',
        '$pluginBase//etc/passwd',
        '$pluginBase/assets',
        '$pluginBase/assets/',
        '$pluginBase/missing.txt',
        '${server.hostUri.origin}/t/${server.hostUri.pathSegments[1]}'
            '/p/com.example.other/index.html',
      ];

      for (final url in requests) {
        final response = await _get(Uri.parse(url));
        expect(
          response.statusCode,
          anyOf(HttpStatus.forbidden, HttpStatus.notFound),
          reason: url,
        );
        expect(response.text, isNot(contains('secret')), reason: url);
      }

      expect(await outside.exists(), isTrue);
      expect(await outside.readAsString(), 'secret');
    },
  );

  test('rejects symbolic links when they can be created', () async {
    final outside = await File(p.join(temporary.path, 'outside.txt'))
        .writeAsString('outside');
    final link = Link(p.join(pluginRoot.path, 'escape.txt'));
    try {
      await link.create(outside.path);
    } on FileSystemException {
      // Windows may require developer mode or elevation to create symlinks.
      return;
    }

    final response = await _get(Uri.parse('$pluginBase/escape.txt'));
    expect(
      response.statusCode,
      anyOf(HttpStatus.forbidden, HttpStatus.notFound),
    );
    expect(response.text, isNot(contains('outside')));
  });

  test('restricts CORS to the host origin', () async {
    final hostOrigin = server.hostUri.origin;

    final allowed = await _get(
      server.entryUri,
      headers: <String, String>{'Origin': hostOrigin},
    );
    expect(allowed.header('access-control-allow-origin'), hostOrigin);

    final denied = await _get(
      server.entryUri,
      headers: <String, String>{'Origin': 'https://evil.example'},
    );
    expect(denied.header('access-control-allow-origin'), isNull);
    expect(denied.header('access-control-allow-origin'), isNot('*'));
  });

  test('uses a random 32-hex token per session', () async {
    final first = server.hostUri.pathSegments[1];
    final secondServer = PluginHostServer();
    await secondServer.start(
      pluginRoot: pluginRoot,
      pluginId: _pluginId,
      entry: 'index.html',
    );
    final second = secondServer.hostUri.pathSegments[1];
    await secondServer.close();

    expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(second, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(second, isNot(first));
    expect(server.hostUri.host, '127.0.0.1');
    expect(server.hostUri.port, greaterThan(0));
  });

  test('closes the listener and the port is no longer reachable', () async {
    final port = server.hostUri.port;
    await server.close();

    Object? error;
    try {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      socket.destroy();
    } on Object catch (caught) {
      error = caught;
    }
    expect(error, isA<SocketException>());
  });
}

class _Response {
  _Response({
    required this.statusCode,
    required this.contentType,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final String? contentType;
  final Map<String, List<String>> headers;
  final List<int> body;

  String get text => utf8.decode(body);

  String? header(String name) => headers[name.toLowerCase()]?.join(', ');
}

Future<_Response> _get(
  Uri uri, {
  String method = 'GET',
  Map<String, String> headers = const <String, String>{},
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, uri);
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final response = await request.close();
    final responseHeaders = <String, List<String>>{};
    response.headers.forEach((name, values) {
      responseHeaders[name.toLowerCase()] = List<String>.of(values);
    });
    final body = <int>[];
    await for (final chunk in response) {
      body.addAll(chunk);
    }
    return _Response(
      statusCode: response.statusCode,
      contentType: response.headers.contentType?.mimeType,
      headers: responseHeaders,
      body: body,
    );
  } finally {
    client.close(force: true);
  }
}
