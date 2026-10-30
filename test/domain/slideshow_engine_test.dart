import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/domain/slideshow/slideshow_engine.dart';

List<ImmichAsset> assets(int count) {
  return List<ImmichAsset>.generate(
    count,
    (index) => ImmichAsset(id: 'asset-$index'),
  );
}

List<String> ids(SlideshowEngine engine) {
  return engine.sequence.map((asset) => asset.id).toList();
}

void main() {
  test('keeps input order when shuffle is off', () {
    final engine = SlideshowEngine(assets(3));

    expect(ids(engine), <String>['asset-0', 'asset-1', 'asset-2']);
    expect(engine.currentIndex, 0);
    expect(engine.current?.id, 'asset-0');
    expect(engine.total, 3);
    expect(engine.hasItems, isTrue);
    expect(engine.shuffle, isFalse);
  });

  test('shuffles deterministically with a seeded random', () {
    final first = SlideshowEngine(assets(8), random: Random(42), shuffle: true);
    final second = SlideshowEngine(assets(8), random: Random(42), shuffle: true);

    expect(ids(first), ids(second));
    expect(ids(first), isNot(ids(SlideshowEngine(assets(8)))));
  });

  test('wraps next and previous', () {
    final engine = SlideshowEngine(assets(3));

    expect(engine.previous(), isTrue);
    expect(engine.currentIndex, 2);
    expect(engine.next(), isTrue);
    expect(engine.currentIndex, 0);
    expect(engine.next(), isTrue);
    expect(engine.currentIndex, 1);
  });

  test('pause freezes ticks until resume', () {
    final engine = SlideshowEngine(assets(2), intervalSeconds: 1);

    engine.pause();
    expect(engine.playing, isFalse);
    expect(engine.tick(const Duration(seconds: 2)), isFalse);
    expect(engine.currentIndex, 0);
    expect(engine.elapsed, Duration.zero);

    engine.resume();
    expect(engine.tick(const Duration(milliseconds: 500)), isFalse);
    expect(engine.elapsed, const Duration(milliseconds: 500));
  });

  test('auto advances when elapsed reaches the interval', () {
    final engine = SlideshowEngine(assets(3), intervalSeconds: 1);

    expect(engine.tick(const Duration(seconds: 1)), isTrue);
    expect(engine.currentIndex, 1);
    expect(engine.elapsed, Duration.zero);
  });

  test('exposes progress within the current interval', () {
    final engine = SlideshowEngine(assets(2), intervalSeconds: 10);

    expect(engine.progress, 0);
    engine.tick(const Duration(seconds: 5));
    expect(engine.progress, closeTo(0.5, 0.0001));
    engine.tick(const Duration(seconds: 5));
    expect(engine.progress, 0);
    expect(engine.currentIndex, 1);
  });

  test('handles an empty asset list', () {
    final engine = SlideshowEngine(const <ImmichAsset>[]);

    expect(engine.current, isNull);
    expect(engine.hasItems, isFalse);
    expect(engine.total, 0);
    expect(engine.progress, 0);
    expect(engine.next(), isFalse);
    expect(engine.previous(), isFalse);
    expect(engine.tick(const Duration(seconds: 5)), isFalse);
  });

  test('setShuffle preserves the current asset', () {
    final engine = SlideshowEngine(assets(6), random: Random(3));
    engine
      ..next()
      ..next();
    final currentId = engine.current!.id;

    engine.setShuffle(true);
    expect(engine.shuffle, isTrue);
    expect(engine.current?.id, currentId);

    engine.setShuffle(false);
    expect(ids(engine), <String>[
      'asset-0',
      'asset-1',
      'asset-2',
      'asset-3',
      'asset-4',
      'asset-5',
    ]);
    expect(engine.current?.id, currentId);
  });

  test('setInterval clamps and controls auto advance', () {
    final engine = SlideshowEngine(assets(2), intervalSeconds: 10);

    engine.setInterval(2);
    expect(engine.intervalSeconds, 2);
    expect(engine.tick(const Duration(seconds: 2)), isTrue);

    engine.setInterval(0);
    expect(engine.intervalSeconds, 1);

    engine.setInterval(9999);
    expect(engine.intervalSeconds, 3600);
  });

  test('setCurrentDuration controls progress and the advance point', () {
    final engine = SlideshowEngine(assets(2), intervalSeconds: 10);

    engine.setCurrentDuration(const Duration(seconds: 4));
    expect(engine.currentDuration, const Duration(seconds: 4));
    expect(engine.progress, 0);

    expect(engine.tick(const Duration(seconds: 2)), isFalse);
    expect(engine.progress, closeTo(0.5, 0.0001));

    expect(engine.tick(const Duration(seconds: 2)), isTrue);
    expect(engine.currentIndex, 1);
    expect(engine.currentDuration, isNull);
  });

  test('setCurrentDuration treats zero as null', () {
    final engine = SlideshowEngine(assets(2), intervalSeconds: 10);

    engine.setCurrentDuration(const Duration(seconds: 3));
    expect(engine.currentDuration, const Duration(seconds: 3));

    engine.setCurrentDuration(Duration.zero);
    expect(engine.currentDuration, isNull);

    engine.tick(const Duration(seconds: 5));
    expect(engine.progress, closeTo(0.5, 0.0001));
  });

  test('reset returns to the first asset and clears elapsed', () {
    final engine = SlideshowEngine(assets(3), intervalSeconds: 10);
    engine
      ..next()
      ..tick(const Duration(seconds: 4))
      ..pause();

    engine.reset();

    expect(engine.currentIndex, 0);
    expect(engine.elapsed, Duration.zero);
    expect(engine.playing, isTrue);
  });
}
