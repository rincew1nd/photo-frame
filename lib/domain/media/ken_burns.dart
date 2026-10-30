import 'dart:math' as math;

enum PanMotion { horizontal, vertical, zoom }

class KenBurnsPlan {
  const KenBurnsPlan({
    required this.motion,
    required this.scale,
    required this.translateX,
    required this.translateY,
  });

  final PanMotion motion;
  final double scale;
  final double translateX;
  final double translateY;
}

class KenBurnsFrameSize {
  const KenBurnsFrameSize({
    required this.displayWidth,
    required this.displayHeight,
    required this.maxX,
    required this.maxY,
  });

  final double displayWidth;
  final double displayHeight;
  final double maxX;
  final double maxY;
}

KenBurnsFrameSize frameSizeFor({
  required double imageAspect,
  required double viewportWidth,
  required double viewportHeight,
  required PanMotion motion,
}) {
  final validViewport =
      viewportWidth.isFinite &&
      viewportWidth > 0 &&
      viewportHeight.isFinite &&
      viewportHeight > 0;
  if (!validViewport || !imageAspect.isFinite || imageAspect <= 0) {
    return KenBurnsFrameSize(
      displayWidth: validViewport ? viewportWidth : 0,
      displayHeight: validViewport ? viewportHeight : 0,
      maxX: 0,
      maxY: 0,
    );
  }
  if (motion == PanMotion.horizontal) {
    final displayWidth = viewportHeight * imageAspect;
    return KenBurnsFrameSize(
      displayWidth: displayWidth,
      displayHeight: viewportHeight,
      maxX: math.max(0, (displayWidth - viewportWidth) / 2),
      maxY: 0,
    );
  }
  if (motion == PanMotion.vertical) {
    final displayHeight = viewportWidth / imageAspect;
    return KenBurnsFrameSize(
      displayWidth: viewportWidth,
      displayHeight: displayHeight,
      maxX: 0,
      maxY: math.max(0, (displayHeight - viewportHeight) / 2),
    );
  }
  return KenBurnsFrameSize(
    displayWidth: viewportWidth,
    displayHeight: viewportHeight,
    maxX: 0,
    maxY: 0,
  );
}

const double maxCoverOverflow = 4.0;

KenBurnsPlan kenBurnsPlan({
  required double imageAspect,
  required double viewportAspect,
  required int panStrength,
  required double progress,
  double tolerance = 0.05,
}) {
  final intensity = (panStrength / 100).clamp(0.0, 1.0);
  final valid =
      imageAspect.isFinite &&
      imageAspect > 0 &&
      viewportAspect.isFinite &&
      viewportAspect > 0;
  if (intensity == 0 || !valid) {
    return const KenBurnsPlan(
      motion: PanMotion.zoom,
      scale: 1,
      translateX: 0,
      translateY: 0,
    );
  }
  final t = progress.clamp(0.0, 1.0);
  final difference = imageAspect - viewportAspect;
  if (difference.abs() <= tolerance) {
    final wave = 0.5 - 0.5 * math.cos(2 * math.pi * t);
    return KenBurnsPlan(
      motion: PanMotion.zoom,
      scale: 1 + 0.20 * intensity * wave,
      translateX: 0,
      translateY: 0,
    );
  }
  if (difference > 0) {
    final overflow = (imageAspect / viewportAspect - 1).clamp(
      0.0,
      maxCoverOverflow,
    );
    final half = overflow / 2 * intensity;
    return KenBurnsPlan(
      motion: PanMotion.horizontal,
      scale: 1,
      translateX: (t * 2 - 1) * half,
      translateY: 0,
    );
  }
  final overflow = (viewportAspect / imageAspect - 1).clamp(
    0.0,
    maxCoverOverflow,
  );
  final half = overflow / 2 * intensity;
  return KenBurnsPlan(
    motion: PanMotion.vertical,
    scale: 1,
    translateX: 0,
    translateY: (t * 2 - 1) * half,
  );
}
