import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/app/connection_providers.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/core/logging/app_logger.dart';
import 'package:photoframe/data/cache/cache_store.dart';
import 'package:photoframe/data/immich/immich_client.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/data/settings/settings_repository.dart';
import 'package:photoframe/features/slideshow/slideshow_controller.dart';
import 'package:photoframe/platform/paths.dart';

import '../support/mock_immich_server.dart';

class _FakeConnectionController extends ConnectionController {
  _FakeConnectionController(this.client);

  final ImmichClient client;

  @override
  Future<ConnectionState> build() async =>
      const ConnectionState(settings: AppSettings());

  @override
  Future<ImmichClient> clientFromStoredCredentials() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return client;
  }
}

void main() {
  late MockImmichServer server;
  late Directory temporary;
  late InMemoryAppPaths paths;
  late MemoryCacheStore store;
  late ImmichClient client;
  late ProviderContainer container;

  setUp(() async {
    server = await MockImmichServer.start();
    temporary = Directory.systemTemp.createTempSync('photoframe_slideshow_');
    paths = InMemoryAppPaths(temporary);
    store = MemoryCacheStore();
    client = ImmichClient(baseUri: server.apiUrl, apiKey: 'test-key');
    final settings = AppSettings(
      connection: ConnectionSettings(
        serverUrl: server.apiUrl.toString(),
        albumIds: const <String>{'album-1'},
      ),
    );
    container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(settings),
        ),
        cacheStoreProvider.overrideWithValue(store),
        appPathsProvider.overrideWithValue(paths),
        appLoggerProvider.overrideWithValue(AppLogger()),
        connectionControllerProvider.overrideWith(
          () => _FakeConnectionController(client),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await server.close();
    if (temporary.existsSync()) {
      temporary.deleteSync(recursive: true);
    }
  });

  test('build auto-syncs an empty cache and clears the syncing flag', () async {
    final initial = await container.read(slideshowControllerProvider.future);
    expect(initial.cached, isEmpty);
    expect(initial.syncing, isTrue);

    SlideshowViewState? state;
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      state = container.read(slideshowControllerProvider).value;
      final assets = await store.allAssets();
      if (state != null && !state.syncing && assets.length == 3) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    state = container.read(slideshowControllerProvider).value;
    expect(state?.syncing, isFalse);
    expect(state?.cached, hasLength(3));
    expect(state?.current, isNotNull);
    expect(await store.allAssets(), hasLength(3));
  });
}
