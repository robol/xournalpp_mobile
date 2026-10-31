import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/widgets/StrokeOpeningGate.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';

void main() {
  Widget probe() => StrokeOpeningGate(
    child: Builder(
      builder: (context) =>
          Text(StrokeOpeningScope.isOpen(context) ? 'open' : 'waiting'),
    ),
  );

  testWidgets('waits for actual route completion, not a fixed delay', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const SizedBox()),
    );
    navigator.currentState!.push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(seconds: 2),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        reverseTransitionDuration: const Duration(seconds: 1),
        pageBuilder: (_, _, _) => probe(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('waiting'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('open'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'opens immediately without a route or with a zero duration route',
    (tester) async {
      await tester.pumpWidget(
        Directionality(textDirection: TextDirection.ltr, child: probe()),
      );
      expect(find.text('open'), findsOneWidget);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox()),
      );
      navigator.currentState!.push(
        PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => probe(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    },
  );

  testWidgets('closed gate creates no stroke painters or raster jobs', (
    tester,
  ) async {
    final layer = XppLayer(
      content: [
        XppStrokePen(
          color: Colors.black,
          points: [
            XppStrokePoint(x: 1, y: 1, width: 1),
            XppStrokePoint(x: 10, y: 10, width: 1),
          ],
        ),
      ],
    );
    var rasters = 0;
    XppPageStack.debugRasterizePicture = (_, _, _) async {
      rasters++;
      throw StateError('Unexpected raster during opening');
    };
    Widget page(bool open) => MaterialApp(
      home: StrokeOpeningScope(
        open: open,
        child: XppLayerStack(
          layer: layer,
          pageSize: const Size(40, 40),
          rasterScale: 1,
        ),
      ),
    );
    await tester.pumpWidget(page(false));
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.descendant(
        of: find.byType(XppLayerStack),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    expect(rasters, 0);
    await tester.pumpWidget(page(true));
    expect(
      find.descendant(
        of: find.byType(XppLayerStack),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    XppPageStack.debugRasterizePicture = null;
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing during opening removes the animation listener', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const SizedBox()),
    );
    navigator.currentState!.push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(seconds: 2),
        pageBuilder: (_, _, _) => probe(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
