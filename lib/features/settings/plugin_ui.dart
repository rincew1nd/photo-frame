import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/plugins/plugin_bundle.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';
import 'package:photoframe/data/plugins/plugin_store.dart';
import 'package:photoframe/platform/paths.dart';

String pluginSourceLabel(String source) {
  return switch (source) {
    pluginSourceZip => 'ZIP',
    pluginSourceBundled => 'Bundled',
    _ => source,
  };
}

/// Plugin icon from the installed bundle, or a generic extension icon.
Widget pluginIcon(InstalledPlugin plugin, {double size = 40}) {
  final icon = plugin.manifest.icon;
  final file = icon == null
      ? null
      : fileIfExists(p.join(plugin.bundlePath, icon));
  if (file == null) {
    return Icon(Icons.extension, size: size);
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Image.file(
      file,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          Icon(Icons.extension, size: size),
    ),
  );
}

/// Installs a plugin from a ZIP path or updates an existing plugin.
///
/// Pass [updatePluginId] to replace an installed plugin instead of adding a
/// new one. Returns the installed plugin, or null when cancelled.
Future<InstalledPlugin?> showPluginZipImportDialog(
  BuildContext context, {
  String? updatePluginId,
}) {
  return showDialog<InstalledPlugin>(
    context: context,
    builder: (context) =>
        PluginZipImportDialog(updatePluginId: updatePluginId),
  );
}

class PluginZipImportDialog extends ConsumerStatefulWidget {
  const PluginZipImportDialog({super.key, this.updatePluginId});

  final String? updatePluginId;

  @override
  ConsumerState<PluginZipImportDialog> createState() =>
      _PluginZipImportDialogState();
}

class _PluginZipImportDialogState
    extends ConsumerState<PluginZipImportDialog> {
  final TextEditingController _path = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final path = _path.text.trim();
    if (path.isEmpty) {
      setState(() => _error = 'Enter the path to a plugin ZIP file.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final file = File(path);
      if (!await file.exists()) {
        throw const PluginValidationException(
          'The plugin ZIP file was not found.',
        );
      }
      final bytes = await file.readAsBytes();
      final store = ref.read(pluginStoreProvider);
      final installed = await store.list();
      final installedIds = <String>{
        for (final plugin in installed)
          if (plugin.id != widget.updatePluginId) plugin.id,
      };
      final appVersion = await ref.read(hostAppVersionProvider.future);
      final bundle = const PluginBundleValidator().validate(
        bytes,
        installedIds: installedIds,
        hostApiVersion: supportedPluginApiVersion,
        hostAppVersion: appVersion,
      );

      final updateId = widget.updatePluginId;
      if (updateId != null && bundle.manifest.id != updateId) {
        throw PluginValidationException(
          'The ZIP contains plugin "${bundle.manifest.id}" but '
          '"$updateId" was expected.',
        );
      }

      final InstalledPlugin result;
      if (updateId == null) {
        result = await store.install(
          bundle,
          enabled: true,
          source: pluginSourceZip,
        );
      } else {
        final existing = await store.get(updateId);
        result = await store.update(
          bundle,
          enabled: existing?.enabled ?? true,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } on PluginValidationException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Could not read the plugin ZIP: ${error.message}',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not install the plugin: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = widget.updatePluginId != null;
    return AlertDialog(
      title: Text(update ? 'Update plugin' : 'Add plugin'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            key: const ValueKey<String>('plugin-zip-path'),
            controller: _path,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'ZIP file path',
              helperText: 'Enter the full path to a plugin ZIP file.',
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const ValueKey<String>('plugin-install-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('plugin-install-submit'),
          onPressed: _busy ? null : _import,
          child: Text(update ? 'Update' : 'Install'),
        ),
      ],
    );
  }
}
