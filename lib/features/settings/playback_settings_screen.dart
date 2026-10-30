import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/settings/app_settings.dart';
import 'package:photoframe/features/settings/settings_scaffold.dart';

class PlaybackSettingsScreen extends ConsumerWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettings = ref.watch(settingsControllerProvider);
    return SettingsScaffold(
      title: 'Playback',
      body: asyncSettings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Unable to load settings')),
        data: (settings) => _body(ref, settings),
      ),
    );
  }

  Widget _body(WidgetRef ref, AppSettings settings) {
    final playback = settings.playback;
    return ListView(
      children: <Widget>[
        ListTile(
          title: const Text('Slide interval'),
          subtitle: Text('${playback.intervalSeconds} seconds'),
        ),
        Slider(
          value: playback.intervalSeconds.clamp(5, 300).toDouble(),
          min: 5,
          max: 300,
          divisions: 295,
          label: '${playback.intervalSeconds} seconds',
          onChanged: (value) => _save(
            ref,
            (playback) => playback.copyWith(intervalSeconds: value.round()),
          ),
        ),
        SwitchListTile(
          title: const Text('Shuffle'),
          value: playback.shuffle,
          onChanged: (value) =>
              _save(ref, (playback) => playback.copyWith(shuffle: value)),
        ),
        ListTile(
          title: const Text('Transition'),
          trailing: DropdownButton<TransitionType>(
            value: playback.transition,
            onChanged: (value) {
              if (value != null) {
                _save(ref, (playback) => playback.copyWith(transition: value));
              }
            },
            items: <DropdownMenuItem<TransitionType>>[
              for (final transition in TransitionType.values)
                DropdownMenuItem<TransitionType>(
                  value: transition,
                  child: Text(settingsLabel(transition.name)),
                ),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('Mute video/live audio'),
          subtitle: const Text('Applies to videos and Live Photo motion.'),
          value: playback.muted,
          onChanged: (value) =>
              _save(ref, (playback) => playback.copyWith(muted: value)),
        ),
        const SettingsSectionHeader('Video playback'),
        RadioGroup<VideoPlaybackMode>(
          groupValue: playback.videoPlaybackMode,
          onChanged: (value) {
            if (value != null) {
              _save(
                ref,
                (playback) => playback.copyWith(videoPlaybackMode: value),
              );
            }
          },
          child: Column(
            children: <Widget>[
              for (final mode in VideoPlaybackMode.values)
                RadioListTile<VideoPlaybackMode>(
                  key: ValueKey<String>('video-mode-${mode.name}'),
                  value: mode,
                  title: Text(_videoLabel(mode)),
                  subtitle: Text(_videoSubtitle(mode)),
                  enabled: _videoEnabled(mode),
                ),
            ],
          ),
        ),
        const SettingsSectionHeader('Live Photo playback'),
        RadioGroup<LivePhotoMode>(
          groupValue: playback.livePhotoMode,
          onChanged: (value) {
            if (value != null) {
              _save(ref, (playback) => playback.copyWith(livePhotoMode: value));
            }
          },
          child: Column(
            children: <Widget>[
              for (final mode in LivePhotoMode.values)
                RadioListTile<LivePhotoMode>(
                  key: ValueKey<String>('live-photo-mode-${mode.name}'),
                  value: mode,
                  title: Text(settingsLabel(mode.name)),
                  subtitle: Text(_liveSubtitle(mode)),
                  enabled: mode == LivePhotoMode.off,
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _save(
    WidgetRef ref,
    PlaybackSettings Function(PlaybackSettings) update,
  ) {
    ref
        .read(settingsControllerProvider.notifier)
        .save(
          (current) => current.copyWith(playback: update(current.playback)),
        );
  }

  bool _videoEnabled(VideoPlaybackMode mode) {
    return mode == VideoPlaybackMode.off ||
        mode == VideoPlaybackMode.staticPreview ||
        mode == VideoPlaybackMode.full;
  }

  String _videoLabel(VideoPlaybackMode mode) {
    return mode == VideoPlaybackMode.full
        ? 'Full video'
        : settingsLabel(mode.name);
  }

  String _videoSubtitle(VideoPlaybackMode mode) {
    return switch (mode) {
      VideoPlaybackMode.off => 'Skip videos.',
      VideoPlaybackMode.staticPreview =>
        'Show the thumbnail for the normal interval.',
      VideoPlaybackMode.full => 'Play the original video with audio.',
      _ => 'Not available yet.',
    };
  }

  String _liveSubtitle(LivePhotoMode mode) {
    return mode == LivePhotoMode.off
        ? 'Show as a still photo.'
        : 'Not available yet.';
  }
}
