import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/src/XppBackground.dart';

void main() {
  test('solid background cache keys include target pixel size', () {
    const first = RasterizedBackgroundKeyForTest(
      style: 'graph',
      color: Color(0xffffffff),
      size: Size(600, 800),
      targetPixelWidth: 1200,
      targetPixelHeight: 1600,
    );
    const second = RasterizedBackgroundKeyForTest(
      style: 'graph',
      color: Color(0xffffffff),
      size: Size(600, 800),
      targetPixelWidth: 1800,
      targetPixelHeight: 2400,
    );

    expect(first, isNot(second));
  });
}
