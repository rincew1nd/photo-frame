import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/features/settings/settings_scaffold.dart';

class SlideshowSettingsScreen extends ConsumerWidget {
  const SlideshowSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettings = ref.watch(settingsControllerProvider);
    return SettingsScaffold(
      title: 'Slideshow',
      body: asyncSettings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Unable to load settings')),
        data: (settings) => _body(context, ref, settings),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, AppSettings settings) {
    final profile = settings.defaultProfile;
    return ListView(
      children: <Widget>[
        ListTile(
          title: const Text('Image fit'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SegmentedButton<ImageFit>(
              segments: <ButtonSegment<ImageFit>>[
                for (final fit in ImageFit.values)
                  ButtonSegment<ImageFit>(
                    value: fit,
                    label: Text(settingsLabel(fit.name)),
                  ),
              ],
              selected: <ImageFit>{profile.fit},
              onSelectionChanged: (selection) => _save(
                ref,
                (profile) => profile.copyWith(fit: selection.first),
              ),
            ),
          ),
        ),
        const SettingsSectionHeader('Adaptive background'),
        RadioGroup<AdaptiveBackground>(
          groupValue: profile.adaptiveBackground,
          onChanged: (value) {
            if (value != null) {
              _save(
                ref,
                (profile) => profile.copyWith(adaptiveBackground: value),
              );
            }
          },
          child: Column(
            children: <Widget>[
              for (final background in AdaptiveBackground.values)
                RadioListTile<AdaptiveBackground>(
                  value: background,
                  title: Text(settingsLabel(background.name)),
                  subtitle: _backgroundSubtitle(background),
                ),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('Image motion'),
          subtitle: Text(
            profile.fit == ImageFit.contain
                ? 'Available with Cover.'
                : 'Slow pan and zoom.',
          ),
          value: profile.imageMotion,
          onChanged: profile.fit == ImageFit.contain
              ? null
              : (value) => _save(
                  ref,
                  (profile) => profile.copyWith(imageMotion: value),
                ),
        ),
        ListTile(
          title: const Text('Pan strength'),
          subtitle: Text(
            profile.fit == ImageFit.contain
                ? 'Set Image fit to Cover to use pan.'
                : '${profile.panStrength} · Ken Burns pan',
          ),
        ),
        Slider(
          value: profile.panStrength.toDouble(),
          min: 0,
          max: 100,
          divisions: 100,
          label: '${profile.panStrength}',
          onChanged: profile.fit == ImageFit.contain
              ? null
              : (value) => _save(
                  ref,
                  (profile) => profile.copyWith(panStrength: value.round()),
                ),
        ),
        ListTile(
          title: const Text('Customizations'),
          subtitle: Text('${settings.customizations.length} profiles'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/slideshow/customizations'),
        ),
      ],
    );
  }

  void _save(WidgetRef ref, AspectProfile Function(AspectProfile) update) {
    ref
        .read(settingsControllerProvider.notifier)
        .save(
          (current) =>
              current.copyWith(defaultProfile: update(current.defaultProfile)),
        );
  }

  Widget? _backgroundSubtitle(AdaptiveBackground background) {
    return switch (background) {
      AdaptiveBackground.ambientGlow => const Text(
        'Blurred photo glow behind the image',
      ),
      AdaptiveBackground.blurredCover => const Text(
        'Blurred fill behind contained images',
      ),
      AdaptiveBackground.none => null,
    };
  }
}
