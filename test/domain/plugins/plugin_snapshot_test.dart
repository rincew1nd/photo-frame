import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';
import 'package:photoframe/domain/plugins/plugin_snapshot.dart';

import '../../data/plugins/plugin_test_support.dart';

PluginManifest _manifest(List<Object?> inputs) {
  return PluginManifest.fromJson(sampleManifest(inputs: inputs));
}

PluginSnapshotSource _source({
  PluginWeatherSnapshot? weather,
  PluginMediaSnapshot? media,
  PluginImageSnapshot? image,
  Map<String, dynamic> config = const <String, dynamic>{
    'format': '24h',
    'showSeconds': true,
  },
  bool enabled = true,
  bool visible = true,
}) {
  return PluginSnapshotSource(
    appVersion: '1.0.0',
    pluginApiVersion: supportedPluginApiVersion,
    locale: 'en-US',
    timeZone: 'Europe/Berlin',
    theme: 'dark',
    viewportWidth: 1920,
    viewportHeight: 1080,
    safeArea: const PluginInsets(top: 10, right: 20, bottom: 30, left: 40),
    nightMode: true,
    now: DateTime.utc(2026, 11, 1, 21, 30, 5),
    weather: weather,
    playback: const PluginPlaybackSnapshot(
      playing: true,
      index: 2,
      total: 10,
      intervalSeconds: 15,
      progress: 0.4,
      muted: false,
      slideshowRunning: true,
    ),
    media: media,
    image: image,
    config: config,
    placement: const PluginPlacement(
      anchor: PluginAnchor.bottomEnd,
      x: 0.75,
      y: 0.8,
      width: 320,
      height: 160,
      zOrder: 3,
      showDuringNight: true,
    ),
    enabled: enabled,
    visible: visible,
  );
}

Map<String, dynamic> _section(Map<String, dynamic> snapshot, String key) {
  return snapshot[key]! as Map<String, dynamic>;
}

