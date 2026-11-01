import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/cache/app_database.dart';
import 'package:photoframe/data/plugins/plugin_bundle.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';
import 'package:photoframe/data/plugins/plugin_seeder.dart';
import 'package:photoframe/data/plugins/plugin_store.dart';
import 'package:photoframe/platform/paths.dart';

import 'plugin_test_support.dart';

void main() {
  late Directory temporary;
  late AppDatabase database;
  late PluginStore store;

  BundledPluginSource source(
    String id, {
    bool defaultEnabled = false,
    String version = '1.0.0',
  }) {
    return BundledPluginSource(
      id: id,
      zipBytes: buildBundleZip(
        manifest: sampleManifest(id: id, version: version),
      ),
      defaultEnabled: defaultEnabled,
    );
  }

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('photoframe_seeder_');
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

  test('seeds through the normal install path and marks once', () async {
    var marked = 0;
    final result = await PluginSeeder().seed(
      store: store,
      sources: <BundledPluginSource>[
        source('com.example.clock', defaultEnabled: true),
        source('com.example.other'),
      ],
      alreadySeeded: false,
      markSeeded: () async => marked++,
    );

    expect(result.installed, 2);
    expect(result.failed, 0);
    expect(marked, 1);
    expect((await store.get('com.example.clock'))!.enabled, isTrue);
    expect((await store.get('com.example.other'))!.enabled, isFalse);
    expect((await store.list()).map((plugin) => plugin.source).toSet(), {
      pluginSourceBundled,
    });
  });

  test('does nothing when already seeded', () async {
    var marked = 0;
    final result = await PluginSeeder().seed(
      store: store,
      sources: <BundledPluginSource>[source('com.example.clock')],
      alreadySeeded: true,
      markSeeded: () async => marked++,
    );

    expect(result.installed, 0);
    expect(result.skipped, 1);
    expect(marked, 0);
    expect(await store.list(), isEmpty);
  });

  test('skips an already installed id without failing the pass', () async {
    var marked = 0;
    final initial = source('com.example.clock');
    await store.install(
      const PluginBundleValidator().validate(
        initial.zipBytes,
        hostApiVersion: supportedPluginApiVersion,
        hostAppVersion: '2.0.0',
      ),
      enabled: false,
      source: pluginSourceZip,
    );

    final result = await PluginSeeder().seed(
      store: store,
      sources: <BundledPluginSource>[initial, source('com.example.other')],
      alreadySeeded: false,
      markSeeded: () async => marked++,
    );

    expect(result.installed, 1);
    expect(result.skipped, 1);
    expect(result.failed, 0);
    expect(marked, 1);
  });

  test('does not mark seeded when a source fails', () async {
    var marked = 0;
    final result = await PluginSeeder().seed(
      store: store,
      sources: <BundledPluginSource>[
        const BundledPluginSource(
          id: 'com.example.broken',
          zipBytes: <int>[1, 2, 3],
          defaultEnabled: false,
        ),
        source('com.example.other'),
      ],
      alreadySeeded: false,
      markSeeded: () async => marked++,
    );

    expect(result.failed, 1);
    expect(result.installed, 1);
    expect(marked, 0);
    expect(await store.isSeeded(), isFalse);
  });
}
