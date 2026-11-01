import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/features/settings/settings_scaffold.dart';

class AutomationSettingsScreen extends ConsumerStatefulWidget {
  const AutomationSettingsScreen({super.key});

  @override
  ConsumerState<AutomationSettingsScreen> createState() =>
      _AutomationSettingsScreenState();
}

class _AutomationSettingsScreenState
    extends ConsumerState<AutomationSettingsScreen>
    with WidgetsBindingObserver {
  bool? _batteryIgnored;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBatteryStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadBatteryStatus();
    }
  }

  Future<void> _loadBatteryStatus() async {
    final ignored = await ref
        .read(permissionsServiceProvider)
        .batteryOptimizationIgnored;
    if (!mounted) {
      return;
    }
    setState(() => _batteryIgnored = ignored);
    if (Platform.isAndroid &&
        ignored == false &&
        ref.read(settingsControllerProvider).value?.automation.startOnBoot ==
            true) {
      _save(
        ref,
        (current) => current.copyWith(
          automation: current.automation.copyWith(startOnBoot: false),
        ),
      );
    }
  }

  Future<void> _grantBatteryExemption() async {
    await ref
        .read(permissionsServiceProvider)
        .requestBatteryOptimizationExemption();
    await _loadBatteryStatus();
  }

  @override
  Widget build(BuildContext context) {
    final asyncSettings = ref.watch(settingsControllerProvider);
    return SettingsScaffold(
      title: 'Automation',
      body: asyncSettings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Unable to load settings')),
        data: (settings) => _body(context, settings),
      ),
    );
  }

  Widget _body(BuildContext context, AppSettings settings) {
    final automation = settings.automation;
    final night = settings.nightMode;
    final autostartSupported =
        ref.watch(autostartSupportProvider).value ?? false;
    final batteryExempt = !Platform.isAndroid || _batteryIgnored == true;
    final batteryKnown = !Platform.isAndroid || _batteryIgnored != null;
    final canToggleAutostart =
        autostartSupported &&
        batteryKnown &&
        (batteryExempt || automation.startOnBoot);
    return ListView(
      children: <Widget>[
        SwitchListTile(
          title: const Text('Start on boot'),
          subtitle: Text(
            !autostartSupported
                ? 'Not supported on this device.'
                : Platform.isAndroid && _batteryIgnored != true
                ? 'Battery optimization exemption is required.'
                : 'Starts the slideshow after reboot.',
          ),
          value: automation.startOnBoot,
          onChanged: canToggleAutostart
              ? (value) => _save(
                  ref,
                  (current) => current.copyWith(
                    automation: current.automation.copyWith(startOnBoot: value),
                  ),
                )
              : null,
        ),
        if (Platform.isAndroid) ...[
          ListTile(
            title: const Text('Battery optimization'),
            subtitle: Text(
              _batteryIgnored == null
                  ? 'Checking status.'
                  : _batteryIgnored!
                  ? 'Exempt from battery optimization.'
                  : 'Battery optimization may stop the slideshow.',
            ),
            trailing: _batteryIgnored == true
                ? const Icon(Icons.check)
                : TextButton(
                    onPressed: _grantBatteryExemption,
                    child: const Text('Grant'),
                  ),
          ),
          ListTile(
            title: const Text('OEM autostart'),
            subtitle: const Text(
              'Some manufacturers require a separate autostart permission.',
            ),
            trailing: TextButton(
              onPressed: () =>
                  ref.read(permissionsServiceProvider).openAutostartSettings(),
              child: const Text('Open'),
            ),
          ),
          ListTile(
            title: const Text('Home app'),
            subtitle: const Text(
              'Choose Photo Frame as the home app to start it with the Home button.',
            ),
            trailing: TextButton(
              onPressed: () =>
                  ref.read(permissionsServiceProvider).openHomeSettings(),
              child: const Text('Open'),
            ),
          ),
        ],
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
        if (Platform.isWindows || Platform.isLinux)
          SwitchListTile(
            title: const Text('Kiosk mode'),
            subtitle: const Text(
              'Hides the window controls and keeps the frame on top.',
            ),
            value: automation.kiosk,
            onChanged: (value) => _save(
              ref,
              (current) => current.copyWith(
                automation: current.automation.copyWith(
                  kiosk: value,
                  fullscreen: value ? true : current.automation.fullscreen,
                ),
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
          onChanged: (value) =>
              _saveNight(ref, (night) => night.copyWith(enabled: value)),
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
          onChanged: (value) =>
              _saveNight(ref, (night) => night.copyWith(dimOpacity: value)),
        ),
        SwitchListTile(
          title: const Text('Pause slideshow'),
          value: night.pauseSlideshow,
          onChanged: (value) =>
              _saveNight(ref, (night) => night.copyWith(pauseSlideshow: value)),
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
