import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/StylusInputPolicy.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

void main() {
  for (final touchTool in [EditingTool.STYLUS, EditingTool.ERASER]) {
    testWidgets('cross-page palm cancellation releases $touchTool ownership', (
      t,
    ) async {
      final policy = StylusInputPolicy();
      final keys = [
        GlobalKey<PointerListenerState>(),
        GlobalKey<PointerListenerState>(),
      ];
      final saved = <Object>[];
      var erasures = 0;
      policy.addListener(() {
        for (final key in keys) {
          key.currentState?.cancelRejectedPointers();
        }
      });
      Widget page(int index) => Expanded(
        child: PointerListener(
          key: keys[index],
          stylusPolicy: policy,
          viewportGesturesExternallyManaged: true,
          toolData: {
            PointerDeviceKind.touch: touchTool,
            PointerDeviceKind.stylus: EditingTool.STYLUS,
          },
          color: Colors.black,
          strokeWidth: 2,
          eraserWidth: 10,
          onNewContent: (c) {
            if (index == 0 && c != null) saved.add(c);
          },
          filterEraser: ({coordinates, radius}) {},
          filterEraserPath: ({coordinates, radius}) {
            erasures++;
          },
          child: const SizedBox.expand(),
        ),
      );
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: policy.down,
            onPointerUp: policy.up,
            onPointerCancel: policy.up,
            child: Row(children: [page(0), page(1)]),
          ),
        ),
      );
      await t.sendEventToBinding(
        const PointerDownEvent(
          pointer: 1,
          kind: PointerDeviceKind.touch,
          position: Offset(50, 100),
        ),
      );
      await t.sendEventToBinding(
        const PointerMoveEvent(
          pointer: 1,
          kind: PointerDeviceKind.touch,
          position: Offset(70, 100),
        ),
      );
      await t.sendEventToBinding(
        const PointerDownEvent(
          pointer: 2,
          kind: PointerDeviceKind.stylus,
          position: Offset(450, 100),
        ),
      );
      expect(keys[0].currentState!.strokePoints.isEmpty, isTrue);
      expect(keys[0].currentState!.eraserPreview.points, isEmpty);
      await t.sendEventToBinding(
        const PointerUpEvent(
          pointer: 2,
          kind: PointerDeviceKind.stylus,
          position: Offset(450, 100),
        ),
      );
      await t.sendEventToBinding(
        const PointerUpEvent(
          pointer: 1,
          kind: PointerDeviceKind.touch,
          position: Offset(70, 100),
        ),
      );
      expect(saved, isEmpty);
      expect(erasures, 0);
      await t.pump(const Duration(milliseconds: 501));
      await t.sendEventToBinding(
        const PointerDownEvent(
          pointer: 3,
          kind: PointerDeviceKind.touch,
          position: Offset(50, 100),
        ),
      );
      await t.sendEventToBinding(
        const PointerUpEvent(
          pointer: 3,
          kind: PointerDeviceKind.touch,
          position: Offset(70, 100),
        ),
      );
      if (touchTool == EditingTool.STYLUS) {
        expect(saved, hasLength(1));
      } else {
        expect(erasures, 1);
      }
      await t.pumpWidget(const SizedBox());
      policy.dispose();
    });
  }
}
