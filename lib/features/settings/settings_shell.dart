import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/features/settings/settings_scaffold.dart';
import 'package:photoframe/l10n/app_localizations.dart';

class SettingsShell extends ConsumerWidget {
  const SettingsShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final asyncSettings = ref.watch(settingsControllerProvider);
    return SettingsScaffold(
      title: l.settings,
      onBack: () => _leave(context, ref),
      body: asyncSettings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Unable to load settings')),
        data: (settings) => _body(context, ref, settings),
      ),
    );
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    await ref.read(settingsControllerProvider.notifier).flush();
    if (!context.mounted) {
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    final settings = ref.read(settingsControllerProvider).value;
    final connection = settings?.connection;
    if (connection != null &&
        (connection.serverUrl ?? '').trim().isNotEmpty &&
        connection.albumIds.isNotEmpty) {
      context.go('/slideshow');
    } else {
      SystemNavigator.pop();
    }
  }

  Widget _body(BuildContext context, WidgetRef ref, AppSettings settings) {
    final connection = settings.connection;
    final cache = settings.cache;
    final quotaGb = (cache.quotaBytes / (1024 * 1024 * 1024)).round();
    final playback = settings.playback;
    final profile = settings.defaultProfile;
    final panSummary =
        profile.fit == ImageFit.cover &&
            profile.imageMotion &&
            profile.panStrength > 0
        ? ' · Pan ${profile.panStrength}'
        : '';
    final overlays = settings.overlays;
    final overlayCount = <bool>[
      overlays.clock,
      overlays.weather,
      overlays.metadata,
    ].where((enabled) => enabled).length;
    final automation = settings.automation;
    final night = settings.nightMode;
    final mediaCount = settings.filters.selectedAssetIds.length;
    final serverConfigured = (connection.serverUrl ?? '').trim().isNotEmpty;
    return ListView(
      children: <Widget>[
        const SettingsSectionHeader('Media'),
        _row(
          title: 'Albums',
          subtitle: serverConfigured
              ? '${connection.albumIds.length} selected'
              : 'Not configured',
          onTap: () => context.push('/albums'),
        ),
        _row(
          title: 'Select media',
          subtitle: mediaCount == 0 ? 'All media' : '$mediaCount selected',
          onTap: () => context.push('/media-selection'),
        ),
        _row(
          title: 'Cache',
          subtitle: '$quotaGb GB limit · prefetch ${cache.prefetchCount}',
          onTap: () => context.push('/settings/cache'),
        ),
        const SettingsSectionHeader('Playback'),
        _row(
          title: 'Playback',
          subtitle:
              '${playback.intervalSeconds}s · '
              '${playback.shuffle ? 'Shuffle' : 'In order'} · '
              '${settingsLabel(playback.transition.name)} · '
              '${settingsLabel(playback.videoPlaybackMode.name)}',
          onTap: () => context.push('/settings/playback'),
        ),
        const SettingsSectionHeader('Slideshow'),
        _row(
          title: 'Slideshow',
          subtitle:
              '${settingsLabel(profile.fit.name)} · '
              '${settingsLabel(profile.adaptiveBackground.name)}'
              '$panSummary',
          onTap: () => context.push('/settings/slideshow'),
        ),
        const SettingsSectionHeader('Plugins'),
        _row(
          title: 'Plugins',
          subtitle:
              '$overlayCount built-in '
              '${overlayCount == 1 ? 'overlay' : 'overlays'} · 0 plugins',
          onTap: () => context.push('/settings/plugins'),
        ),
        const SettingsSectionHeader('Automation'),
        _row(
          title: 'Automation',
          subtitle:
              '${automation.fullscreen ? 'Fullscreen' : 'Windowed'} · '
              '${settings.display.keepScreenOn ? 'Keep awake' : 'Screen may sleep'} · '
              '${night.enabled ? 'Night mode on' : 'Night mode off'}',
          onTap: () => context.push('/settings/automation'),
        ),
        const SettingsSectionHeader('Connection'),
        _row(
          title: 'Connection',
          subtitle: _connectionSummary(connection),
          onTap: () => context.push('/settings/connection'),
        ),
        const SettingsSectionHeader('Appearance'),
        SwitchListTile(
          title: const Text('Follow system theme'),
          value: settings.display.theme == 'system',
          onChanged: (value) {
            final theme = value
                ? 'system'
                : Theme.of(context).brightness == Brightness.dark
                ? 'dark'
                : 'light';
            ref
                .read(settingsControllerProvider.notifier)
                .save(
                  (current) => current.copyWith(
                    display: current.display.copyWith(theme: theme),
                  ),
                );
          },
        ),
        const SettingsSectionHeader('About'),
        _row(
          title: 'About & diagnostics',
          subtitle: 'Version, build & logs',
          onTap: () => context.push('/settings/about'),
        ),
      ],
    );
  }
}

Widget _row({
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return ListTile(
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

String _connectionSummary(ConnectionSettings connection) {
  final serverUrl = (connection.serverUrl ?? '').trim();
  if (serverUrl.isEmpty) {
    return 'Not configured';
  }
  final host = _serverHost(serverUrl);
  final name = (connection.userName ?? '').trim();
  final email = (connection.userEmail ?? '').trim();
  final user = name.isNotEmpty
      ? name
      : email.isNotEmpty
      ? email
      : 'Unknown user';
  final connected = connection.permissions.isNotEmpty;
  return '$host · $user · ${connected ? 'Connected' : 'Not connected'}';
}

String _serverHost(String url) {
  final uri = Uri.tryParse(url);
  if (uri != null && uri.host.isNotEmpty) {
    return uri.host;
  }
  return url.replaceFirst(RegExp(r'/api/?$'), '');
}
