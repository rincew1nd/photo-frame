import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/settings/app_settings.dart';
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
    final overlays = settings.overlays;
    final label = overlays.weatherLocationLabel.trim();
    final latitude = overlays.weatherLatitude;
    final longitude = overlays.weatherLongitude;
    final unit = overlays.weatherUnit == 'fahrenheit'
        ? 'fahrenheit'
        : 'celsius';
    return ListView(
      children: <Widget>[
        const SettingsSectionHeader('Built-in overlays'),
        SwitchListTile(
          title: const Text('Clock'),
          value: overlays.clock,
          onChanged: (value) =>
              _save(ref, (overlay) => overlay.copyWith(clock: value)),
        ),
        SwitchListTile(
          title: const Text('Weather'),
          value: overlays.weather,
          onChanged: (value) =>
              _save(ref, (overlay) => overlay.copyWith(weather: value)),
        ),
        ListTile(
          key: const ValueKey<String>('weather-location'),
          title: const Text('Location'),
          subtitle: Text(label.isEmpty ? 'Not set' : label),
          onTap: () => _editLocation(context, ref, label),
        ),
        ListTile(
          key: const ValueKey<String>('weather-latitude'),
          title: const Text('Latitude'),
          subtitle: Text(latitude == null ? 'Not set' : '$latitude'),
          onTap: () => _editCoordinate(
            context,
            ref,
            title: 'Weather latitude',
            current: latitude,
            min: -90,
            max: 90,
            save: (overlay, value) => overlay.copyWith(weatherLatitude: value),
          ),
        ),
        ListTile(
          key: const ValueKey<String>('weather-longitude'),
          title: const Text('Longitude'),
          subtitle: Text(longitude == null ? 'Not set' : '$longitude'),
          onTap: () => _editCoordinate(
            context,
            ref,
            title: 'Weather longitude',
            current: longitude,
            min: -180,
            max: 180,
            save: (overlay, value) => overlay.copyWith(weatherLongitude: value),
          ),
        ),
        ListTile(
          title: const Text('Unit'),
          trailing: DropdownButton<String>(
            value: unit,
            onChanged: (value) {
              if (value != null) {
                _save(ref, (overlay) => overlay.copyWith(weatherUnit: value));
              }
            },
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: 'celsius',
                child: Text('Celsius'),
              ),
              DropdownMenuItem<String>(
                value: 'fahrenheit',
                child: Text('Fahrenheit'),
              ),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('Metadata'),
          value: overlays.metadata,
          onChanged: (value) =>
              _save(ref, (overlay) => overlay.copyWith(metadata: value)),
        ),
        const SettingsSectionHeader('Installed plugins'),
        const ListTile(
          leading: Icon(Icons.extension),
          title: Text('No plugins installed'),
          subtitle: Text('Plugin support arrives in Phase 4.'),
        ),
        const ListTile(
          enabled: false,
          leading: Icon(Icons.upload_file),
          title: Text('Add plugin'),
          subtitle: Text("Plugin system isn't available yet."),
        ),
      ],
    );
  }

  void _save(WidgetRef ref, OverlaySettings Function(OverlaySettings) update) {
    ref
        .read(settingsControllerProvider.notifier)
        .save(
          (current) => current.copyWith(overlays: update(current.overlays)),
        );
  }

  Future<void> _editLocation(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final text = await _promptText(
      context,
      title: 'Weather location',
      initialValue: current,
    );
    if (text == null || !context.mounted) {
      return;
    }
    _save(ref, (overlay) => overlay.copyWith(weatherLocationLabel: text));
  }

  Future<void> _editCoordinate(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required double? current,
    required double min,
    required double max,
    required OverlaySettings Function(OverlaySettings, double) save,
  }) async {
    final text = await _promptText(
      context,
      title: title,
      initialValue: current == null ? '' : '$current',
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
    );
    if (text == null || !context.mounted) {
      return;
    }
    final value = double.tryParse(text.trim());
    if (value == null || value < min || value > max) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enter a value between $min and $max')),
      );
      return;
    }
    _save(ref, (overlay) => save(overlay, value));
  }

  Future<String?> _promptText(
    BuildContext context, {
    required String title,
    required String initialValue,
    TextInputType? keyboardType,
  }) {
    var value = initialValue;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initialValue,
          autofocus: true,
          keyboardType: keyboardType,
          onChanged: (text) => value = text,
          onFieldSubmitted: (text) => Navigator.of(dialogContext).pop(text),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(value),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