void main() {
  group('PluginSnapshotBuilder', () {
    test('always includes app and time, filtered to declared inputs', () {
      final snapshot = PluginSnapshotBuilder.build(
        manifest: _manifest(const <Object?>[]),
        source: _source(),
      );

      expect(snapshot.keys, unorderedEquals(<String>['app', 'time']));
      final app = _section(snapshot, 'app');
      expect(app['version'], '1.0.0');
      expect(app['pluginApiVersion'], supportedPluginApiVersion);
      expect(app['locale'], 'en-US');
      expect(app['timeZone'], 'Europe/Berlin');
      expect(app['theme'], 'dark');
      expect(app['viewport'], <String, double>{'width': 1920, 'height': 1080});
      expect(app['safeArea'], <String, double>{
        'top': 10,
        'right': 20,
        'bottom': 30,
        'left': 40,
      });
      expect(app['nightMode'], isTrue);

      final time = _section(snapshot, 'time');
      expect(time['iso'], '2026-11-01T21:30:05.000Z');
      expect(
        time['epochMs'],
        DateTime.utc(2026, 11, 1, 21, 30, 5).millisecondsSinceEpoch,
      );
      expect(time['year'], 2026);
      expect(time['month'], 11);
      expect(time['day'], 1);
      expect(time['hour'], 21);
      expect(time['minute'], 30);
      expect(time['second'], 5);
      expect(time['weekday'], DateTime.sunday);
    });

    test('declared sections are included and undefined sections omitted', () {
      final snapshot = PluginSnapshotBuilder.build(
        manifest: _manifest(<Object?>[
          'weather',
          'playback',
          'image',
          'config',
          'placement',
        ]),
        source: _source(
          image: const PluginImageSnapshot(id: 'asset-1', type: 'photo'),
        ),
      );

      expect(
        snapshot.keys,
        unorderedEquals(<String>[
          'app',
          'time',
          'weather',
          'playback',
          'image',
          'config',
          'placement',
        ]),
      );
      expect(snapshot['weather'], isNull);

      final playback = _section(snapshot, 'playback');
      expect(playback['playing'], isTrue);
      expect(playback['index'], 2);
      expect(playback['total'], 10);
      expect(playback['intervalSeconds'], 15);
      expect(playback['progress'], 0.4);
      expect(playback['muted'], isFalse);
      expect(playback['slideshowRunning'], isTrue);

      final config = _section(snapshot, 'config');
      expect(config['format'], '24h');
      expect(config['showSeconds'], isTrue);

      final placement = _section(snapshot, 'placement');
      expect(placement['anchor'], 'bottom-end');
      expect(placement['x'], 0.75);
      expect(placement['y'], 0.8);
      expect(placement['width'], 320);
      expect(placement['height'], 160);
      expect(placement['zOrder'], 3);
      expect(placement['showDuringNight'], isTrue);
    });

    test('leaves undeclared source sections out of the snapshot', () {
      final snapshot = PluginSnapshotBuilder.build(
        manifest: _manifest(<Object?>['time']),
        source: _source(
          weather: PluginWeatherSnapshot(
            temperature: 12.5,
            unit: 'celsius',
            code: 3,
            description: 'Overcast',
            locationLabel: 'Berlin',
            fetchedAt: DateTime.utc(2026, 11, 1, 21),
          ),
          image: const PluginImageSnapshot(id: 'asset-1', type: 'photo'),
        ),
      );

      expect(snapshot.keys, unorderedEquals(<String>['app', 'time']));
      expect(snapshot, isNot(contains('weather')));
      expect(snapshot, isNot(contains('media')));
      expect(snapshot, isNot(contains('image')));
      expect(snapshot, isNot(contains('config')));
      expect(snapshot, isNot(contains('placement')));
    });

    test('emits background media only when declared', () {
      const media = PluginMediaSnapshot(
        hasSession: true,
        title: 'Track',
        artist: 'Artist',
        album: 'Album',
        packageName: 'com.spotify.music',
        playing: true,
        canPrevious: true,
        canNext: false,
        positionSeconds: 12.5,
        durationSeconds: 200,
      );

      final declared = PluginSnapshotBuilder.build(
        manifest: _manifest(<Object?>['media']),
        source: _source(media: media),
      );
      final section = _section(declared, 'media');
      expect(
        section.keys,
        unorderedEquals(<String>[
          'hasSession',
          'title',
          'artist',
          'album',
          'packageName',
          'playing',
          'canPrevious',
          'canNext',
          'positionSeconds',
          'durationSeconds',
        ]),
      );
      expect(section['hasSession'], isTrue);
      expect(section['title'], 'Track');
      expect(section['artist'], 'Artist');
      expect(section['album'], 'Album');
      expect(section['packageName'], 'com.spotify.music');
      expect(section['playing'], isTrue);
      expect(section['canPrevious'], isTrue);
      expect(section['canNext'], isFalse);
      expect(section['positionSeconds'], 12.5);
      expect(section['durationSeconds'], 200.0);

      final undeclared = PluginSnapshotBuilder.build(
        manifest: _manifest(<Object?>['playback']),
        source: _source(media: media),
      );
      expect(undeclared, isNot(contains('media')));
    });

    test('a declared media section is null without a session', () {
      final snapshot = PluginSnapshotBuilder.build(
        manifest: _manifest(<Object?>['media']),
        source: _source(),
      );

      expect(snapshot, contains('media'));
      expect(snapshot['media'], isNull);
    });

    test('emits weather when declared and present', () {
      final snapshot = PluginSnapshotBuilder.build(
        manifest: _manifest(<Object?>['weather']),
        source: _source(
          weather: PluginWeatherSnapshot(
            temperature: 12.5,
            unit: 'celsius',
            code: 3,
            description: 'Overcast',
            locationLabel: 'Berlin',
            fetchedAt: DateTime.utc(2026, 11, 1, 21),
          ),
        ),
      );

      final weather = _section(snapshot, 'weather');
      expect(weather['temperature'], 12.5);
      expect(weather['unit'], 'celsius');
      expect(weather['code'], 3);
      expect(weather['description'], 'Overcast');
      expect(weather['locationLabel'], 'Berlin');
      expect(weather['fetchedAt'], '2026-11-01T21:00:00.000Z');
    });

    test('redacts image metadata to the bounded field set', () {
      final snapshot = PluginSnapshotBuilder.build(
        manifest: _manifest(<Object?>['image']),
        source: _source(
          image: PluginImageSnapshot(
            id: 'asset-1',
            type: 'livePhoto',
            livePhoto: true,
            width: 4032,
            height: 3024,
            aspectBucket: 'fourThree',
            aspectLabel: '4:3',
            mimeType: 'image/jpeg',
            cached: true,
            exifDate: DateTime.utc(2024, 6, 1, 12),
            description: 'Beach',
            location: 'Lisbon',
            tags: const <String>['holiday', 'sea'],
          ),
        ),
      );

      final image = _section(snapshot, 'image');
      expect(
        image.keys,
        unorderedEquals(<String>[
          'id',
          'type',
          'livePhoto',
          'width',
          'height',
          'aspectBucket',
          'aspectLabel',
          'mimeType',
          'cached',
          'exifDate',
          'description',
          'location',
          'tags',
        ]),
      );
      expect(image['id'], 'asset-1');
      expect(image['type'], 'livePhoto');
      expect(image['livePhoto'], isTrue);
      expect(image['width'], 4032);
      expect(image['height'], 3024);
      expect(image['aspectBucket'], 'fourThree');
      expect(image['aspectLabel'], '4:3');
      expect(image['mimeType'], 'image/jpeg');
      expect(image['cached'], isTrue);
      expect(image['exifDate'], '2024-06-01T12:00:00.000Z');
      expect(image['description'], 'Beach');
      expect(image['location'], 'Lisbon');
      expect(image['tags'], <String>['holiday', 'sea']);

      for (final forbidden in <String>[
        'albumIds',
        'albums',
        'checksum',
        'originalPath',
        'thumbnailPath',
        'liveVideoPath',
        'derivedImagePath',
        'originalFileName',
        'livePhotoVideoId',
        'sizeBytes',
        'make',
        'model',
        'lensModel',
      ]) {
        expect(image, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('reports enabled and visible state in every snapshot', () {
      final snapshot = PluginSnapshotBuilder.build(
        manifest: _manifest(const <Object?>[]),
        source: _source(enabled: false, visible: false),
      );

      final app = _section(snapshot, 'app');
      expect(app['enabled'], isFalse);
      expect(app['visible'], isFalse);

      final enabled = PluginSnapshotBuilder.build(
        manifest: _manifest(const <Object?>[]),
        source: _source(),
      );
      expect(_section(enabled, 'app')['enabled'], isTrue);
      expect(_section(enabled, 'app')['visible'], isTrue);
    });
  });
}
