import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/core/clock.dart';
import 'package:photoframe/core/failures.dart';
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/data/immich/auth_service.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/data/secure/secure_store.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/settings/settings_repository.dart';

import '../../support/mock_immich_server.dart';

class FixedClock implements Clock {
  FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

void main() {
  late MockImmichServer server;
  late MemorySecureStore secure;
  late InMemorySettingsRepository settings;
  late AuthService service;
  final now = DateTime.utc(2024, 5, 1, 12);

  setUp(() async {
    server = await MockImmichServer.start();
    secure = MemorySecureStore();
    settings = InMemorySettingsRepository();
    service = AuthService(
      secure: secure,
      settings: settings,
      logger: AppLogger(),
      clock: FixedClock(now),
    );
  });

  tearDown(() async {
    await server.close();
  });

  test('persists credentials and connection only on success', () async {
    final report = await service.connectWithApiKey(
      serverBase: server.rootUrl,
      apiKey: 'test-key',
      userId: 'user-1',
      userEmail: 'test@example.com',
      userName: 'Test User',
    );

    expect(report.canConnect, isTrue);
    expect(await secure.read(SecretKeys.immichApiKey), 'test-key');
    expect(await secure.read(SecretKeys.immichAccessToken), isNull);
    expect(await service.readApiKeyForReveal(), 'test-key');

    final loaded = await settings.load();
    expect(loaded.connection.serverUrl, server.apiUrl.toString());
    expect(loaded.connection.authMode, AuthMode.apiKey);
    expect(loaded.connection.userId, 'user-1');
    expect(loaded.connection.userEmail, 'test@example.com');
    expect(loaded.connection.userName, 'Test User');
    expect(loaded.connection.permissions['user.read'], 'granted');
    expect(loaded.connection.permissions['asset.download'], 'granted');
    expect(loaded.connection.lastConnectedAt, now);
  });

  test('does not persist when a blocking permission fails', () async {
    server.denyAlbum = true;

    final report = await service.connectWithApiKey(
      serverBase: server.rootUrl,
      apiKey: 'test-key',
    );

    expect(report.canConnect, isFalse);
    expect(report.blockingFailure?.kind, FailureKind.permission);
    expect(await secure.read(SecretKeys.immichApiKey), isNull);
    expect((await settings.load()).connection.serverUrl, isNull);
  });

  test('rejects invalid server URLs without persisting', () async {
    final report = await service.connectWithApiKey(
      serverBase: Uri.parse('ftp://invalid'),
      apiKey: 'test-key',
    );

    expect(report.canConnect, isFalse);
    expect(report.blockingFailure?.kind, FailureKind.invalidResponse);
    expect(await secure.read(SecretKeys.immichApiKey), isNull);
    expect((await settings.load()).connection.serverUrl, isNull);
  });

  test('disconnect clears secrets and resets connection settings', () async {
    await secure.write(SecretKeys.immichApiKey, 'test-key');
    await secure.write(SecretKeys.immichAccessToken, 'access-token');
    await settings.save(
      const AppSettings().copyWith(
        connection: const ConnectionSettings(
          serverUrl: 'http://host/api',
          authMode: AuthMode.oauth,
          userId: 'user-1',
          permissions: <String, String>{'user.read': 'granted'},
          albumIds: <String>{'album-1'},
        ),
        playback: const PlaybackSettings(intervalSeconds: 42),
      ),
    );

    await service.disconnect();

    expect(await secure.read(SecretKeys.immichApiKey), isNull);
    expect(await secure.read(SecretKeys.immichAccessToken), isNull);

    final loaded = await settings.load();
    expect(loaded.connection.serverUrl, isNull);
    expect(loaded.connection.userId, isNull);
    expect(loaded.connection.albumIds, isEmpty);
    expect(loaded.playback.intervalSeconds, 42);
  });

  test('persists an OAuth api key with oauth auth mode', () async {
    final report = await service.connectWithOAuth(
      serverBase: server.rootUrl,
      session: const ImmichAuthSession(
        apiKey: 'test-key',
        accessToken: 'oauth-access-token',
        authMode: AuthMode.oauth,
      ),
      userId: 'user-1',
    );

    expect(report.canConnect, isTrue);
    expect(await secure.read(SecretKeys.immichApiKey), 'test-key');
    expect(await secure.read(SecretKeys.immichAccessToken), isNull);

    final loaded = await settings.load();
    expect(loaded.connection.authMode, AuthMode.oauth);
    expect(loaded.connection.serverUrl, server.apiUrl.toString());
  });

  test('falls back to the OAuth access token when no api key exists', () async {
    final report = await service.connectWithOAuth(
      serverBase: server.rootUrl,
      session: const ImmichAuthSession(
        accessToken: 'oauth-access-token',
        authMode: AuthMode.oauth,
      ),
    );

    expect(report.canConnect, isTrue);
    expect(await secure.read(SecretKeys.immichApiKey), isNull);
    expect(
      await secure.read(SecretKeys.immichAccessToken),
      'oauth-access-token',
    );
    expect((await settings.load()).connection.authMode, AuthMode.oauth);
  });

  test('rechecks permissions with stored credentials', () async {
    await service.connectWithApiKey(
      serverBase: server.rootUrl,
      apiKey: 'test-key',
    );

    final report = await service.recheckPermissions();

    expect(report, isNotNull);
    expect(report!.canConnect, isTrue);
    expect(report.user?.id, 'user-1');
  });
}
