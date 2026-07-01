import 'dart:math';
import 'dart:ui';

import 'package:xournalpp/layer_contents/XppStroke.dart';

class StrokePointBuffer {
  static const double _maxPointSpacing = 1.5;
  static const int _maxInterpolatedPointsPerInput = 32;
  static const int _smoothingIterations = 1;

  final List<XppStrokePoint> rawPoints = [];
  final List<XppStrokePoint> points = [];

  bool get isEmpty => points.isEmpty;

  XppStrokePoint get last => points.last;

  void clear() {
    rawPoints.clear();
    points.clear();
  }

  List<XppStrokePoint> add(XppStrokePoint point) {
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

    var smoothed = List<XppStrokePoint>.from(rawPoints);
    for (var i = 0; i < _smoothingIterations; i++) {
      smoothed = _chaikinSmooth(smoothed);
    }

    return _densify(smoothed);
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

  List<XppStrokePoint> _chaikinSmooth(List<XppStrokePoint> source) {
    if (source.length < 3) return source;

    final smoothed = <XppStrokePoint>[source.first];
    for (var i = 0; i < source.length - 1; i++) {
      final start = source[i];
      final end = source[i + 1];
      smoothed.add(_lerpStrokePoint(start, end, 0.25));
      smoothed.add(_lerpStrokePoint(start, end, 0.75));
    }
    smoothed.add(source.last);
    return smoothed;
  }

  List<XppStrokePoint> _densify(List<XppStrokePoint> source) {
    if (source.length < 2) return source;

    final dense = <XppStrokePoint>[source.first];
    for (var i = 1; i < source.length; i++) {
      final start = dense.last;
      final end = source[i];
      final distance = (end.offset - start.offset).distance;
      final steps = max(1, (distance / _maxPointSpacing).ceil());
      for (var step = 1; step <= steps; step++) {
        dense.add(_lerpStrokePoint(start, end, step / steps));
      }
    }
    return dense;
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
