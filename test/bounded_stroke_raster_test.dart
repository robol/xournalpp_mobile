import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';

XppStroke pen(int count, {Color color = Colors.black}) => XppStrokePen(
  color: color,
  points: List.generate(
    count,
    (i) => XppStrokePoint(
      x: 3 + (i % 20).toDouble(),
      y: 3 + (i ~/ 20 % 20).toDouble(),
      width: i.isEven ? .2 : 2.3,
    ),
  ),
);

Widget app(XppPage page, {double scale = 1}) => MaterialApp(
  home: XppPageStack(page: page, rasterScale: scale),
);

XppPage page(List<XppStroke> strokes) => XppPage(
  pageSize: XppPageSize(width: 30, height: 30),
  layers: [XppLayer(content: strokes)],
);

Future<void> drain(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 130));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(done(), isTrue);
  await tester.pump();
}

void main() {
  setUp(() {
    XppPageStack.debugPenCommandsPerPass = 32;
  });
  tearDown(() {
    XppPageStack.debugPenCommandsPerPass = null;
    XppPageStack.debugRasterPass = null;
    XppPageStack.debugVectorWork = null;
    XppPageStack.debugRasterizePicture = null;
  });

  testWidgets(
    'long pen and many short pens use separate bounded native passes',
    (tester) async {
      final strokes = [
        pen(131),
        ...List.generate(12, (_) => pen(5)),
        pen(1),
        pen(0),
      ];
      final original = strokes
          .map((s) => s.toXmlElement().toXmlString())
          .toList();
      final passes = <int>[];
      var complete = false;
      var requests = 0;
      XppPageStack.debugRasterPass = (count, _, done) {
        expect(count, lessThanOrEqualTo(32));
        passes.add(count);
        complete = done;
      };
      XppPageStack.debugVectorWork = (count) =>
          expect(count, lessThanOrEqualTo(32));
      XppPageStack.debugRasterizePicture = (picture, w, h) async {
        requests++;
        return picture.toImage(w, h);
      };
      final document = page(strokes);
      await tester.pumpWidget(app(document));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await drain(tester, () => complete);
      expect(passes.fold(0, (a, b) => a + b), 179);
      expect(requests, passes.length);
      expect(requests, greaterThan(1));
      expect(strokes.map((s) => s.toXmlElement().toXmlString()), original);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final ratio in [1.0, 2.0]) {
    testWidgets('prefix composition matches original painter at ratio $ratio', (
      tester,
    ) async {
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.resetDevicePixelRatio);
      final strokes = [
        pen(83, color: const Color(0x80335577)),
        pen(1),
        XppStrokeHighlight(
          color: Colors.yellow,
          points: [
            XppStrokePoint(x: 3, y: 10, width: 4),
            XppStrokePoint(x: 24, y: 10, width: 4),
          ],
        ),
        pen(4)..fill = 80,
      ];
      ui.Image? actual;
      var done = false;
      XppPageStack.debugRasterPass = (_, _, complete) => done = complete;
      XppPageStack.debugRasterizePicture = (picture, w, h) async {
        actual = await picture.toImage(w, h);
        return actual!;
      };
      await tester.pumpWidget(app(page(strokes)));
      await drain(tester, () => done && actual != null);
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(ratio);
        // Bounds round to (1, 1) for the widest pen endpoints in this fixture.
        // Obtain actual bounds from the authoritative geometry, as production does.
        Rect? bounds;
        for (final stroke in strokes) {
          final b = stroke.eraseBounds;
          if (b != null) bounds = bounds?.expandToInclude(b) ?? b;
        }
        canvas.translate(
          -bounds!.left.floorToDouble().clamp(0.0, 30.0),
          -bounds.top.floorToDouble().clamp(0.0, 30.0),
        );
        for (final stroke in strokes) {
          XppStrokePainter(
            points: stroke.points,
            color: stroke.tool == XppStrokeTool.HIGHLIGHTER
                ? stroke.color!.withValues(alpha: .5)
                : stroke.color,
            topLeft: Offset.zero,
            smoothPressure: stroke.tool == XppStrokeTool.PEN,
            fill: stroke.fill,
          ).paint(canvas, Size.zero);
        }
        final picture = recorder.endRecording();
        final expected = await picture.toImage(actual!.width, actual!.height);
        final a = (await actual!.toByteData())!.buffer.asUint8List();
        final b = (await expected.toByteData())!.buffer.asUint8List();
        var maxDelta = 0;
        for (var i = 0; i < a.length; i++) {
          final delta = (a[i] - b[i]).abs();
          if (delta > maxDelta) maxDelta = delta;
        }
        expect(maxDelta, lessThanOrEqualTo(2));
        expected.dispose();
        picture.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('completed dense run remounts and append reuses its prefix', (
    tester,
  ) async {
    final document = page([pen(97)]);
    var total = 0;
    var done = false;
    XppPageStack.debugRasterPass = (count, _, complete) {
      total += count;
      done = complete;
    };
    XppPageStack.debugVectorWork = (count) =>
        expect(count, lessThanOrEqualTo(32));
    await tester.pumpWidget(app(document));
    await drain(tester, () => done);
    expect(total, 96);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(document));
    await tester.pump(const Duration(milliseconds: 200));
    expect(total, 96);
    document.layers!.single.content!.add(pen(81));
    done = false;
    await tester.pumpWidget(app(document));
    await drain(tester, () => done);
    expect(total, 176);
    // Scale changes rebuild bounded passes, but keep the current complete ink
    // visible while those passes are pending.
    done = false;
    await tester.pumpWidget(app(document, scale: 2));
    expect(find.byType(RawImage), findsWidgets);
    await drain(tester, () => done);
    expect(total, 352);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'destructive edit discards in-flight result, no dense vector bypass',
    (tester) async {
      final pending = Completer<ui.Image>();
      var calls = 0;
      XppPageStack.debugVectorWork = (count) =>
          expect(count, lessThanOrEqualTo(32));
      XppPageStack.debugRasterizePicture = (picture, w, h) {
        calls++;
        return pending.future;
      };
      final document = page([pen(100)]);
      await tester.pumpWidget(app(document));
      await drain(tester, () => calls == 1);
      document.layers!.single.content!.clear();
      await tester.pumpWidget(app(document));
      final recorder = ui.PictureRecorder();
      Canvas(recorder);
      final picture = recorder.endRecording();
      final image = (await tester.runAsync(() => picture.toImage(1, 1)))!;
      pending.complete(image);
      await tester.pump();
      expect(image.debugDisposed, isTrue);
      expect(calls, 1);
      picture.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
