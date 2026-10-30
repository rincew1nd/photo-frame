import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:photoframe/core/failures.dart';
import 'package:photoframe/data/immich/immich_client.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:url_launcher/url_launcher.dart';

typedef OAuthBrowserLauncher = Future<bool> Function(Uri url);

/// A PKCE verifier/challenge pair plus the OAuth state token.
class PkcePair {
  const PkcePair({
    required this.verifier,
    required this.challenge,
    required this.state,
  });

  final String verifier;
  final String challenge;
  final String state;

  /// Generates a random verifier and state with its S256 challenge.
  factory PkcePair.generate({Random? random}) {
    final rng = random ?? Random.secure();
    final verifier = _randomToken(rng, 64);
    final state = _randomToken(rng, 32);
    return PkcePair(
      verifier: verifier,
      challenge: _challengeFor(verifier),
      state: state,
    );
  }

  static String _challengeFor(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }
}

/// Drives Immich's OAuth PKCE sign-in flow.
class OAuthService {
  OAuthService({OAuthBrowserLauncher? launchBrowser})
    : _launch = launchBrowser ?? _launchExternal;

  final OAuthBrowserLauncher _launch;

  Future<Uri> begin({
    required Uri serverBase,
    required String redirectUri,
    PkcePair? pkce,
  }) async {
    final pair = pkce ?? PkcePair.generate();
    final client = ImmichClient(
      baseUri: ImmichClient.normalizeBaseUrl(serverBase.toString()),
    );
    final url = await client.startOAuth(
      codeChallenge: pair.challenge,
      redirectUri: redirectUri,
      state: pair.state,
    );
    try {
      await _launch(url);
    } on Object {
      return url;
    }
    return url;
  }

  Future<ImmichAuthSession> finish({
    required Uri serverBase,
    required String redirectUri,
    required Uri callbackUri,
    required PkcePair pkce,
  }) async {
    final base = ImmichClient.normalizeBaseUrl(serverBase.toString());
    final client = ImmichClient(baseUri: base);
    final accessToken = await client.completeOAuth(
      callbackUrl: callbackUri,
      codeVerifier: pkce.verifier,
      state: pkce.state,
    );

    String? apiKey;
    try {
      final authenticated = ImmichClient(baseUri: base, accessToken: accessToken);
      apiKey = await authenticated.createApiKey();
    } on Object {
      apiKey = null;
    }

    return ImmichAuthSession(
      apiKey: apiKey,
      accessToken: accessToken,
      authMode: AuthMode.oauth,
    );
  }

  Future<ImmichAuthSession> runDesktop({
    required Uri serverBase,
    PkcePair? pkce,
  }) async {
    final pair = pkce ?? PkcePair.generate();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      path: '/oauth',
    );
    final callback = Completer<Uri>();
    final subscription = server.listen((request) async {
      if (request.uri.path != '/oauth') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!DOCTYPE html><html><body>'
        '<p>Sign-in complete. You can close this window.</p>'
        '</body></html>',
      );
      await request.response.close();
      if (!callback.isCompleted) {
        callback.complete(
          redirectUri.replace(queryParameters: request.uri.queryParameters),
        );
      }
    });

    try {
      await begin(
        serverBase: serverBase,
        redirectUri: redirectUri.toString(),
        pkce: pair,
      );
      final uri = await callback.future.timeout(const Duration(minutes: 5));
      return await finish(
        serverBase: serverBase,
        redirectUri: redirectUri.toString(),
        callbackUri: uri,
        pkce: pair,
      );
    } on TimeoutException {
      throw const AppFailure(FailureKind.auth, 'Sign-in timed out');
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  }

  Future<ImmichAuthSession> runAndroid({
    required Uri serverBase,
    required Uri redirectScheme,
    PkcePair? pkce,
  }) async {
    final pair = pkce ?? PkcePair.generate();
    final links = AppLinks();
    final callback = Completer<Uri>();
    final subscription = links.uriLinkStream.listen(
      (uri) {
        if (_matches(uri, redirectScheme) && !callback.isCompleted) {
          callback.complete(uri);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!callback.isCompleted) {
          callback.completeError(error, stackTrace);
        }
      },
    );

    try {
      final initial = await links.getInitialLink();
      if (initial != null &&
          _matches(initial, redirectScheme) &&
          !callback.isCompleted) {
        callback.complete(initial);
      }
      await begin(
        serverBase: serverBase,
        redirectUri: redirectScheme.toString(),
        pkce: pair,
      );
      final uri = await callback.future.timeout(const Duration(minutes: 5));
      return await finish(
        serverBase: serverBase,
        redirectUri: redirectScheme.toString(),
        callbackUri: uri,
        pkce: pair,
      );
    } on TimeoutException {
      throw const AppFailure(FailureKind.auth, 'Sign-in timed out');
    } finally {
      await subscription.cancel();
    }
  }

  bool _matches(Uri uri, Uri expected) {
    return uri.scheme == expected.scheme &&
        (expected.host.isEmpty || uri.host == expected.host) &&
        (expected.path.isEmpty || uri.path == expected.path);
  }
}

Future<bool> _launchExternal(Uri url) {
  return launchUrl(url, mode: LaunchMode.externalApplication);
}

String _randomToken(Random random, int bytes) {
  final data = List<int>.generate(bytes, (_) => random.nextInt(256));
  return base64Url.encode(data).replaceAll('=', '');
}
