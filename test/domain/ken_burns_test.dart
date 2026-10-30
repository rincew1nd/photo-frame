import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/domain/media/ken_burns.dart';

void main() {
  const viewport = 16 / 9;
  const horizontalImage = viewport + 0.5;
  const verticalImage = viewport - 0.5;
  const horizontalHalf = (horizontalImage / viewport - 1) / 2;
  const verticalHalf = (viewport / verticalImage - 1) / 2;

  test('wider images pan horizontally only', () {
    final start = kenBurnsPlan(
      imageAspect: horizontalImage,
      viewportAspect: viewport,
      panStrength: 100,
      progress: 0,
    );
    final middle = kenBurnsPlan(
      imageAspect: horizontalImage,
      viewportAspect: viewport,
      panStrength: 100,
      progress: 0.5,
    );
    final end = kenBurnsPlan(
      imageAspect: horizontalImage,
      viewportAspect: viewport,
      panStrength: 100,
      progress: 1,
    );

    expect(start.motion, PanMotion.horizontal);
    expect(middle.motion, PanMotion.horizontal);
    expect(end.motion, PanMotion.horizontal);
    expect(start.translateY, 0);
    expect(middle.translateY, 0);
    expect(end.translateY, 0);
    expect(start.translateX, closeTo(-horizontalHalf, 1e-9));
    expect(middle.translateX, 0);
    expect(end.translateX, closeTo(horizontalHalf, 1e-9));
    expect(start.scale, 1);
    expect(middle.scale, 1);
    expect(end.scale, 1);
  });

  test('taller images pan vertically only', () {
    final start = kenBurnsPlan(
      imageAspect: verticalImage,
      viewportAspect: viewport,
      panStrength: 100,
      progress: 0,
    );
    final middle = kenBurnsPlan(
      imageAspect: verticalImage,
      viewportAspect: viewport,
      panStrength: 100,
      progress: 0.5,
    );
    final end = kenBurnsPlan(
      imageAspect: verticalImage,
      viewportAspect: viewport,
      panStrength: 100,
      progress: 1,
    );

    expect(start.motion, PanMotion.vertical);
    expect(end.motion, PanMotion.vertical);
    expect(start.translateX, 0);
    expect(end.translateX, 0);
    expect(start.translateY, closeTo(-verticalHalf, 1e-9));
    expect(middle.translateY, 0);
    expect(end.translateY, closeTo(verticalHalf, 1e-9));
    expect(start.scale, 1);
  });

  test('three-to-one image in sixteen-nine uses full overflow half range', () {
    const image = 3.0;
    final start = kenBurnsPlan(
      imageAspect: image,
      viewportAspect: viewport,
      panStrength: 100,
      progress: 0,
    );
    final end = kenBurnsPlan(
      imageAspect: image,
      viewportAspect: viewport,
      panStrength: 100,
      progress: 1,
    );

    expect(start.translateX, closeTo(-0.34375, 1e-9));
    expect(end.translateX, closeTo(0.34375, 1e-9));
    expect(start.scale, 1);
    expect(end.scale, 1);
  });

  test('matching aspects zoom without translation', () {
    final start = kenBurnsPlan(
      imageAspect: viewport,
      viewportAspect: viewport,
      panStrength: 100,
      progress: 0,
    );
    final middle = kenBurnsPlan(
      imageAspect: viewport,
      viewportAspect: viewport,
      panStrength: 100,
      progress: 0.5,
    );
    final end = kenBurnsPlan(
      imageAspect: viewport,
      viewportAspect: viewport,
      panStrength: 100,
      progress: 1,
    );

    expect(start.motion, PanMotion.zoom);
    expect(middle.motion, PanMotion.zoom);
    expect(end.motion, PanMotion.zoom);
    expect(start.translateX, 0);
    expect(start.translateY, 0);
    expect(end.translateX, 0);
    expect(end.translateY, 0);
    expect(start.scale, closeTo(1.0, 1e-9));
    expect(middle.scale, closeTo(1.2, 1e-9));
    expect(end.scale, closeTo(1.0, 1e-9));
  });

  test('tolerance boundaries count as zoom', () {
    const view = 1.5;
    const edge = 0.125;
    final below = kenBurnsPlan(
      imageAspect: view - edge,
      viewportAspect: view,
      panStrength: 100,
      progress: 0.5,
      tolerance: edge,
    );
    final above = kenBurnsPlan(
      imageAspect: view + edge,
      viewportAspect: view,
      panStrength: 100,
      progress: 0.5,
      tolerance: edge,
    );
    final outside = kenBurnsPlan(
      imageAspect: view + edge + 0.001,
      viewportAspect: view,
      panStrength: 100,
      progress: 0.5,
      tolerance: edge,
    );

    expect(below.motion, PanMotion.zoom);
    expect(above.motion, PanMotion.zoom);
    expect(outside.motion, PanMotion.horizontal);
  });

  test('zero pan strength stays static', () {
    for (final aspect in <double>[viewport - 0.5, viewport, viewport + 0.5]) {
      final plan = kenBurnsPlan(
        imageAspect: aspect,
        viewportAspect: viewport,
        panStrength: 0,
        progress: 0.7,
      );
      expect(plan.scale, 1);
      expect(plan.translateX, 0);
      expect(plan.translateY, 0);
    }
  });

  test('invalid dimensions and progress stay bounded', () {
    final inputs = <List<double>>[
      <double>[0, viewport],
      <double>[-1, viewport],
      <double>[double.nan, viewport],
      <double>[double.infinity, viewport],
      <double>[viewport, 0],
      <double>[viewport, double.nan],
      <double>[viewport, double.infinity],
    ];
    for (final input in inputs) {
      final plan = kenBurnsPlan(
        imageAspect: input[0],
        viewportAspect: input[1],
        panStrength: 100,
        progress: 0.5,
      );
      expect(plan.scale, 1);
      expect(plan.translateX, 0);
      expect(plan.translateY, 0);
    }

    final low = kenBurnsPlan(
      imageAspect: horizontalImage,
      viewportAspect: viewport,
      panStrength: 100,
      progress: -3,
    );
    final high = kenBurnsPlan(
      imageAspect: horizontalImage,
      viewportAspect: viewport,
      panStrength: 100,
      progress: 9,
    );
    expect(low.translateX, closeTo(-horizontalHalf, 1e-9));
    expect(high.translateX, closeTo(horizontalHalf, 1e-9));
  });

  test('pan strength scales intensity and clamps above 100', () {
    final half = kenBurnsPlan(
      imageAspect: horizontalImage,
      viewportAspect: viewport,
      panStrength: 50,
      progress: 1,
    );
    final over = kenBurnsPlan(
      imageAspect: horizontalImage,
      viewportAspect: viewport,
      panStrength: 250,
      progress: 1,
    );

    expect(half.translateX, closeTo(horizontalHalf / 2, 1e-9));
    expect(over.translateX, closeTo(horizontalHalf, 1e-9));
    expect(over.scale, 1);
  });

  test('frame size for a wide image uses the full cover width', () {
    final frame = frameSizeFor(
      imageAspect: 3,
      viewportWidth: 1600,
      viewportHeight: 900,
      motion: PanMotion.horizontal,
    );

    expect(frame.displayWidth, closeTo(2700, 1e-9));
    expect(frame.displayHeight, 900);
    expect(frame.maxX, closeTo((2700 - 1600) / 2, 1e-9));
    expect(frame.maxY, 0);
  });

  test('frame size for a tall image uses the full cover height', () {
    final frame = frameSizeFor(
      imageAspect: 0.5,
      viewportWidth: 1600,
      viewportHeight: 900,
      motion: PanMotion.vertical,
    );

    expect(frame.displayWidth, 1600);
    expect(frame.displayHeight, closeTo(3200, 1e-9));
    expect(frame.maxX, 0);
    expect(frame.maxY, closeTo((3200 - 900) / 2, 1e-9));
  });

  test('frame size for zoom stays viewport sized', () {
    final frame = frameSizeFor(
      imageAspect: 3,
      viewportWidth: 1600,
      viewportHeight: 900,
      motion: PanMotion.zoom,
    );

    expect(frame.displayWidth, 1600);
    expect(frame.displayHeight, 900);
    expect(frame.maxX, 0);
    expect(frame.maxY, 0);
  });

  test('frame size falls back to the viewport for an invalid aspect', () {
    for (final aspect in <double>[0, -1, double.nan, double.infinity]) {
      final frame = frameSizeFor(
        imageAspect: aspect,
        viewportWidth: 1600,
        viewportHeight: 900,
        motion: PanMotion.horizontal,
      );

      expect(frame.displayWidth, 1600);
      expect(frame.displayHeight, 900);
      expect(frame.maxX, 0);
      expect(frame.maxY, 0);
    }
  });
}
