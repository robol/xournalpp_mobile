import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/widgets/StrokePointBuffer.dart';

void main() {
  test('large jumps have bounded work and preserve exact endpoint', () {
    final buffer = StrokePointBuffer();
    buffer.add(XppStrokePoint(x: 0, y: 0, width: 2));
    final added = buffer.add(XppStrokePoint(x: 1000000, y: 1000000, width: 3));
    expect(added.length, lessThanOrEqualTo(32));
    buffer.add(XppStrokePoint(x: 2000000, y: 0, width: 4));
    final smoothed = buffer.smoothedPoints();
    expect(smoothed.length, lessThanOrEqualTo(641));
    expect(smoothed.last.x, 2000000);
    expect(smoothed.last.width, 4);
  });
  test('invalid and repeated identical samples do not enter the buffer', () {
    final buffer = StrokePointBuffer();
    final point = XppStrokePoint(x: 10, y: 20, width: 2);
    buffer.add(point);
    buffer.add(point);
    buffer.add(XppStrokePoint(x: double.nan, y: 1, width: 2));
    buffer.add(XppStrokePoint(x: 1, y: double.infinity, width: 2));
    buffer.add(XppStrokePoint(x: 1, y: 1, width: double.nan));
    expect(buffer.rawPoints, hasLength(1));
    expect(buffer.smoothedPoints(), hasLength(1));
  });
}
