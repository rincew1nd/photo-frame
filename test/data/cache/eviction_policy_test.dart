import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/cache/cache_assets.dart';
import 'package:photoframe/data/cache/eviction_policy.dart';

void main() {
  final base = DateTime.utc(2024, 1, 1);

  CachedAsset asset(
    String id, {
    required int sizeBytes,
    required int accessedHour,
    List<String> tags = const <String>[],
    int liveVideoSizeBytes = 0,
    int derivedImageSizeBytes = 0,
  }) {
    final accessed = base.add(Duration(hours: accessedHour));
    return CachedAsset(
      id: id,
      tags: tags,
      sizeBytes: sizeBytes,
      liveVideoSizeBytes: liveVideoSizeBytes,
      derivedImageSizeBytes: derivedImageSizeBytes,
      cachedAt: accessed,
      lastAccessedAt: accessed,
    );
  }

  test('does nothing while under quota', () {
    final selection = EvictionSelection.select(
      assets: <CachedAsset>[
        asset('a', sizeBytes: 50, accessedHour: 1),
        asset('b', sizeBytes: 50, accessedHour: 2),
      ],
      quotaBytes: 200,
      incomingBytes: 0,
      protectedIds: const <String>{},
    );

    expect(selection.evicted, isEmpty);
    expect(selection.freedBytes, 0);
  });

  test('accounts for incoming bytes', () {
    final selection = EvictionSelection.select(
      assets: <CachedAsset>[
        asset('a', sizeBytes: 50, accessedHour: 1),
        asset('b', sizeBytes: 50, accessedHour: 2),
      ],
      quotaBytes: 100,
      incomingBytes: 40,
      protectedIds: const <String>{},
    );

    expect(selection.evicted.map((item) => item.id), <String>['a']);
    expect(selection.freedBytes, 50);
  });

  test('evicts the oldest last accessed assets until it fits', () {
    final selection = EvictionSelection.select(
      assets: <CachedAsset>[
        asset('newest', sizeBytes: 50, accessedHour: 3),
        asset('oldest', sizeBytes: 50, accessedHour: 1),
        asset('middle', sizeBytes: 50, accessedHour: 2),
      ],
      quotaBytes: 100,
      incomingBytes: 0,
      protectedIds: const <String>{},
    );

    expect(selection.evicted.map((item) => item.id), <String>['oldest']);
    expect(selection.freedBytes, 50);
  });

  test('never evicts protected current or next assets', () {
    final selection = EvictionSelection.select(
      assets: <CachedAsset>[
        asset('current', sizeBytes: 50, accessedHour: 1),
        asset('next', sizeBytes: 50, accessedHour: 2),
        asset('older', sizeBytes: 50, accessedHour: 3),
        asset('newer', sizeBytes: 50, accessedHour: 4),
      ],
      quotaBytes: 100,
      incomingBytes: 0,
      protectedIds: const <String>{'current', 'next'},
    );

    expect(selection.evicted.map((item) => item.id), <String>[
      'older',
      'newer',
    ]);
    expect(selection.freedBytes, 100);
  });

  test('evicts by total size including motion and derived bytes', () {
    final selection = EvictionSelection.select(
      assets: <CachedAsset>[
        asset(
          'with-live',
          sizeBytes: 50,
          liveVideoSizeBytes: 900,
          accessedHour: 1,
        ),
        asset(
          'with-derived',
          sizeBytes: 50,
          derivedImageSizeBytes: 1000,
          accessedHour: 2,
        ),
      ],
      quotaBytes: 1200,
      incomingBytes: 0,
      protectedIds: const <String>{},
    );

    expect(selection.evicted.map((item) => item.id), <String>['with-live']);
    expect(selection.freedBytes, 950);
  });

  test('returns only what can be freed when protection is not enough', () {
    final selection = EvictionSelection.select(
      assets: <CachedAsset>[
        asset('current', sizeBytes: 50, accessedHour: 1),
        asset('next', sizeBytes: 50, accessedHour: 2),
      ],
      quotaBytes: 0,
      incomingBytes: 100,
      protectedIds: const <String>{'current', 'next'},
    );

    expect(selection.evicted, isEmpty);
    expect(selection.freedBytes, 0);
  });
}
