import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/media/playback.dart';

void main() {
  group('PlaybackSource', () {
    test('defaults headers to an empty map', () {
      const source = PlaybackSource(uri: 'https://example.com/asset.jpg');

      expect(source.uri, 'https://example.com/asset.jpg');
      expect(source.headers, isEmpty);
    });

    test('exposes provided headers', () {
      const source = PlaybackSource(
        uri: 'https://example.com/asset.mp4',
        headers: <String, String>{'Authorization': 'Bearer token'},
      );

      expect(source.headers, <String, String>{
        'Authorization': 'Bearer token',
      });
    });
  });

  group('PlaybackSnapshot', () {
    test('defaults to idle with no progress', () {
      const snapshot = PlaybackSnapshot();

      expect(snapshot.phase, PlaybackPhase.idle);
      expect(snapshot.position, Duration.zero);
      expect(snapshot.duration, isNull);
      expect(snapshot.error, isNull);
    });

    test('carries playback state', () {
      const snapshot = PlaybackSnapshot(
        phase: PlaybackPhase.playing,
        position: Duration(seconds: 3),
        duration: Duration(seconds: 30),
        error: 'boom',
      );

      expect(snapshot.phase, PlaybackPhase.playing);
      expect(snapshot.position, const Duration(seconds: 3));
      expect(snapshot.duration, const Duration(seconds: 30));
      expect(snapshot.error, 'boom');
    });
  });
}
