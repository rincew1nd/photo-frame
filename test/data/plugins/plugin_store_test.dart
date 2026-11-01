import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/cache/app_database.dart';
import 'package:photoframe/data/plugins/plugin_bundle.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';
import 'package:photoframe/data/plugins/plugin_store.dart';
import 'package:photoframe/platform/paths.dart';

import 'plugin_test_support.dart';

void main() {
  late Directory temporary;
  late AppDatabase database;
  late PluginStore store;

  PluginBundle bundle({
    String id = 'com.example.test',
    String version = '1.0.0',
    bool withSettings = true,
  }) {
    final manifest = sampleManifest(
      id: id,
      version: version,
      settings: withSettings
          ? <String, dynamic>{
              'color': <String, dynamic>{
                'type': 'color',
                'label': 'Color',
                'default': '#FFFFFFFF',
              },
            }
          : null,
    );
    final zip = buildBundleZip(manifest: manifest);
    return PluginBundleValidator().validate(
      zip,
      installedIds: const <String>{},
      hostApiVersion: supportedPluginApiVersion,
      hostAppVersion: '2.0.0',
    );
  }

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('photoframe_plugins_');
    database = AppDatabase(NativeDatabase.memory());
    store = PluginStore(database, InMemoryAppPaths(temporary));
    await store.init();
  });

  tearDown(() async {
    await database.close();
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('installs, lists, and reads a plugin with defaults', () async {
    final installed = await store.install(
      bundle(),
      enabled: true,
      source: pluginSourceZip,
    );

    expect(installed.id, 'com.example.test');
    expect(installed.enabled, isTrue);
    expect(installed.source, pluginSourceZip);
    expect(installed.config, <String, dynamic>{'color': '#FFFFFFFF'});
    expect(installed.placement.width, 320);
    expect(installed.placement.height, 160);
    expect(await File(installed.bundlePath).exists(), isFalse);
    expect(await Directory(installed.bundlePath).exists(), isTrue);
    expect((await store.list()).single.id, installed.id);
  });

  test('duplicate install is rejected', () async {
    await store.install(bundle(), enabled: true, source: pluginSourceZip);
    expect(
      () => store.install(bundle(), enabled: true, source: pluginSourceZip),
      throwsA(isA<PluginStoreException>()),
    );
  });

  test('enable, visible, config, placement, and storage persist', () async {
    await store.install(bundle(), enabled: true, source: pluginSourceZip);

    await store.setEnabled('com.example.test', false);
    await store.setVisible('com.example.test', false);
    await store.setConfig('com.example.test', <String, dynamic>{
      'color': '#80000000',
    });
    await store.setPlacement(
      'com.example.test',
      const PluginPlacement(
        x: 0.1,
        y: 0.2,
        width: 400,
        height: 200,
        zOrder: 20,
        showDuringNight: true,
      ),
    );
    await store.storageSet('com.example.test', 'key', '"value"');

    final plugin = await store.get('com.example.test');
    expect(plugin!.enabled, isFalse);
    expect(plugin.visible, isFalse);
    expect(plugin.config, <String, dynamic>{'color': '#80000000'});
    expect(plugin.placement.x, 0.1);
    expect(plugin.placement.y, 0.2);
    expect(plugin.placement.zOrder, 20);
    expect(plugin.placement.showDuringNight, isTrue);
    expect(await store.storageGet('com.example.test', 'key'), '"value"');
  });

  test('storage quota is enforced', () async {
    await store.install(bundle(), enabled: true, source: pluginSourceZip);
    final tooLarge = 'x' * (PluginStore.storageQuotaBytes + 1);

    expect(
      () => store.storageSet('com.example.test', 'key', tooLarge),
      throwsA(isA<PluginValidationException>()),
    );
  });

  test('update preserves compatible config and placement', () async {
    await store.install(bundle(), enabled: true, source: pluginSourceZip);
    await store.setConfig('com.example.test', <String, dynamic>{
      'color': '#80000000',
    });
    await store.setPlacement(
      'com.example.test',
      const PluginPlacement(width: 400, height: 220),
    );

    final updated = await store.update(
      bundle(version: '1.1.0'),
      enabled: false,
    );

    expect(updated.config, <String, dynamic>{'color': '#80000000'});
    expect(updated.placement.width, 400);
    expect(updated.placement.height, 220);
    expect(updated.enabled, isFalse);
  });

  test('update resets config when the settings schema changes', () async {
    await store.install(bundle(), enabled: true, source: pluginSourceZip);
    await store.setConfig('com.example.test', <String, dynamic>{
      'color': '#80000000',
    });

    final updated = await store.update(
      bundle(version: '2.0.0', withSettings: false),
      enabled: true,
    );

    expect(updated.config, isEmpty);
  });

  test('delete removes registry, config, storage, and bundle files', () async {
    final installed = await store.install(
      bundle(),
      enabled: true,
      source: pluginSourceZip,
    );
    await store.storageSet('com.example.test', 'key', '"value"');

    await store.delete('com.example.test');

    expect(await store.get('com.example.test'), isNull);
    expect(await Directory(installed.bundlePath).exists(), isFalse);
    expect(
      () => store.storageGet('com.example.test', 'key'),
      throwsA(isA<PluginStoreException>()),
    );
    final storageRows = await database
        .customSelect(
          'SELECT COUNT(*) AS count FROM plugin_storage '
          'WHERE plugin_id = ?',
          variables: <Variable>[
            Variable.withString('com.example.test'),
          ],
        )
        .get();
    expect(storageRows.single.read<int>('count'), 0);
  });

  test('seed marker is stored once', () async {
    expect(await store.isSeeded(), isFalse);
    await store.markSeeded();
    expect(await store.isSeeded(), isTrue);
  });
}
