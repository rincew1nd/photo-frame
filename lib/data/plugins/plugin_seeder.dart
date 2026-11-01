import 'package:photoframe/data/plugins/plugin_bundle.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';
import 'package:photoframe/data/plugins/plugin_store.dart';

/// One bundled example plugin, loaded from app assets.
class BundledPluginSource {
  const BundledPluginSource({
    required this.id,
    required this.zipBytes,
    required this.defaultEnabled,
  });

  final String id;
  final List<int> zipBytes;
  final bool defaultEnabled;
}

/// Counts and failures from one seeding pass.
class PluginSeedResult {
  const PluginSeedResult({
    this.installed = 0,
    this.updated = 0,
    this.skipped = 0,
    this.failed = 0,
    this.failures = const <String>[],
  });

  final int installed;
  final int updated;
  final int skipped;
  final int failed;
  final List<String> failures;

  bool get succeeded => failed == 0;

  PluginSeedResult plus({
    int installed = 0,
    int updated = 0,
    int skipped = 0,
    int failed = 0,
    String? failure,
  }) {
    final mergedFailures = <String>[...failures];
    if (failure != null) {
      mergedFailures.add(failure);
    }
    return PluginSeedResult(
      installed: this.installed + installed,
      updated: this.updated + updated,
      skipped: this.skipped + skipped,
      failed: this.failed + failed,
      failures: mergedFailures,
    );
  }
}

/// Seeds bundled example plugins through the normal validate/install path.
///
/// A bad example is skipped and reported; the rest still install. The seed
/// marker is written only when no source failed, so a transient failure is
/// retried on the next launch.
class PluginSeeder {
  const PluginSeeder({
    this.validator = const PluginBundleValidator(),
    this.hostApiVersion = supportedPluginApiVersion,
    this.hostAppVersion = '1.0.0',
  });

  final PluginBundleValidator validator;
  final int hostApiVersion;
  final String hostAppVersion;

  Future<PluginSeedResult> seed({
    required PluginStore store,
    required Iterable<BundledPluginSource> sources,
    required bool alreadySeeded,
    required Future<void> Function() markSeeded,
    bool installMissing = true,
    bool updateExisting = false,
  }) async {
    if (alreadySeeded && !updateExisting) {
      return PluginSeedResult(skipped: sources.length);
    }

    var result = const PluginSeedResult();
    final installed = <String, InstalledPlugin>{
      for (final plugin in await store.list()) plugin.id: plugin,
    };
    final installedIds = installed.keys.toSet();

    for (final source in sources) {
      final existing = installed[source.id];
      if (existing != null) {
        if (!updateExisting || existing.source != pluginSourceBundled) {
          result = result.plus(skipped: 1);
          continue;
        }
        try {
          final bundle = validator.validate(
            source.zipBytes,
            installedIds: installedIds.difference({source.id}),
            hostApiVersion: hostApiVersion,
            hostAppVersion: hostAppVersion,
          );
          await store.update(
            bundle,
            enabled: existing.enabled,
            resetPlacement: true,
          );
          result = result.plus(updated: 1);
        } on Object catch (error) {
          result = result.plus(
            failed: 1,
            failure: '${source.id}: $error',
          );
        }
        continue;
      }
      if (!installMissing) {
        result = result.plus(skipped: 1);
        continue;
      }
      try {
        final bundle = validator.validate(
          source.zipBytes,
          installedIds: installedIds,
          hostApiVersion: hostApiVersion,
          hostAppVersion: hostAppVersion,
        );
        await store.install(
          bundle,
          enabled: source.defaultEnabled,
          source: pluginSourceBundled,
        );
        installedIds.add(bundle.manifest.id);
        result = result.plus(installed: 1);
      } on Object catch (error) {
        result = result.plus(
          failed: 1,
          failure: '${source.id}: $error',
        );
      }
    }

    if (result.succeeded) {
      await markSeeded();
    }
    return result;
  }
}
