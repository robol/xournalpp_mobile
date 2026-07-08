import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:xml/xml.dart';

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

  testWidgets('canvas pinch zoom works while move tool is selected', (
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
          file: XppFile(title: 'Document', pages: [XppPage.empty()]),
        ),
      ),
    );
    await tester.pump();

    final dynamic canvasState = tester.state(find.byType(CanvasPage));
    expect(canvasState.pageScale, 1);

    await tester.sendEventToBinding(
      const PointerDownEvent(
        pointer: 30,
        position: Offset(350, 300),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerDownEvent(
        pointer: 31,
        position: Offset(450, 300),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerMoveEvent(
        pointer: 31,
        position: Offset(500, 300),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.pump();
    await tester.sendEventToBinding(
      const PointerUpEvent(
        pointer: 31,
        position: Offset(500, 300),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerUpEvent(
        pointer: 30,
        position: Offset(350, 300),
        kind: PointerDeviceKind.touch,
      ),
    );

    expect(canvasState.pageScale, greaterThan(1));
  });

  testWidgets('canvas pinch zoom does not rerender PDF background until end', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final background = _RecordingPdfBackground();

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
            pages: [
              XppPage(
                pageSize: XppPageSize.a4,
                background: background,
                layers: [XppLayer.empty()],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(background.targetSizes, hasLength(1));

    await tester.sendEventToBinding(
      const PointerDownEvent(
        pointer: 40,
        position: Offset(350, 300),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerDownEvent(
        pointer: 41,
        position: Offset(450, 300),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerMoveEvent(
        pointer: 41,
        position: Offset(500, 300),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.pump();

    expect(background.targetSizes, hasLength(1));

    await tester.sendEventToBinding(
      const PointerUpEvent(
        pointer: 41,
        position: Offset(500, 300),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerUpEvent(
        pointer: 40,
        position: Offset(350, 300),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.pump();

    expect(background.targetSizes, hasLength(1));

    await tester.pump(const Duration(milliseconds: 200));

    expect(background.targetSizes.length, lessThanOrEqualTo(2));
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

  testWidgets('two touch pointers moving apart report pinch zoom in', (
    WidgetTester tester,
  ) async {
    final scaleDeltas = <double>[];
    var starts = 0;
    var ends = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PointerListener(
          toolData: const {PointerDeviceKind.touch: EditingTool.MOVE},
          onPinchZoomStart: (_) => starts++,
          onPinchZoomUpdate:
              ({
                required scaleDelta,
                required globalFocalPoint,
                required globalFocalDelta,
              }) {
                scaleDeltas.add(scaleDelta);
              },
          onPinchZoomEnd: () => ends++,
          child: const SizedBox(width: 200, height: 200),
        ),
      ),
    );

    await tester.sendEventToBinding(
      const PointerDownEvent(
        pointer: 10,
        position: Offset(80, 100),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerDownEvent(
        pointer: 11,
        position: Offset(120, 100),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerMoveEvent(
        pointer: 11,
        position: Offset(140, 100),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerUpEvent(
        pointer: 11,
        position: Offset(140, 100),
        kind: PointerDeviceKind.touch,
      ),
    );

    expect(starts, 1);
    expect(scaleDeltas, isNotEmpty);
    expect(scaleDeltas.last, greaterThan(1));
    expect(ends, 1);
  });

  testWidgets('two touch pointers moving together report pinch zoom out', (
    WidgetTester tester,
  ) async {
    final scaleDeltas = <double>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PointerListener(
          toolData: const {PointerDeviceKind.touch: EditingTool.MOVE},
          onPinchZoomUpdate:
              ({
                required scaleDelta,
                required globalFocalPoint,
                required globalFocalDelta,
              }) {
                scaleDeltas.add(scaleDelta);
              },
          child: const SizedBox(width: 200, height: 200),
        ),
      ),
    );

    await tester.sendEventToBinding(
      const PointerDownEvent(
        pointer: 12,
        position: Offset(70, 100),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerDownEvent(
        pointer: 13,
        position: Offset(130, 100),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerMoveEvent(
        pointer: 13,
        position: Offset(110, 100),
        kind: PointerDeviceKind.touch,
      ),
    );

    expect(scaleDeltas, isNotEmpty);
    expect(scaleDeltas.last, lessThan(1));
  });

  testWidgets('two touch pointers pinch zoom while touch pen is selected', (
    WidgetTester tester,
  ) async {
    final contents = <XppContent>[];
    final scaleDeltas = <double>[];
    var starts = 0;
    var ends = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PointerListener(
          toolData: const {PointerDeviceKind.touch: EditingTool.STYLUS},
          strokeWidth: 4,
          color: Colors.black,
          onNewContent: (content) {
            if (content != null) contents.add(content);
          },
          onPinchZoomStart: (_) => starts++,
          onPinchZoomUpdate:
              ({
                required scaleDelta,
                required globalFocalPoint,
                required globalFocalDelta,
              }) {
                scaleDeltas.add(scaleDelta);
              },
          onPinchZoomEnd: () => ends++,
          child: const SizedBox(width: 200, height: 200),
        ),
      ),
    );

    await tester.sendEventToBinding(
      const PointerDownEvent(
        pointer: 16,
        position: Offset(80, 100),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerDownEvent(
        pointer: 17,
        position: Offset(120, 100),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerMoveEvent(
        pointer: 17,
        position: Offset(140, 100),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerUpEvent(
        pointer: 17,
        position: Offset(140, 100),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerUpEvent(
        pointer: 16,
        position: Offset(80, 100),
        kind: PointerDeviceKind.touch,
      ),
    );

    expect(starts, 1);
    expect(scaleDeltas, isNotEmpty);
    expect(scaleDeltas.last, greaterThan(1));
    expect(ends, 1);
    expect(contents, isEmpty);
  });

  testWidgets('pinch zoom does not save a stroke on touch up', (
    WidgetTester tester,
  ) async {
    final contents = <XppContent>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PointerListener(
          toolData: const {PointerDeviceKind.touch: EditingTool.MOVE},
          strokeWidth: 4,
          color: Colors.black,
          onNewContent: (content) {
            if (content != null) contents.add(content);
          },
          child: const SizedBox(width: 200, height: 200),
        ),
      ),
    );

    await tester.sendEventToBinding(
      const PointerDownEvent(
        pointer: 14,
        position: Offset(80, 100),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerDownEvent(
        pointer: 15,
        position: Offset(120, 100),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerMoveEvent(
        pointer: 15,
        position: Offset(140, 100),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerUpEvent(
        pointer: 15,
        position: Offset(140, 100),
        kind: PointerDeviceKind.touch,
      ),
    );
    await tester.sendEventToBinding(
      const PointerUpEvent(
        pointer: 14,
        position: Offset(80, 100),
        kind: PointerDeviceKind.touch,
      ),
    );

    expect(contents, isEmpty);
  });
}

class _RecordingPdfBackground extends XppBackgroundPdf {
  final List<Size> targetSizes = [];

  _RecordingPdfBackground()
    : super(onUnavailable: (_, __) => throw UnimplementedError());

  @override
  Widget render({
    ValueChanged<bool>? onLoadingChanged,
    double? targetPixelWidth,
    double? targetPixelHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
  }) {
    targetSizes.add(Size(targetPixelWidth ?? 0, targetPixelHeight ?? 0));
    return const SizedBox.shrink();
  }

  @override
  XmlElement toXmlElement() => XmlElement(XmlName('background'));
}
