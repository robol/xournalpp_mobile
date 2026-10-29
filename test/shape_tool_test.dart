import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/ShapeTool.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

void main() {
  testWidgets('pinch cancels a shape without committing it', (tester) async {
    var commits = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PointerListener(
          toolData: const {PointerDeviceKind.touch: EditingTool.SHAPE},
          onNewShape: (_) => commits++,
          child: const SizedBox(width: 200, height: 200),
        ),
      ),
    );
    final first = await tester.startGesture(const Offset(20, 20));
    await first.moveTo(const Offset(80, 80));
    final second = await tester.startGesture(const Offset(120, 120));
    await first.up();
    await second.up();
    await tester.pump();
    expect(commits, 0);
  });
  test('square and circle use equal sides and an unfilled outline', () {
    for (final kind in [ShapeKind.square, ShapeKind.circle]) {
      final strokes = shapeStrokes(
        const Offset(100, 100),
        const Offset(40, 20),
        ShapeSettings(kind: kind, outline: Colors.blue),
      );
      expect(strokes, hasLength(1));
      expect(strokes.first.fill, isNull);
      expect(strokes.last.color, Colors.blue);
      final xs = strokes.last.points!.map((p) => p.x!).toList();
      final ys = strokes.last.points!.map((p) => p.y!).toList();
      xs.sort();
      ys.sort();
      expect(xs.last - xs.first, closeTo(60, .001));
      expect(ys.last - ys.first, closeTo(60, .001));
    }
    expect(
      shapeStrokes(Offset.zero, const Offset(1, 1), const ShapeSettings()),
      isEmpty,
    );
    expect(
      shapeStrokes(Offset.zero, const Offset(20, 20), const ShapeSettings()),
      hasLength(1),
    );
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.stylus]) {
    testWidgets('shape drag commits and cancellation does not ($kind)', (
      tester,
    ) async {
      final committed = <List<XppStroke>>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PointerListener(
            toolData: {kind: EditingTool.SHAPE},
            shapeSettings: const ShapeSettings(kind: ShapeKind.square),
            onNewShape: (contents) => committed.add(contents.cast<XppStroke>()),
            child: const SizedBox(width: 200, height: 200),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        const Offset(20, 20),
        kind: kind,
      );
      await gesture.moveTo(const Offset(80, 80));
      await tester.pump();
      expect(committed, isEmpty);
      await gesture.up();
      await tester.pump();
      expect(committed.single, hasLength(1));
      final cancelled = await tester.startGesture(
        const Offset(20, 20),
        kind: kind,
      );
      await cancelled.moveTo(const Offset(80, 80));
      await cancelled.cancel();
      await tester.pump();
      expect(committed, hasLength(1));
    });
  }
}
