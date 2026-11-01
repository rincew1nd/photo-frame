import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/plugins/plugin_store.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/features/settings/plugin_ui.dart';
import 'package:photoframe/features/settings/settings_scaffold.dart';

class PluginsSettingsScreen extends ConsumerWidget {
  const PluginsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettings = ref.watch(settingsControllerProvider);
    return SettingsScaffold(
      title: 'Plugins',
      body: asyncSettings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Unable to load settings')),
        data: (settings) => _body(context, ref, settings),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, AppSettings settings) {
    return ListView(children: const <Widget>[_InstalledPluginsSection()]);
  }
}

class _InstalledPluginsSection extends ConsumerWidget {
  const _InstalledPluginsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(installedPluginsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SettingsSectionHeader('Installed plugins'),
        ...plugins.when(
          loading: () => const <Widget>[
            ListTile(title: Text('Loading plugins...')),
          ],
          error: (error, stackTrace) => <Widget>[
            ListTile(
              title: const Text('Unable to load plugins'),
              subtitle: Text('$error'),
              trailing: TextButton(
                onPressed: () => ref.invalidate(installedPluginsProvider),
                child: const Text('Retry'),
              ),
            ),
          ],
          data: (installed) => installed.isEmpty
              ? const <Widget>[
                  ListTile(
                    leading: Icon(Icons.extension),
                    title: Text('No plugins installed'),
                    subtitle: Text('Add a plugin ZIP to get started.'),
                  ),
                ]
              : <Widget>[
                  for (final plugin in installed)
                    _InstalledPluginTile(plugin: plugin),
                ],
        ),
        ListTile(
          key: const ValueKey<String>('add-plugin'),
          leading: const Icon(Icons.upload_file),
          title: const Text('Add plugin'),
          subtitle: const Text('Install from a ZIP file path.'),
          onTap: () => _add(context, ref),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final installed = await showPluginZipImportDialog(context);
    if (installed == null || !context.mounted) {
      return;
    }
    ref.invalidate(installedPluginsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Installed ${installed.manifest.name}.')),
    );
  }
}

class _InstalledPluginTile extends ConsumerWidget {
  const _InstalledPluginTile({required this.plugin});

  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = plugin.manifest.name;
    return ListTile(
      leading: pluginIcon(plugin),
      title: Text(name),
      subtitle: Text(
        '${plugin.version} · ${pluginSourceLabel(plugin.source)}'
        '${plugin.enabled ? '' : ' · Disabled'}',
      ),
      onTap: () => context.push('/settings/plugins/${plugin.id}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Switch(
            value: plugin.enabled,
            onChanged: (value) => _setEnabled(context, ref, value),
          ),
          IconButton(
            tooltip: 'Delete $name',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _setEnabled(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    try {
      await ref.read(pluginStoreProvider).setEnabled(plugin.id, enabled);
      ref.invalidate(installedPluginsProvider);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update the plugin: $error')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete plugin?'),
        content: Text(
          'Delete "${plugin.manifest.name}"? Its files, settings, and '
          'stored data will be removed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await ref.read(pluginStoreProvider).delete(plugin.id);
      ref.invalidate(installedPluginsProvider);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete the plugin: $error')),
        );
      }
    }
  }
}
