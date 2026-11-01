import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/app/bootstrap.dart';
import 'package:photoframe/app/connection_providers.dart' as conn;
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/data/cache/app_database.dart';
import 'package:photoframe/data/secure/secure_store.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/platform/paths.dart';
import 'package:photoframe/platform/services.dart';

import '../support/mock_immich_server.dart';

class _NoopKeepAwake implements KeepAwakeService {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}

  @override
  Future<bool> get isEnabled async => false;
}

class _NoopBiometrics implements BiometricsService {
  @override
  Future<bool> get canAuthenticate async => false;

  @override
  Future<bool> authenticate(String reason) async => true;
}

class _NoopSingleInstance implements SingleInstanceService {
  @override
  Future<bool> acquire() async => true;

  @override
  Future<void> release() async {}
}

void main() {
  late MockImmichServer server;
  late Directory tempDirectory;
  late Bootstrap bootstrap;
  late ProviderContainer container;

  setUp(() async {
    server = await MockImmichServer.start();
    tempDirectory = Directory.systemTemp.createTempSync('photoframe_test_');
    bootstrap = Bootstrap(
      paths: InMemoryAppPaths(tempDirectory),
      logger: AppLogger(),
      settings: InMemorySettingsRepository(),
      secure: MemorySecureStore(),
      database: AppDatabase(NativeDatabase.memory()),
      platform: PlatformServices(
        keepAwake: _NoopKeepAwake(),
        fullscreen: const UnsupportedFullscreen(),
        biometrics: _NoopBiometrics(),
        singleInstance: _NoopSingleInstance(),
        autostart: const UnsupportedAutostart(),
        permissions: const UnsupportedPermissions(),
        kiosk: const UnsupportedKiosk(),
        brightness: const UnsupportedBrightness(),
        livePhotoBounce: const PlatformLivePhotoBounceSupport(),
      ),
    );
    container = ProviderContainer(
      overrides: [bootstrapProvider.overrideWithValue(bootstrap)],
    );
  });

  tearDown(() async {
    container.dispose();
    await server.close();
    await bootstrap.database.close();
    try {
      tempDirectory.deleteSync(recursive: true);
    } on Object {
      return;
    }
  });

  test('builds from cached settings without network access', () async {
    await bootstrap.settings.save(
      AppSettings(
        connection: ConnectionSettings(
          serverUrl: 'https://photos.example.com/api',
          permissions: const <String, String>{'user.read': 'granted'},
          lastConnectedAt: DateTime.utc(2026, 1, 1),
        ),
      ),
    );

    final state = await container.read(
      conn.connectionControllerProvider.future,
    );

    expect(state.report, isNotNull);
    expect(state.isConnected, isTrue);
    expect(state.albums, isEmpty);
  });

  test('connectWithApiKey stores credentials and fetches albums', () async {
    final initial = await container.read(
      conn.connectionControllerProvider.future,
    );
    expect(initial.isConnected, isFalse);

    final controller = container.read(
      conn.connectionControllerProvider.notifier,
    );
    final report = await controller.connectWithApiKey(
      server.rootUrl.toString(),
      'test-key',
    );

    final state = container
        .read(conn.connectionControllerProvider)
        .requireValue;
    expect(report?.canConnect, isTrue);
    expect(state.isConnected, isTrue);
    expect(state.settings.connection.serverUrl, server.apiUrl.toString());
    expect(state.settings.connection.permissions['user.read'], 'granted');
    expect(state.settings.connection.permissions['asset.download'], 'granted');
    expect(state.albums, hasLength(2));
    expect(await bootstrap.secure.read(SecretKeys.immichApiKey), 'test-key');
    expect(await bootstrap.secure.read(SecretKeys.immichAccessToken), isNull);
  });

  test('refreshAlbums keeps albums when the request fails', () async {
    final controller = container.read(
      conn.connectionControllerProvider.notifier,
    );
    await controller.connectWithApiKey(server.rootUrl.toString(), 'test-key');
    await controller.refreshAlbums();
    var state = container.read(conn.connectionControllerProvider).requireValue;
    expect(state.albums, hasLength(2));
    expect(state.failure, isNull);

    server.unauthorized = true;
    await controller.refreshAlbums();
    state = container.read(conn.connectionControllerProvider).requireValue;
    expect(state.albums, hasLength(2));
    expect(state.failure, isNotNull);
  });

  test('saveAlbumSelection persists the selection', () async {
    final controller = container.read(
      conn.connectionControllerProvider.notifier,
    );
    await controller.connectWithApiKey(server.rootUrl.toString(), 'test-key');
    await controller.saveAlbumSelection(<String>{'album-1', 'album-2'});

    final stored = await bootstrap.settings.load();
    final state = container
        .read(conn.connectionControllerProvider)
        .requireValue;
    expect(stored.connection.albumIds, <String>{'album-1', 'album-2'});
    expect(state.selectedAlbumIds, <String>{'album-1', 'album-2'});
  });

  test('disconnect clears secrets and connection settings', () async {
    final controller = container.read(
      conn.connectionControllerProvider.notifier,
    );
    await controller.connectWithApiKey(server.rootUrl.toString(), 'test-key');
    await controller.disconnect();

    final state = container
        .read(conn.connectionControllerProvider)
        .requireValue;
    expect(await bootstrap.secure.read(SecretKeys.immichApiKey), isNull);
    expect(await bootstrap.secure.read(SecretKeys.immichAccessToken), isNull);
    expect((await bootstrap.settings.load()).connection.serverUrl, isNull);
    expect(state.isConnected, isFalse);
    expect(state.report, isNull);
  });
}
