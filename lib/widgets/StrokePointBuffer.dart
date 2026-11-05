import 'dart:math';
import 'dart:ui';

import 'package:xournalpp/layer_contents/XppStroke.dart';

class StrokePointBuffer {
  static const double _maxPointSpacing = 1.5;
  static const int _maxInterpolatedPointsPerInput = 32;
  static const int _maxSmoothedPointsPerSegment = 128;

  final List<XppStrokePoint> rawPoints = [];
  final List<XppStrokePoint> points = [];
  List<XppStrokePoint> _smoothed = [];

  bool get isEmpty => points.isEmpty;

  XppStrokePoint get last => points.last;

  void clear() {
    rawPoints.clear();
    points.clear();
    _smoothed = [];
  }

  List<XppStrokePoint> add(XppStrokePoint point) {
    if (point.x?.isFinite != true ||
        point.y?.isFinite != true ||
        point.width?.isFinite != true ||
        point.width! <= 0)
      return [];
    if (rawPoints.isNotEmpty &&
        rawPoints.last.offset == point.offset &&
        rawPoints.last.width == point.width)
      return [];
    if (rawPoints.isEmpty) {
      _smoothed.add(point);
    } else {
      final previous = rawPoints.last;
      _appendDense(_smoothed, _lerpStrokePoint(previous, point, .25));
      _appendDense(_smoothed, _lerpStrokePoint(previous, point, .75));
    }
    rawPoints.add(point);

    if (points.isEmpty) {
      points.add(point);
      return [point];
    }

    final appended = _interpolate(points.last, point);
    points.addAll(appended);
    return appended;
  }

  List<XppStrokePoint> smoothedPoints() {
    if (rawPoints.length < 3) return List<XppStrokePoint>.from(points);

    // Only the final endpoint remains. The stable Chaikin prefix was built
    // incrementally as input arrived, so release no longer reprocesses it.
    final result = List<XppStrokePoint>.from(_smoothed);
    _appendDense(result, rawPoints.last);
    return result;
  }

  List<XppStrokePoint> _interpolate(XppStrokePoint start, XppStrokePoint end) {
    final distance = (end.offset - start.offset).distance;
    final steps = min(
      _maxInterpolatedPointsPerInput,
      distance.isFinite
          ? max(
              1,
              min(
                _maxInterpolatedPointsPerInput.toDouble(),
                distance / _maxPointSpacing,
              ).ceil(),
            )
          : _maxInterpolatedPointsPerInput,
    );

    return [
      for (var i = 1; i <= steps; i++) _lerpStrokePoint(start, end, i / steps),
    ];
  }

  void _appendDense(List<XppStrokePoint> dense, XppStrokePoint end) {
    final start = dense.last;
    final distance = (end.offset - start.offset).distance;
    final steps = distance.isFinite
        ? max(
            1,
            min(
              _maxSmoothedPointsPerSegment.toDouble(),
              distance / _maxPointSpacing,
            ).ceil(),
          )
        : _maxSmoothedPointsPerSegment;
    for (var step = 1; step <= steps; step++) {
      dense.add(_lerpStrokePoint(start, end, step / steps));
    }
  }

  double _safeLerp(double a, double b, double t) =>
      (b - a).isFinite ? lerpDouble(a, b, t)! : a * (1 - t) + b * t;

  XppStrokePoint _lerpStrokePoint(
    XppStrokePoint start,
    XppStrokePoint end,
    double t,
  ) {
    return XppStrokePoint(
      x: _safeLerp(start.x!, end.x!, t),
      y: _safeLerp(start.y!, end.y!, t),
      width: _safeLerp(start.width!, end.width!, t),
    );
  }
}
