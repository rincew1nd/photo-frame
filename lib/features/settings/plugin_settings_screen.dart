import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';
import 'package:photoframe/data/plugins/plugin_store.dart';
import 'package:photoframe/features/settings/plugin_ui.dart';
import 'package:photoframe/features/settings/settings_scaffold.dart';

class PluginSettingsScreen extends ConsumerWidget {
  const PluginSettingsScreen({super.key, required this.pluginId});

  final String pluginId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(installedPluginsProvider);
    return plugins.when(
      loading: () => const SettingsScaffold(
        title: 'Plugin',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => const SettingsScaffold(
        title: 'Plugin',
        body: Center(child: Text('Unable to load plugins')),
      ),
      data: (items) {
        InstalledPlugin? plugin;
        for (final item in items) {
          if (item.id == pluginId) {
            plugin = item;
            break;
          }
        }
        if (plugin == null) {
          return const SettingsScaffold(
            title: 'Plugin',
            body: Center(child: Text('This plugin is not installed.')),
          );
        }
        return _PluginDetails(key: ValueKey(plugin.id), plugin: plugin);
      },
    );
  }
}

class _PluginDetails extends ConsumerStatefulWidget {
  const _PluginDetails({super.key, required this.plugin});

  final InstalledPlugin plugin;

  @override
  ConsumerState<_PluginDetails> createState() => _PluginDetailsState();
}

