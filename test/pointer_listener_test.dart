import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppFile.dart';
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
}
