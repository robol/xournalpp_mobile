import 'dart:math';
import 'dart:ui';

import 'package:xournalpp/layer_contents/XppStroke.dart';

class StrokePointBuffer {
  static const double _maxPointSpacing = 1.5;
  static const int _maxInterpolatedPointsPerInput = 32;

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
      max(1, (distance / _maxPointSpacing).ceil()),
    );

    return [
      for (var i = 1; i <= steps; i++) _lerpStrokePoint(start, end, i / steps),
    ];
  }

  void _appendDense(List<XppStrokePoint> dense, XppStrokePoint end) {
    final start = dense.last;
    final steps = max(
      1,
      ((end.offset - start.offset).distance / _maxPointSpacing).ceil(),
    );
    for (var step = 1; step <= steps; step++) {
      dense.add(_lerpStrokePoint(start, end, step / steps));
    }
  }

  XppStrokePoint _lerpStrokePoint(
    XppStrokePoint start,
    XppStrokePoint end,
    double t,
  ) {
    return XppStrokePoint(
      x: lerpDouble(start.x!, end.x!, t),
      y: lerpDouble(start.y!, end.y!, t),
      width: lerpDouble(start.width!, end.width!, t),
    );
  }
}