class _PluginDetailsState extends ConsumerState<_PluginDetails>
    with WidgetsBindingObserver {
  late final Map<String, dynamic> _values = <String, dynamic>{
    ...widget.plugin.config,
  };
  bool _saving = false;
  bool? _notificationAccess;

  InstalledPlugin get plugin => widget.plugin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshNotificationAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotificationAccess();
    }
  }

  Future<void> _refreshNotificationAccess() async {
    final granted = await ref
        .read(mediaSessionServiceProvider)
        .hasNotificationAccess;
    if (mounted) {
      setState(() => _notificationAccess = granted);
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    try {
      await ref.read(pluginStoreProvider).setConfig(plugin.id, _values);
      ref.invalidate(installedPluginsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plugin settings saved.')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save settings: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _toggle(bool enabled) async {
    await ref.read(pluginStoreProvider).setEnabled(plugin.id, enabled);
    ref.invalidate(installedPluginsProvider);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete plugin?'),
        content: Text(
          'This removes ${plugin.manifest.name}, its configuration, and its '
          'plugin storage.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(pluginStoreProvider).delete(plugin.id);
    ref.invalidate(installedPluginsProvider);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _update() async {
    final result = await showPluginZipImportDialog(
      context,
      updatePluginId: plugin.id,
    );
    if (result != null) {
      ref.invalidate(installedPluginsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manifest = plugin.manifest;
    final theme = Theme.of(context);
    return SettingsScaffold(
      title: manifest.name,
      body: ListView(
        children: <Widget>[
          ListTile(
            leading: pluginIcon(plugin, size: 56),
            title: Text(manifest.name),
            subtitle: Text(
              '${manifest.id} · v${manifest.version.value} · '
              '${pluginSourceLabel(plugin.source)}',
            ),
            trailing: Switch(
              value: plugin.enabled,
              onChanged: _toggle,
            ),
          ),
          if (manifest.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(manifest.description),
            ),
          const SettingsSectionHeader('Details'),
          _detail('Author', manifest.author),
          _detail('License', manifest.license),
          _detail('API version', 'v${manifest.apiVersion}'),
          _detail(
            'Permissions',
            manifest.permissions.network ? 'Network' : 'No network',
          ),
          _detail(
            'Inputs',
            manifest.inputs.isEmpty
                ? 'App/time only'
                : manifest.inputs.map((input) => input.name).join(', '),
          ),
          _detail(
            'Placement',
            '${plugin.placement.width.round()}×'
            '${plugin.placement.height.round()} · z${plugin.placement.zOrder}',
          ),
          if (manifest.inputs.contains(PluginInput.media)) ...<Widget>[
            const SettingsSectionHeader('Background media'),
            ListTile(
              key: const ValueKey<String>('notification-access-tile'),
              leading: const Icon(Icons.music_note_outlined),
              title: const Text('Notification access'),
              subtitle: Text(
                switch (_notificationAccess) {
                  null => 'Checking…',
                  true => 'Granted · background media is available',
                  false =>
                    'Not granted · tap to open notification access settings',
                },
              ),
              trailing: IconButton(
                tooltip: 'Refresh notification access',
                icon: const Icon(Icons.refresh),
                onPressed: _refreshNotificationAccess,
              ),
              onTap: () => ref
                  .read(mediaSessionServiceProvider)
                  .openNotificationAccessSettings(),
            ),
          ],
          if (manifest.screenshots.isNotEmpty) ...<Widget>[
            const SettingsSectionHeader('Screenshots'),
            for (final screenshot in manifest.screenshots)
              _screenshot(screenshot),
          ],
          if (manifest.settings.isNotEmpty) ...<Widget>[
            const SettingsSectionHeader('Settings'),
            for (final field in manifest.settings) _field(field),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _saving ? null : _saveConfig,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save settings'),
              ),
            ),
          ],
          const SettingsSectionHeader('Placement'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Move and resize this plugin from the slideshow.',
            ),
          ),
          const SettingsSectionHeader('Actions'),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('Update from ZIP'),
            onTap: _update,
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            title: Text(
              'Delete plugin',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: _delete,
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(value, textAlign: TextAlign.end),
    );
  }

  Widget _screenshot(String relative) {
    final file = File(p.join(plugin.bundlePath, relative));
    if (!file.existsSync()) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          file,
          height: 180,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _field(PluginSettingField field) {
    final value = _values[field.key] ?? field.defaultValue;
    switch (field.type) {
      case PluginSettingType.boolean:
        return SwitchListTile(
          title: Text(field.label),
          subtitle: field.help == null ? null : Text(field.help!),
          value: value == true,
          onChanged: (next) => setState(() => _values[field.key] = next),
        );
      case PluginSettingType.select:
        final selected = field.options.any((option) => option.value == value)
            ? value as String
            : field.options.first.value;
        return ListTile(
          title: Text(field.label),
          subtitle: field.help == null ? null : Text(field.help!),
          trailing: DropdownButton<String>(
            value: selected,
            onChanged: (next) {
              if (next != null) {
                setState(() => _values[field.key] = next);
              }
            },
            items: <DropdownMenuItem<String>>[
              for (final option in field.options)
                DropdownMenuItem<String>(
                  value: option.value,
                  child: Text(option.label),
                ),
            ],
          ),
        );
      case PluginSettingType.number:
        return ListTile(
          title: Text(field.label),
          subtitle: Text(
            field.help == null ? '${value ?? ''}' : '${field.help} · $value',
          ),
          trailing: SizedBox(
            width: 140,
            child: TextFormField(
              initialValue: '$value',
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              onChanged: (text) {
                final parsed = num.tryParse(text.trim());
                if (parsed != null) {
                  _values[field.key] = parsed;
                }
              },
            ),
          ),
        );
      case PluginSettingType.multiline:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextFormField(
            initialValue: '$value',
            minLines: field.rows ?? 3,
            maxLines: field.rows ?? 6,
            maxLength: field.maxLength,
            decoration: InputDecoration(
              labelText: field.label,
              helperText: field.help,
            ),
            onChanged: (text) => _values[field.key] = text,
          ),
        );
      case PluginSettingType.text:
      case PluginSettingType.color:
      case PluginSettingType.url:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextFormField(
            initialValue: '$value',
            maxLength: field.maxLength,
            decoration: InputDecoration(
              labelText: field.label,
              helperText: field.help ?? _fieldHint(field),
            ),
            onChanged: (text) => _values[field.key] = text,
          ),
        );
    }
  }

  String? _fieldHint(PluginSettingField field) {
    return switch (field.type) {
      PluginSettingType.color => 'Use #RRGGBB or #AARRGGBB',
      PluginSettingType.url => 'https://example.com',
      _ => null,
    };
  }
}
