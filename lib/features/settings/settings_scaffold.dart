import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/settings/app_settings.dart';

class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.body,
    this.onBack,
    this.actions = const <Widget>[],
  });

  final String title;
  final Widget body;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed:
              onBack ??
              () => context.canPop() ? context.pop() : context.go('/settings'),
        ),
        title: Text(title),
        actions: <Widget>[const SettingsThemeButton(), ...actions],
      ),
      body: body,
    );
  }
}

class SettingsThemeButton extends ConsumerWidget {
  const SettingsThemeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider).value;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: dark ? 'Switch to light theme' : 'Switch to dark theme',
      icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
      onPressed: settings == null
          ? null
          : () => ref
                .read(settingsControllerProvider.notifier)
                .save(
                  (current) => current.copyWith(
                    display: current.display.copyWith(
                      theme: dark ? 'light' : 'dark',
                    ),
                  ),
                ),
    );
  }
}

class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

String settingsLabel(String value) {
  final spaced = value.replaceAllMapped(
    RegExp('[A-Z]'),
    (match) => ' ${match[0]!.toLowerCase()}',
  );
  return spaced.isEmpty
      ? spaced
      : spaced[0].toUpperCase() + spaced.substring(1);
}

/// Human-readable label for a [MediaKind].
String mediaKindLabel(MediaKind kind) {
  return switch (kind) {
    MediaKind.photo => 'Photos',
    MediaKind.livePhoto => 'Live Photos',
    MediaKind.video => 'Videos',
  };
}
