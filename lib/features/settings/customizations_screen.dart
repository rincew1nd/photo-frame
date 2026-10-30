import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/features/settings/settings_scaffold.dart';

/// Lists customization profiles and opens the embedded editor.
class CustomizationsScreen extends ConsumerWidget {
  const CustomizationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettings = ref.watch(settingsControllerProvider);
    return SettingsScaffold(
      title: 'Customizations',
      body: asyncSettings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Unable to load settings')),
        data: (settings) => _body(context, ref, settings),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, AppSettings settings) {
    final profiles = settings.customizations;
    return ListView(
      children: <Widget>[
        if (profiles.isEmpty)
          const ListTile(
            leading: Icon(Icons.tune),
            title: Text('No customizations yet'),
            subtitle: Text('Matching media uses the Slideshow defaults.'),
          )
        else
          for (var index = 0; index < profiles.length; index++)
            _profileTile(context, ref, settings, index: index),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            key: const ValueKey<String>('customization-add'),
            onPressed: () => _add(context, ref, settings),
            icon: const Icon(Icons.add),
            label: const Text('Add customization'),
          ),
        ),
      ],
    );
  }

  Widget _profileTile(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings, {
    required int index,
  }) {
    final profile = settings.customizations[index];
    final name = profile.name.isEmpty ? 'Customization' : profile.name;
    return ListTile(
      key: ValueKey<String>('customization-profile-${profile.id}'),
      title: Text(name),
      subtitle: Text(_summary(profile)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            key: ValueKey<String>('customization-up-${profile.id}'),
            tooltip: 'Move up',
            icon: const Icon(Icons.arrow_upward),
            onPressed: index == 0
                ? null
                : () => _move(ref, settings, index, index - 1),
          ),
          IconButton(
            key: ValueKey<String>('customization-down-${profile.id}'),
            tooltip: 'Move down',
            icon: const Icon(Icons.arrow_downward),
            onPressed: index == settings.customizations.length - 1
                ? null
                : () => _move(ref, settings, index, index + 1),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () =>
          context.push('/settings/slideshow/customizations/${profile.id}'),
    );
  }

  void _move(WidgetRef ref, AppSettings settings, int from, int to) {
    final profiles = List<CustomizationProfile>.of(settings.customizations);
    final moved = profiles.removeAt(from);
    profiles.insert(to, moved);
    ref
        .read(settingsControllerProvider.notifier)
        .save((current) => current.copyWith(customizations: profiles));
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final profile = CustomizationProfile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: 'Customization ${settings.customizations.length + 1}',
      profile: settings.defaultProfile,
    );
    await ref
        .read(settingsControllerProvider.notifier)
        .save(
          (current) => current.copyWith(
            customizations: <CustomizationProfile>[
              ...current.customizations,
              profile,
            ],
          ),
        );
    if (!context.mounted) {
      return;
    }
    await context.push('/settings/slideshow/customizations/${profile.id}');
  }

  String _summary(CustomizationProfile profile) {
    final aspects = profile.aspects.isEmpty
        ? 'Any aspect'
        : profile.aspects.map((aspect) => aspect.label).join(', ');
    final media = profile.mediaTypes.isEmpty
        ? 'Any media'
        : profile.mediaTypes.map(mediaKindLabel).join(', ');
    final overrides = <String>[
      settingsLabel(profile.profile.fit.name),
      if (profile.profile.adaptiveBackground != AdaptiveBackground.none)
        settingsLabel(profile.profile.adaptiveBackground.name),
      if (profile.profile.fit == ImageFit.cover && !profile.profile.imageMotion)
        'No motion',
      if (profile.profile.fit == ImageFit.cover &&
          profile.profile.panStrength > 0)
        'Pan ${profile.profile.panStrength}',
    ];
    return <String>[aspects, media, ...overrides].join(' · ');
  }
}

/// Edits a single customization profile that resolves slideshow options.
class CustomizationEditorScreen extends ConsumerStatefulWidget {
  const CustomizationEditorScreen({super.key, this.customizationId});

  final String? customizationId;

  @override
  ConsumerState<CustomizationEditorScreen> createState() =>
      _CustomizationEditorScreenState();
}

