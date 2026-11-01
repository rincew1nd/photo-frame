import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/features/settings/settings_scaffold.dart';

class AboutSettingsScreen extends ConsumerStatefulWidget {
  const AboutSettingsScreen({super.key});

  @override
  ConsumerState<AboutSettingsScreen> createState() =>
      _AboutSettingsScreenState();
}

class _AboutSettingsScreenState extends ConsumerState<AboutSettingsScreen> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();
  late final Future<CacheStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = ref.read(cacheStoreProvider).stats();
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(appLoggerProvider).recentLines;
    final lines = recent.length > 50
        ? recent.sublist(recent.length - 50)
        : recent;
    final errors = recent
        .where((line) => line.contains('[ERROR]'))
        .toList(growable: false);
    return SettingsScaffold(
      title: 'About & diagnostics',
      body: ListView(
        children: <Widget>[
          FutureBuilder<PackageInfo>(
            future: _packageInfo,
            builder: (context, snapshot) {
              final info = snapshot.data;
              return Column(
                children: <Widget>[
                  ListTile(
                    title: const Text('Version'),
                    trailing: Text(info?.version ?? 'Unknown'),
                  ),
                  ListTile(
                    title: const Text('Build number'),
                    trailing: Text(info?.buildNumber ?? 'Unknown'),
                  ),
                ],
              );
            },
          ),
          const ListTile(title: Text('Plugin API'), trailing: Text('v1')),
          const SettingsSectionHeader('Platform'),
          ListTile(
            title: const Text('Operating system'),
            trailing: Text(Platform.operatingSystem),
          ),
          ListTile(
            title: const Text('OS version'),
            trailing: Text(Platform.operatingSystemVersion),
          ),
          const SettingsSectionHeader('Cache'),
          FutureBuilder<CacheStats>(
            future: _statsFuture,
            builder: (context, snapshot) {
              final stats = snapshot.data;
              if (stats == null) {
                return ListTile(
                  title: Text(
                    snapshot.hasError
                        ? 'Unable to load statistics'
                        : 'Loading statistics...',
                  ),
                );
              }
              return Column(
                children: <Widget>[
                  ListTile(
                    title: const Text('Assets'),
                    trailing: Text('${stats.assetCount}'),
                  ),
                  ListTile(
                    title: const Text('Images'),
                    trailing: Text(
                      '${stats.imageCount} · ${_formatBytes(stats.imageBytes)}',
                    ),
                  ),
                  ListTile(
                    title: const Text('Videos'),
                    trailing: Text(
                      '${stats.videoCount} · ${_formatBytes(stats.videoBytes)}',
                    ),
                  ),
                  ListTile(
                    title: const Text('Total'),
                    trailing: Text(_formatBytes(stats.totalBytes)),
                  ),
                  ListTile(
                    title: const Text('Last sync'),
                    subtitle: Text(
                      stats.lastSync == null
                          ? 'Never synced'
                          : _formatDateTime(stats.lastSync!),
                    ),
                  ),
                ],
              );
            },
          ),
          FutureBuilder<PackageInfo>(
            future: _packageInfo,
            builder: (context, snapshot) {
              final info = snapshot.data;
              return ListTile(
                title: const Text('Licenses'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: info?.appName ?? 'Photo Frame',
                  applicationVersion: info?.version,
                ),
              );
            },
          ),
          const SettingsSectionHeader('Crash reports'),
          if (errors.isEmpty)
            const ListTile(title: Text('No errors logged'))
          else ...[
            ListTile(
              title: Text(
                '${errors.length} error${errors.length == 1 ? '' : 's'} logged',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextButton(
                onPressed: () => _copy(context, errors),
                child: const Text('Copy errors'),
              ),
            ),
          ],
          const SettingsSectionHeader('Recent logs'),
          if (lines.isEmpty)
            const ListTile(title: Text('No log entries'))
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  lines.join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextButton(
              onPressed: () => _copy(context, lines),
              child: const Text('Copy logs'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, List<String> lines) async {
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Logs copied')));
  }
}

String _formatBytes(int bytes) {
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
