import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/immich/oauth_service.dart';

import '../../support/mock_immich_server.dart';

void main() {
  group('PkcePair', () {
    test('generates a verifier, S256 challenge, and random state', () {
      final pair = PkcePair.generate();

      expect(pair.verifier, isNotEmpty);
      expect(pair.verifier.contains('='), isFalse);
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(pair.verifier), isTrue);
      expect(pair.challenge, isNotEmpty);
      expect(pair.challenge.contains('='), isFalse);
      expect(pair.state, isNotEmpty);

      final expected = base64Url
          .encode(sha256.convert(ascii.encode(pair.verifier)).bytes)
          .replaceAll('=', '');
      expect(pair.challenge, expected);
    });

    test('generates distinct pairs', () {
      final first = PkcePair.generate();
      final second = PkcePair.generate();

      expect(first.verifier, isNot(second.verifier));
      expect(first.state, isNot(second.state));
    });
  });

  test('begins and finishes OAuth and creates an API key', () async {
    final server = await MockImmichServer.start();
    addTearDown(server.close);
    final service = OAuthService(launchBrowser: (_) async => true);
    final pkce = PkcePair.generate();
    const redirect = 'com.rincew1nd.photoframe://oauth';

    final authUrl = await service.begin(
      serverBase: server.rootUrl,
      redirectUri: redirect,
      pkce: pkce,
    );
    expect(authUrl.queryParameters['state'], pkce.state);

    final callback = Uri.parse('$redirect?code=code-1&state=${pkce.state}');
    final session = await service.finish(
      serverBase: server.rootUrl,
      redirectUri: redirect,
      callbackUri: callback,
      pkce: pkce,
    );

    expect(session.accessToken, 'oauth-access-token');
    expect(session.apiKey, isNotNull);
    expect(session.apiKey, isNotEmpty);
    expect(
      server.requests.any((r) => r.uri.path == '/api/api-keys'),
      isTrue,
    );
    expect(
      server.requests.any((r) => r.uri.path == '/api/oauth/callback'),
      isTrue,
    );
  });
}
