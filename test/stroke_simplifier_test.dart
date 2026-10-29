import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/widgets/StrokeSimplifier.dart';

XppStrokePoint point(double x, double y, [double width = 1]) =>
    XppStrokePoint(x: x, y: y, width: width);

void main() {
  test('reduces dense straight lines while retaining eraser spacing', () {
    final input = [for (var i = 0; i <= 100; i++) point(i / 10, 0)];
    final result = simplifyStrokePoints(input);
    expect(result.first, same(input.first));
    expect(result.last, same(input.last));
    expect(result.length, lessThan(input.length ~/ 2));
    for (var i = 1; i < result.length; i++) {
      expect(
        (result[i].offset - result[i - 1].offset).distance,
        lessThanOrEqualTo(1.5),
      );
    }
    final stroke = XppStrokePen(points: result, color: Colors.black);
    expect(
      stroke.eraseWhere(coordinates: const Offset(5, 0), radius: 2).affected,
      isTrue,
    );
  });

  test('retains corners and pressure changes', () {
    final corner = point(0.5, 0.5, 2);
    final input = [point(0, 0), corner, point(1, 0)];
    expect(simplifyStrokePoints(input), contains(same(corner)));
    final pressure = point(0.5, 0, 2);
    expect(
      simplifyStrokePoints([point(0, 0), pressure, point(1, 0)]),
      contains(same(pressure)),
    );
  });

  test('preserves dots, endpoints and coincident pressure changes', () {
    final dot = point(0, 0);
    expect(simplifyStrokePoints([]), isEmpty);
    expect(simplifyStrokePoints([dot]), [dot]);
    final pressure = point(0, 0, 2);
    expect(
      simplifyStrokePoints([dot, pressure, point(0, 0)]),
      contains(same(pressure)),
    );
  });
}
