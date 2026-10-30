import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/features/settings/settings_scaffold.dart';

class AboutSettingsScreen extends ConsumerStatefulWidget {
  const AboutSettingsScreen({super.key});

  @override
  ConsumerState<AboutSettingsScreen> createState() =>
      _AboutSettingsScreenState();
}

class _AboutSettingsScreenState extends ConsumerState<AboutSettingsScreen> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(appLoggerProvider).recentLines;
    final lines = recent.length > 50
        ? recent.sublist(recent.length - 50)
        : recent;
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
