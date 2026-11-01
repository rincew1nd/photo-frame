import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';
import 'package:photoframe/domain/plugins/plugin_placement_editor.dart';
import 'package:photoframe/domain/plugins/plugin_snapshot.dart';

void main() {
  test('resolves anchors inside the safe area', () {
    final topLeft = resolvePluginPlacement(
      placement: const PluginPlacement(
        anchor: PluginAnchor.topStart,
        width: 200,
        height: 100,
      ),
      viewportWidth: 1000,
      viewportHeight: 600,
      safeArea: const PluginInsets(top: 20, left: 30, right: 10, bottom: 10),
    );
    expect(topLeft.left, 30);
    expect(topLeft.top, 20);

    final bottomRight = resolvePluginPlacement(
      placement: const PluginPlacement(
        anchor: PluginAnchor.bottomEnd,
        width: 200,
        height: 100,
      ),
      viewportWidth: 1000,
      viewportHeight: 600,
      safeArea: const PluginInsets(top: 20, left: 30, right: 10, bottom: 10),
    );
    expect(bottomRight.right, 990);
    expect(bottomRight.bottom, 590);
  });

  test('clamps explicit coordinates and size to the viewport', () {
    final geometry = resolvePluginPlacement(
      placement: const PluginPlacement(x: 2, y: -1, width: 2000, height: 900),
      viewportWidth: 800,
      viewportHeight: 500,
    );

    expect(geometry.left, 0);
    expect(geometry.top, 0);
    expect(geometry.width, 800);
    expect(geometry.height, 500);
    expect(geometry.placement.x, 0);
    expect(geometry.placement.y, 0);
  });

  test('snaps to the configured grid inside the safe origin', () {
    final geometry = resolvePluginPlacement(
      placement: const PluginPlacement(x: 0.1, y: 0.1, width: 200, height: 100),
      viewportWidth: 1000,
      viewportHeight: 600,
      safeArea: const PluginInsets(top: 20, left: 30),
      snapToGrid: true,
      gridSize: 16,
    );

    expect((geometry.left - 30) % 16, 0);
    expect((geometry.top - 20) % 16, 0);
  });

  test('moves within bounds and keeps size', () {
    final initial = resolvePluginPlacement(
      placement: const PluginPlacement(
        x: 0.1,
        y: 0.1,
        width: 200,
        height: 100,
      ),
      viewportWidth: 800,
      viewportHeight: 500,
    );
    final moved = movePluginPlacement(
      geometry: initial,
      dx: 1000,
      dy: -1000,
      viewportWidth: 800,
      viewportHeight: 500,
    );

    expect(moved.width, 200);
    expect(moved.height, 100);
    expect(moved.right, 800);
    expect(moved.top, 0);
  });

  test('proportional resize keeps the aspect ratio', () {
    final initial = resolvePluginPlacement(
      placement: const PluginPlacement(x: 0.1, y: 0.1, width: 200, height: 100),
      viewportWidth: 1000,
      viewportHeight: 700,
    );
    final grown = resizePluginPlacement(
      geometry: initial,
      dw: 80,
      dh: 0,
      viewportWidth: 1000,
      viewportHeight: 700,
      preserveAspectRatio: true,
    );
    expect(grown.width / grown.height, closeTo(2, 0.001));
    expect(grown.width, greaterThan(initial.width));

    final shrunk = resizePluginPlacement(
      geometry: initial,
      dw: -500,
      dh: 0,
      viewportWidth: 1000,
      viewportHeight: 700,
      preserveAspectRatio: true,
    );
    expect(shrunk.width / shrunk.height, closeTo(2, 0.001));
  });

  test('resizes with a minimum size and safe-area maximum', () {
    final initial = resolvePluginPlacement(
      placement: const PluginPlacement(
        x: 0,
        y: 0,
        width: 200,
        height: 100,
      ),
      viewportWidth: 800,
      viewportHeight: 500,
    );
    final smaller = resizePluginPlacement(
      geometry: initial,
      dw: -1000,
      dh: -1000,
      viewportWidth: 800,
      viewportHeight: 500,
    );
    expect(smaller.width, defaultPluginMinWidth);
    expect(smaller.height, defaultPluginMinHeight);

    final larger = resizePluginPlacement(
      geometry: initial,
      dw: 1000,
      dh: 1000,
      viewportWidth: 800,
      viewportHeight: 500,
    );
    expect(larger.right, 800);
    expect(larger.bottom, 500);
  });
}
