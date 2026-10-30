import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/features/settings/settings_scaffold.dart';

class AutomationSettingsScreen extends ConsumerWidget {
  const AutomationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettings = ref.watch(settingsControllerProvider);
    return SettingsScaffold(
      title: 'Automation',
      body: asyncSettings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Unable to load settings')),
        data: (settings) => _body(context, ref, settings),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, AppSettings settings) {
    final automation = settings.automation;
    final night = settings.nightMode;
    return ListView(
      children: <Widget>[
        SwitchListTile(
          title: const Text('Start on boot'),
          subtitle: const Text('Not available yet.'),
          value: automation.startOnBoot,
          onChanged: null,
        ),
        SwitchListTile(
          title: const Text('Fullscreen'),
          value: automation.fullscreen,
          onChanged: (value) => _save(
            ref,
            (current) => current.copyWith(
              automation: current.automation.copyWith(fullscreen: value),
            ),
          ),
        ),
        SwitchListTile(
          title: const Text('Keep screen on'),
          value: settings.display.keepScreenOn,
          onChanged: (value) => _save(
            ref,
            (current) => current.copyWith(
              display: current.display.copyWith(keepScreenOn: value),
            ),
          ),
        ),
        const SettingsSectionHeader('Night mode'),
        SwitchListTile(
          key: const ValueKey<String>('night-mode-enabled'),
          title: const Text('Enable night mode'),
          value: night.enabled,
          onChanged: (value) => _saveNight(
            ref,
            (night) => night.copyWith(enabled: value),
          ),
        ),
        ListTile(
          title: const Text('Start time'),
          trailing: Text(_formatMinutes(night.startMinutes)),
          onTap: () => _pickTime(context, ref, start: true),
        ),
        ListTile(
          title: const Text('End time'),
          trailing: Text(_formatMinutes(night.endMinutes)),
          onTap: () => _pickTime(context, ref, start: false),
        ),
        ListTile(
          title: const Text('Dim screen'),
          subtitle: Text('${(night.dimOpacity * 100).round()}%'),
        ),
        Slider(
          value: night.dimOpacity.clamp(0.2, 1).toDouble(),
          min: 0.2,
          max: 1,
          divisions: 8,
          label: '${(night.dimOpacity * 100).round()}%',
          onChanged: (value) => _saveNight(
            ref,
            (night) => night.copyWith(dimOpacity: value),
          ),
        ),
        SwitchListTile(
          title: const Text('Pause slideshow'),
          value: night.pauseSlideshow,
          onChanged: (value) => _saveNight(
            ref,
            (night) => night.copyWith(pauseSlideshow: value),
          ),
        ),
        SwitchListTile(
          title: const Text('Hide overlays'),
          value: night.hideOverlays,
          onChanged: (value) => _saveNight(
            ref,
            (night) => night.copyWith(hideOverlays: value),
          ),
        ),
        if (night.startMinutes > night.endMinutes)
          const ListTile(
            dense: true,
            leading: Icon(Icons.nights_stay),
            title: Text('Overnight window'),
          ),
      ],
    );
  }

  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref, {
    required bool start,
  }) async {
    final current = ref.read(settingsControllerProvider).value;
    if (current == null) {
      return;
    }
    final minutes = start
        ? current.nightMode.startMinutes
        : current.nightMode.endMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked == null || !context.mounted) {
      return;
    }
    final value = picked.hour * 60 + picked.minute;
    _saveNight(
      ref,
      (night) => start
          ? night.copyWith(startMinutes: value)
          : night.copyWith(endMinutes: value),
    );
  }

  void _save(WidgetRef ref, AppSettings Function(AppSettings) update) {
    ref.read(settingsControllerProvider.notifier).save(update);
  }

  void _saveNight(
    WidgetRef ref,
    NightModeSettings Function(NightModeSettings) update,
  ) {
    _save(
      ref,
      (current) => current.copyWith(nightMode: update(current.nightMode)),
    );
  }
}

String _formatMinutes(int minutes) {
  final hours = (minutes ~/ 60).toString().padLeft(2, '0');
  final mins = (minutes % 60).toString().padLeft(2, '0');
  return '$hours:$mins';
}
