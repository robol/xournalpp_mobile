import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/widgets/EditingToolbar.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/ShapeTool.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

void main() {
  testWidgets('toolbar icon follows the shape chosen in settings', (
    tester,
  ) async {
    var settings = const ShapeSettings();
    final devices = <PointerDeviceKind?, EditingTool>{null: EditingTool.SHAPE};
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => EditingToolBar(
              compact: true,
              deviceMap: devices,
              getColor: (_) => Colors.black,
              onNewDeviceMap: (_) {},
              shapeSettings: settings,
              onShapeSettingsChanged: (value) =>
                  setState(() => settings = value),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.widget<ShapeIcon>(find.byType(ShapeIcon)).kind,
      ShapeKind.line,
    );
    await tester.tap(find.byTooltip('Shapes'));
    await tester.pumpAndSettle();
    if (find.text('Circle').evaluate().isEmpty) {
      await tester.tap(find.byTooltip('Shapes'));
      await tester.pumpAndSettle();
    }
    for (final entry in <String, ShapeKind>{
      'Circle': ShapeKind.circle,
      'Square': ShapeKind.square,
      'Ellipse': ShapeKind.ellipse,
      'Rectangle': ShapeKind.rectangle,
      'Line': ShapeKind.line,
    }.entries) {
      await tester.tap(find.text(entry.key));
      await tester.pump();
      expect(
        tester.widget<ShapeIcon>(find.byType(ShapeIcon)).kind,
        entry.value,
      );
    }
  });
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

  test(
    'rectangle and ellipse follow both drag dimensions in either direction',
    () {
      for (final kind in [ShapeKind.rectangle, ShapeKind.ellipse]) {
        for (final endpoints in [
          [const Offset(10, 20), const Offset(90, 60)],
          [const Offset(90, 60), const Offset(10, 20)],
        ]) {
          final stroke = shapeStrokes(
            endpoints[0],
            endpoints[1],
            ShapeSettings(kind: kind),
          ).single;
          final xs = stroke.points!.map((point) => point.x!).toList()..sort();
          final ys = stroke.points!.map((point) => point.y!).toList()..sort();
          expect(xs.first, closeTo(10, .001));
          expect(xs.last, closeTo(90, .001));
          expect(ys.first, closeTo(20, .001));
          expect(ys.last, closeTo(60, .001));
          expect(stroke.fill, isNull);
          expect(stroke.points!.first.x, closeTo(stroke.points!.last.x!, .001));
          expect(stroke.points!.first.y, closeTo(stroke.points!.last.y!, .001));
        }
        expect(
          shapeStrokes(
            Offset.zero,
            const Offset(40, 1),
            ShapeSettings(kind: kind),
          ),
          isEmpty,
        );
      }
    },
  );

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