class _CustomizationEditorScreenState
    extends ConsumerState<CustomizationEditorScreen> {
  TextEditingController? _nameController;

  @override
  void didUpdateWidget(CustomizationEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customizationId != widget.customizationId) {
      _nameController?.dispose();
      _nameController = null;
    }
  }

  @override
  void dispose() {
    _nameController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncSettings = ref.watch(settingsControllerProvider);
    return asyncSettings.when(
      loading: () => const SettingsScaffold(
        title: 'Customization',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => const SettingsScaffold(
        title: 'Customization',
        body: Center(child: Text('Unable to load settings')),
      ),
      data: (settings) {
        final profile = _findProfile(settings);
        if (profile == null) {
          return const SettingsScaffold(
            title: 'Customization',
            body: Center(child: Text('Customization not found')),
          );
        }
        _nameController ??= TextEditingController(text: profile.name);
        return SettingsScaffold(
          title: profile.name.isEmpty ? 'Customization' : profile.name,
          body: _body(context, profile),
        );
      },
    );
  }

  Widget _body(BuildContext context, CustomizationProfile profile) {
    return ListView(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            key: const ValueKey<String>('customization-name'),
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (value) => _update((item) => item.copyWith(name: value)),
          ),
        ),
        const SettingsSectionHeader('Matches'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final aspect in AspectBucket.values)
                FilterChip(
                  key: ValueKey<String>('customization-aspect-${aspect.name}'),
                  label: Text(aspect.label),
                  selected: profile.aspects.contains(aspect),
                  onSelected: (selected) {
                    final next = <AspectBucket>{...profile.aspects};
                    if (selected) {
                      next.add(aspect);
                    } else {
                      next.remove(aspect);
                    }
                    _update((item) => item.copyWith(aspects: next));
                  },
                ),
            ],
          ),
        ),
        _helperText(context, 'No selection means any aspect ratio.'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final kind in MediaKind.values)
                FilterChip(
                  key: ValueKey<String>('customization-media-${kind.name}'),
                  label: Text(mediaKindLabel(kind)),
                  selected: profile.mediaTypes.contains(kind),
                  onSelected: (selected) {
                    final next = <MediaKind>{...profile.mediaTypes};
                    if (selected) {
                      next.add(kind);
                    } else {
                      next.remove(kind);
                    }
                    _update((item) => item.copyWith(mediaTypes: next));
                  },
                ),
            ],
          ),
        ),
        _helperText(context, 'No selection means any media type.'),
        const SettingsSectionHeader('Slideshow options'),
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
              selected: <ImageFit>{profile.profile.fit},
              onSelectionChanged: (selection) => _update(
                (item) => item.copyWith(
                  profile: item.profile.copyWith(fit: selection.first),
                ),
              ),
            ),
          ),
        ),
        const ListTile(title: Text('Adaptive background')),
        RadioGroup<AdaptiveBackground>(
          groupValue: profile.profile.adaptiveBackground,
          onChanged: (value) {
            if (value != null) {
              _update(
                (item) => item.copyWith(
                  profile: item.profile.copyWith(adaptiveBackground: value),
                ),
              );
            }
          },
          child: Column(
            children: <Widget>[
              for (final background in AdaptiveBackground.values)
                RadioListTile<AdaptiveBackground>(
                  key: ValueKey<String>(
                    'customization-background-${background.name}',
                  ),
                  value: background,
                  title: Text(settingsLabel(background.name)),
                ),
            ],
          ),
        ),
        SwitchListTile(
          key: const ValueKey<String>('customization-image-motion'),
          title: const Text('Image motion'),
          subtitle: Text(
            profile.profile.fit == ImageFit.contain
                ? 'Available with Cover.'
                : 'Slow pan and zoom.',
          ),
          value: profile.profile.imageMotion,
          onChanged: profile.profile.fit == ImageFit.contain
              ? null
              : (value) => _update(
                  (item) => item.copyWith(
                    profile: item.profile.copyWith(imageMotion: value),
                  ),
                ),
        ),
        ListTile(
          title: const Text('Pan strength'),
          subtitle: Text(
            profile.profile.fit == ImageFit.contain
                ? 'Set Image fit to Cover to use pan.'
                : '${profile.profile.panStrength} · Ken Burns pan',
          ),
        ),
        Slider(
          key: const ValueKey<String>('customization-pan-strength'),
          value: profile.profile.panStrength.toDouble(),
          min: 0,
          max: 100,
          divisions: 100,
          label: '${profile.profile.panStrength}',
          onChanged: profile.profile.fit == ImageFit.contain
              ? null
              : (value) => _update(
                  (item) => item.copyWith(
                    profile: item.profile.copyWith(panStrength: value.round()),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: OutlinedButton.icon(
            key: const ValueKey<String>('customization-delete'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => _confirmDelete(profile),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove customization'),
          ),
        ),
      ],
    );
  }

  CustomizationProfile? _findProfile(AppSettings settings) {
    final id = widget.customizationId;
    for (final profile in settings.customizations) {
      if (profile.id == id) {
        return profile;
      }
    }
    return null;
  }

  void _update(CustomizationProfile Function(CustomizationProfile) update) {
    final id = widget.customizationId;
    ref.read(settingsControllerProvider.notifier).save((current) {
      return current.copyWith(
        customizations: <CustomizationProfile>[
          for (final profile in current.customizations)
            if (profile.id == id) update(profile) else profile,
        ],
      );
    });
  }

  Future<void> _confirmDelete(CustomizationProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove customization?'),
        content: const Text('This customization will be removed.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await ref.read(settingsControllerProvider.notifier).save((current) {
      return current.copyWith(
        customizations: <CustomizationProfile>[
          for (final item in current.customizations)
            if (item.id != profile.id) item,
        ],
      );
    });
    if (!mounted) {
      return;
    }
    context.pop();
  }

  Widget _helperText(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
