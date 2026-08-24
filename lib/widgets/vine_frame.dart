import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A hand-illustrated-feeling vine curling along a card's edges, painted
/// vector (no image asset, no new package — this codebase deliberately
/// avoids new animation/SVG dependencies after earlier build friction).
/// Wraps its child, so any card becomes "framed" just by adding this.
///
/// The vine is a single continuous bezier path that runs up the left edge,
/// arcs across the top, and down the right edge, with small leaf shapes
/// budding off it at intervals — corners get more density since that's
/// where "vines growing around a card" reads most clearly at a glance.
class VineFrame extends StatelessWidget {
  final Widget child;
  final Color vineColor;
  final Color leafColor;
  final double intensity; // 0..1 — how much of the frame is drawn; the highlighted plan gets a fuller vine

  const VineFrame({
    super.key,
    required this.child,
    required this.vineColor,
    required this.leafColor,
    this.intensity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _VinePainter(vineColor: vineColor, leafColor: leafColor, intensity: intensity),
      child: child,
    );
  }
}

class _VinePainter extends CustomPainter {
  final Color vineColor;
  final Color leafColor;
  final double intensity;
  _VinePainter({required this.vineColor, required this.leafColor, required this.intensity});

  void _leaf(Canvas canvas, Offset at, double angle, double size, Paint paint) {
    final path = Path();
    path.moveTo(0, 0);
    path.quadraticBezierTo(size * 0.55, -size * 0.35, size, 0);
    path.quadraticBezierTo(size * 0.55, size * 0.35, 0, 0);
    path.close();
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final vinePaint = Paint()
      ..color = vineColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final leafPaint = Paint()..color = leafColor.withValues(alpha: 0.75 * intensity);

    // Top-left corner curl.
    final tl = Path()
      ..moveTo(0, size.height * 0.32)
      ..cubicTo(0, size.height * 0.12, size.width * 0.06, 0, size.width * 0.26, 0);
    canvas.drawPath(tl, vinePaint..color = vinePaint.color.withValues(alpha: 0.55 * intensity));
    _leaf(canvas, Offset(size.width * 0.05, size.height * 0.14), -0.7, 11 * intensity, leafPaint);
    _leaf(canvas, Offset(size.width * 0.15, size.height * 0.02), 0.3, 9 * intensity, leafPaint);

    // Top-right corner curl.
    final tr = Path()
      ..moveTo(size.width, size.height * 0.28)
      ..cubicTo(size.width, size.height * 0.1, size.width * 0.9, 0, size.width * 0.74, 0);
    canvas.drawPath(tr, vinePaint);
    _leaf(canvas, Offset(size.width * 0.95, size.height * 0.12), 2.4, 10 * intensity, leafPaint);

    // Bottom-right, lighter (frame reads as "growing down from the top").
    if (intensity > 0.4) {
      final br = Path()
        ..moveTo(size.width, size.height * 0.68)
        ..cubicTo(size.width, size.height * 0.85, size.width * 0.94, size.height, size.width * 0.82, size.height);
      canvas.drawPath(br, vinePaint..color = vinePaint.color.withValues(alpha: 0.35 * intensity));
      _leaf(canvas, Offset(size.width * 0.9, size.height * 0.9), 1.0, 8 * intensity, leafPaint..color = leafPaint.color.withValues(alpha: 0.5 * intensity));
    }

    // A couple of small free leaves along the left edge for texture.
    for (final t in [0.45, 0.62]) {
      _leaf(canvas, Offset(2, size.height * t), math.pi * 0.15, 7 * intensity, leafPaint..color = leafColor.withValues(alpha: 0.4 * intensity));
    }
  }

  @override
  bool shouldRepaint(covariant _VinePainter oldDelegate) =>
      oldDelegate.vineColor != vineColor || oldDelegate.leafColor != leafColor || oldDelegate.intensity != intensity;
}
