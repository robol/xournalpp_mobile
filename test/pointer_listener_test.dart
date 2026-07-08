import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
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

  testWidgets('desktop scroll pans when pointer is between pages', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          DefaultMaterialLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: CanvasPage(
          file: XppFile(
            title: 'Document',
            pages: [XppPage.empty(), XppPage.empty(), XppPage.empty()],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendEventToBinding(
      const PointerHoverEvent(
        position: Offset(400, 300),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(400, 300),
        scrollDelta: Offset(0, 1100),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();
    await tester.sendEventToBinding(
      const PointerHoverEvent(
        position: Offset(400, 300),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();

    final verticalScrollable = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere((state) => state.position.axis == Axis.vertical);
    final beforeGapScroll = verticalScrollable.position.pixels;

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(400, 140),
        scrollDelta: Offset(0, 24),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();

    expect(verticalScrollable.position.pixels, greaterThan(beforeGapScroll));
  });

  testWidgets('stylus primary button uses eraser while pen is selected', (
    WidgetTester tester,
  ) async {
    final contents = <XppContent>[];
    final erasedPaths = <List<Offset>>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PointerListener(
          toolData: const {PointerDeviceKind.stylus: EditingTool.STYLUS},
          strokeWidth: 4,
          eraserWidth: 12,
          color: Colors.black,
          onNewContent: (content) {
            if (content != null) contents.add(content);
          },
          filterEraser: ({coordinates, radius}) {},
          filterEraserPath: ({coordinates, radius}) {
            erasedPaths.add(List<Offset>.from(coordinates ?? const []));
          },
          child: const SizedBox(width: 200, height: 200),
        ),
      ),
    );

    await tester.sendEventToBinding(
      const PointerDownEvent(
        pointer: 1,
        position: Offset(20, 20),
        kind: PointerDeviceKind.stylus,
        buttons: kPrimaryStylusButton,
      ),
    );
    await tester.sendEventToBinding(
      const PointerMoveEvent(
        pointer: 1,
        position: Offset(30, 30),
        kind: PointerDeviceKind.stylus,
        buttons: kPrimaryStylusButton,
      ),
    );
    await tester.sendEventToBinding(
      const PointerUpEvent(
        pointer: 1,
        position: Offset(30, 30),
        kind: PointerDeviceKind.stylus,
      ),
    );

    expect(contents, isEmpty);
    expect(erasedPaths, hasLength(1));
    expect(erasedPaths.single, [const Offset(20, 20), const Offset(30, 30)]);
  });

  testWidgets(
    'stylus secondary button uses eraser while highlighter is selected',
    (WidgetTester tester) async {
      final contents = <XppContent>[];
      final erasedPaths = <List<Offset>>[];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PointerListener(
            toolData: const {PointerDeviceKind.stylus: EditingTool.HIGHLIGHT},
            strokeWidth: 4,
            highlighterWidth: 8,
            eraserWidth: 12,
            highlighterColor: Colors.yellow,
            onNewContent: (content) {
              if (content != null) contents.add(content);
            },
            filterEraser: ({coordinates, radius}) {},
            filterEraserPath: ({coordinates, radius}) {
              erasedPaths.add(List<Offset>.from(coordinates ?? const []));
            },
            child: const SizedBox(width: 200, height: 200),
          ),
        ),
      );

      await tester.sendEventToBinding(
        const PointerDownEvent(
          pointer: 2,
          position: Offset(40, 40),
          kind: PointerDeviceKind.stylus,
          buttons: kSecondaryStylusButton,
        ),
      );
      await tester.sendEventToBinding(
        const PointerMoveEvent(
          pointer: 2,
          position: Offset(50, 50),
          kind: PointerDeviceKind.stylus,
          buttons: kSecondaryStylusButton,
        ),
      );
      await tester.sendEventToBinding(
        const PointerUpEvent(
          pointer: 2,
          position: Offset(50, 50),
          kind: PointerDeviceKind.stylus,
        ),
      );

      expect(contents, isEmpty);
      expect(erasedPaths, hasLength(1));
      expect(erasedPaths.single, [const Offset(40, 40), const Offset(50, 50)]);
    },
  );
}
