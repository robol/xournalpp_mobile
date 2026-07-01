import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';

void main() {
  test('eraseWhere splits a stroke around erased points', () {
    final stroke = XppStrokePen(
      points: [
        XppStrokePoint(x: 0, y: 0, width: 4),
        XppStrokePoint(x: 10, y: 0, width: 4),
        XppStrokePoint(x: 20, y: 0, width: 4),
      ],
    );

    final delta = stroke.eraseWhere(coordinates: Offset(10, 0), radius: 4);

    expect(delta.affected, isTrue);
    expect(delta.delete, isFalse);
    expect(delta.newContent, hasLength(2));

    final firstStroke = delta.newContent[0] as XppStroke;
    final secondStroke = delta.newContent[1] as XppStroke;

    expect(firstStroke.points!.map((point) => point.x), [0]);
    expect(secondStroke.points!.map((point) => point.x), [20]);
  });
}
