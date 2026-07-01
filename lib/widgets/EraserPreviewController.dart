import 'dart:math';

import 'package:flutter/material.dart';

typedef ErasePointCallback =
    void Function({Offset? coordinates, double? radius});

typedef ErasePathCallback =
    void Function({List<Offset>? coordinates, double? radius});

class EraserPreviewController {
  final ValueNotifier<int> repaint = ValueNotifier<int>(0);
  final List<Offset> points = [];

  Offset? _lastPosition;

  void start() {
    _lastPosition = null;
    reset();
  }

  void add(Offset position, {required double radius}) {
    final minDistance = max(1.0, radius * 0.25);
    final previousPosition = _lastPosition;
    if (previousPosition != null &&
        (position - previousPosition).distance < minDistance) {
      return;
    }

    _lastPosition = position;
    points.add(position);
    repaint.value++;
  }

  void apply({
    required double? radius,
    required ErasePointCallback fallback,
    ErasePathCallback? path,
  }) {
    if (points.isEmpty) return;

    final coordinates = List<Offset>.from(points);
    if (path != null) {
      path(coordinates: coordinates, radius: radius);
      return;
    }

    for (final coordinate in coordinates) {
      fallback(coordinates: coordinate, radius: radius);
    }
  }

  void reset() {
    _lastPosition = null;
    if (points.isEmpty) return;
    points.clear();
    repaint.value++;
  }

  void dispose() {
    repaint.dispose();
  }
}

class EraserPreviewPainter extends CustomPainter {
  final List<Offset> Function() pointsProvider;
  final double Function() radiusProvider;

  EraserPreviewPainter({
    required this.pointsProvider,
    required this.radiusProvider,
    Listenable? repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final points = pointsProvider();
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.28)
      ..strokeWidth = radiusProvider()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (points.length == 1) {
      canvas.drawCircle(points.first, paint.strokeWidth / 2, paint);
      return;
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant EraserPreviewPainter oldDelegate) {
    return oldDelegate.pointsProvider != pointsProvider ||
        oldDelegate.radiusProvider != radiusProvider;
  }
}
