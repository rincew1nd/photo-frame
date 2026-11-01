/// Pure placement math for the plugin overlay layer.
///
/// A [PluginPlacement] stores normalized 0..1 coordinates and logical
/// width/height. This library resolves those values into logical pixels inside
/// a viewport and safe-area insets, applies default anchors, optional grid
/// snapping, and clamps drag/resize edits. It does not import Flutter or touch
/// any platform channel.
library;

import 'dart:math' as math;

import 'package:photoframe/data/plugins/plugin_manifest.dart';
import 'package:photoframe/domain/plugins/plugin_snapshot.dart';

/// Smallest logical box produced while resizing, unless the safe area is
/// smaller than this.
const double defaultPluginMinWidth = 80;
const double defaultPluginMinHeight = 48;

/// A placement resolved to logical pixels for one viewport.
class PluginPlacementGeometry {
  const PluginPlacementGeometry({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.placement,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  /// The normalized, clamped placement that should be persisted.
  final PluginPlacement placement;

  double get right => left + width;
  double get bottom => top + height;

  @override
  bool operator ==(Object other) {
    return other is PluginPlacementGeometry &&
        other.left == left &&
        other.top == top &&
        other.width == width &&
        other.height == height &&
        other.placement.anchor == placement.anchor &&
        other.placement.x == placement.x &&
        other.placement.y == placement.y &&
        other.placement.width == placement.width &&
        other.placement.height == placement.height &&
        other.placement.zOrder == placement.zOrder &&
        other.placement.showDuringNight == placement.showDuringNight;
  }

  @override
  int get hashCode => Object.hash(
    left,
    top,
    width,
    height,
    placement.anchor,
    placement.x,
    placement.y,
    placement.width,
    placement.height,
    placement.zOrder,
    placement.showDuringNight,
  );
}

/// Copies a [PluginPlacement] without losing anchor/z-order/night fields.
extension PluginPlacementCopy on PluginPlacement {
  PluginPlacement copyWith({
    PluginAnchor? anchor,
    double? x,
    double? y,
    double? width,
    double? height,
    int? zOrder,
    bool? showDuringNight,
  }) {
    return PluginPlacement(
      anchor: anchor ?? this.anchor,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      zOrder: zOrder ?? this.zOrder,
      showDuringNight: showDuringNight ?? this.showDuringNight,
    );
  }
}

/// Resolves [placement] into the viewport, using the anchor when x/y are null.
PluginPlacementGeometry resolvePluginPlacement({
  required PluginPlacement placement,
  required double viewportWidth,
  required double viewportHeight,
  PluginInsets safeArea = const PluginInsets.zero(),
  bool snapToGrid = false,
  double gridSize = 16,
}) {
  final safeLeft = safeArea.left.clamp(0.0, viewportWidth).toDouble();
  final safeTop = safeArea.top.clamp(0.0, viewportHeight).toDouble();
  final safeWidth = math.max(
    0.0,
    viewportWidth - safeLeft - math.max(0.0, safeArea.right),
  );
  final safeHeight = math.max(
    0.0,
    viewportHeight - safeTop - math.max(0.0, safeArea.bottom),
  );

  final width = _clampSize(placement.width, safeWidth);
  final height = _clampSize(placement.height, safeHeight);

  final anchorX = placement.x;
  final anchorY = placement.y;

  var left = anchorX == null
      ? _anchorLeft(placement.anchor, safeLeft, safeWidth, width)
      : safeLeft + anchorX.clamp(0.0, 1.0) * safeWidth;
  var top = anchorY == null
      ? _anchorTop(placement.anchor, safeTop, safeHeight, height)
      : safeTop + anchorY.clamp(0.0, 1.0) * safeHeight;

  if (snapToGrid && gridSize > 0) {
    left = safeLeft + _snap(left - safeLeft, gridSize);
    top = safeTop + _snap(top - safeTop, gridSize);
  }

  final maxLeft = math.max(safeLeft, safeLeft + safeWidth - width);
  final maxTop = math.max(safeTop, safeTop + safeHeight - height);
  left = left.clamp(safeLeft, maxLeft).toDouble();
  top = top.clamp(safeTop, maxTop).toDouble();

  final normalizedX = safeWidth <= 0
      ? 0.0
      : ((left - safeLeft) / safeWidth).clamp(0.0, 1.0).toDouble();
  final normalizedY = safeHeight <= 0
      ? 0.0
      : ((top - safeTop) / safeHeight).clamp(0.0, 1.0).toDouble();

  return PluginPlacementGeometry(
    left: left,
    top: top,
    width: width,
    height: height,
    placement: placement.copyWith(
      x: normalizedX,
      y: normalizedY,
      width: width,
      height: height,
    ),
  );
}

/// Moves [geometry] by [dx]/[dy] logical pixels and clamps it to the safe area.
PluginPlacementGeometry movePluginPlacement({
  required PluginPlacementGeometry geometry,
  required double dx,
  required double dy,
  required double viewportWidth,
  required double viewportHeight,
  PluginInsets safeArea = const PluginInsets.zero(),
  bool snapToGrid = false,
  double gridSize = 16,
}) {
  final safeLeft = safeArea.left.clamp(0.0, viewportWidth).toDouble();
  final safeTop = safeArea.top.clamp(0.0, viewportHeight).toDouble();
  final safeWidth = math.max(
    0.0,
    viewportWidth - safeLeft - math.max(0.0, safeArea.right),
  );
  final safeHeight = math.max(
    0.0,
    viewportHeight - safeTop - math.max(0.0, safeArea.bottom),
  );

  final normalizedX = safeWidth <= 0
      ? 0.0
      : ((geometry.left - safeLeft + dx) / safeWidth)
            .clamp(0.0, 1.0)
            .toDouble();
  final normalizedY = safeHeight <= 0
      ? 0.0
      : ((geometry.top - safeTop + dy) / safeHeight)
            .clamp(0.0, 1.0)
            .toDouble();

  return resolvePluginPlacement(
    placement: geometry.placement.copyWith(
      x: normalizedX,
      y: normalizedY,
      width: geometry.width,
      height: geometry.height,
    ),
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    safeArea: safeArea,
    snapToGrid: snapToGrid,
    gridSize: gridSize,
  );
}

/// Resizes [geometry] by [dw]/[dh] logical pixels.
///
/// The box stays anchored at its top-left, never shrinks below the minimum
/// size (when space allows), and never grows past the safe-area edge.
PluginPlacementGeometry resizePluginPlacement({
  required PluginPlacementGeometry geometry,
  required double dw,
  required double dh,
  required double viewportWidth,
  required double viewportHeight,
  PluginInsets safeArea = const PluginInsets.zero(),
  bool snapToGrid = false,
  double gridSize = 16,
  double minWidth = defaultPluginMinWidth,
  double minHeight = defaultPluginMinHeight,
  bool preserveAspectRatio = false,
}) {
  final safeLeft = safeArea.left.clamp(0.0, viewportWidth).toDouble();
  final safeTop = safeArea.top.clamp(0.0, viewportHeight).toDouble();
  final safeWidth = math.max(
    0.0,
    viewportWidth - safeLeft - math.max(0.0, safeArea.right),
  );
  final safeHeight = math.max(
    0.0,
    viewportHeight - safeTop - math.max(0.0, safeArea.bottom),
  );

  final maxWidth = math.max(0.0, safeLeft + safeWidth - geometry.left);
  final maxHeight = math.max(0.0, safeTop + safeHeight - geometry.top);
  final widthFloor = math.min(minWidth, maxWidth);
  final heightFloor = math.min(minHeight, maxHeight);

  var width = (geometry.width + dw).clamp(widthFloor, maxWidth).toDouble();
  var height = (geometry.height + dh).clamp(heightFloor, maxHeight).toDouble();
  if (preserveAspectRatio && geometry.width > 0 && geometry.height > 0) {
    final ratio = geometry.width / geometry.height;
    final scale = math.max(
      (geometry.width + dw) / geometry.width,
      (geometry.height + dh) / geometry.height,
    );
    width = (geometry.width * scale).clamp(widthFloor, maxWidth).toDouble();
    height = width / ratio;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * ratio;
    }
    if (height < heightFloor) {
      height = heightFloor;
      width = height * ratio;
    }
    if (width > maxWidth) {
      width = maxWidth;
      height = width / ratio;
    }
  }
  if (snapToGrid && gridSize > 0) {
    width = _snap(width, gridSize).clamp(widthFloor, maxWidth).toDouble();
    if (preserveAspectRatio && geometry.height > 0) {
      height = width / (geometry.width / geometry.height);
      height = height.clamp(heightFloor, maxHeight).toDouble();
      width = height * (geometry.width / geometry.height);
    } else {
      height = _snap(height, gridSize).clamp(heightFloor, maxHeight).toDouble();
    }
  }

  return resolvePluginPlacement(
    placement: geometry.placement.copyWith(width: width, height: height),
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    safeArea: safeArea,
    snapToGrid: snapToGrid,
    gridSize: gridSize,
  );
}

double _clampSize(double value, double available) {
  if (!value.isFinite) {
    return available;
  }
  return value.clamp(0.0, available).toDouble();
}

double _snap(double value, double grid) {
  return (value / grid).round() * grid;
}

double _anchorLeft(
  PluginAnchor anchor,
  double safeLeft,
  double safeWidth,
  double width,
) {
  final room = math.max(0.0, safeWidth - width);
  return switch (anchor) {
    PluginAnchor.topStart ||
    PluginAnchor.centerStart ||
    PluginAnchor.bottomStart => safeLeft,
    PluginAnchor.topCenter ||
    PluginAnchor.centerCenter ||
    PluginAnchor.bottomCenter => safeLeft + room / 2,
    PluginAnchor.topEnd ||
    PluginAnchor.centerEnd ||
    PluginAnchor.bottomEnd => safeLeft + room,
  };
}

double _anchorTop(
  PluginAnchor anchor,
  double safeTop,
  double safeHeight,
  double height,
) {
  final room = math.max(0.0, safeHeight - height);
  return switch (anchor) {
    PluginAnchor.topStart ||
    PluginAnchor.topCenter ||
    PluginAnchor.topEnd => safeTop,
    PluginAnchor.centerStart ||
    PluginAnchor.centerCenter ||
    PluginAnchor.centerEnd => safeTop + room / 2,
    PluginAnchor.bottomStart ||
    PluginAnchor.bottomCenter ||
    PluginAnchor.bottomEnd => safeTop + room,
  };
}
