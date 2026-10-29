import 'dart:math' as math;

import 'package:xournalpp/layer_contents/XppStroke.dart';

/// Reduces newly captured points without changing the live stroke preview.
/// Keep points close enough for the existing point-based eraser to hit lines.
List<XppStrokePoint> simplifyStrokePoints(List<XppStrokePoint> points) {
  const maxSpan = 1.5;
  const geometryTolerance = 0.1;
  const widthTolerance = 0.1;
  const maxWindow = 64;
  if (points.length < 3) return List.of(points);

  final result = <XppStrokePoint>[points.first];
  var start = 0;
  while (start < points.length - 1) {
    var end = start + 1;
    var length = 0.0;
    while (end < points.length && end - start <= maxWindow) {
      final nextLength =
          length + (points[end].offset - points[end - 1].offset).distance;
      if (nextLength > maxSpan && end > start + 1) break;
      length = nextLength;
      end++;
    }
    end--;
    final keep = <int>{start, end};
    final pending = <(int, int)>[(start, end)];
    while (pending.isNotEmpty) {
      final (first, last) = pending.removeLast();
      final a = points[first].offset;
      final b = points[last].offset;
      final delta = b - a;
      final lengthSquared = delta.distanceSquared;
      var worst = 1.0;
      var split = -1;
      var previousT = 0.0;
      for (var i = first + 1; i < last; i++) {
        final p = points[i].offset;
        final t = lengthSquared == 0
            ? 0.0
            : (((p.dx - a.dx) * delta.dx + (p.dy - a.dy) * delta.dy) /
                      lengthSquared)
                  .clamp(0.0, 1.0);
        final distance = (p - (a + delta * t)).distance;
        // The renderer uses the final point's width for the entire segment.
        final widthError = ((points[i].width ?? 0) - (points[last].width ?? 0))
            .abs();
        var error = math.max(
          distance / geometryTolerance,
          widthError / widthTolerance,
        );
        // A collinear reversal is part of the path, not a redundant point.
        if (t < previousT) error = math.max(error, 2.0);
        previousT = t;
        if (error > worst) {
          worst = error;
          split = i;
        }
      }
      if (split != -1) {
        keep.add(split);
        pending.add((first, split));
        pending.add((split, last));
      }
    }
    final indices = keep.toList()..sort();
    result.addAll(indices.skip(1).map((index) => points[index]));
    start = end;
  }
  return result;
}
