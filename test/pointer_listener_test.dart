import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

void main() {
  testWidgets('desktop scroll pans regardless of selected tool', (
    WidgetTester tester,
  ) async {
    final panDeltas = <Offset>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PointerListener(
          toolData: const {PointerDeviceKind.mouse: EditingTool.STYLUS},
          onPan: panDeltas.add,
          child: const SizedBox(width: 200, height: 200),
        ),
      ),
    );

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(100, 100),
        scrollDelta: Offset(0, 24),
        kind: PointerDeviceKind.mouse,
      ),
    );

    expect(panDeltas, [const Offset(0, -24)]);
  });
}
