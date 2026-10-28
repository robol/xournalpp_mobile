import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/PageGeometry.dart';
import 'package:xournalpp/src/RasterWorkQueue.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/TransparentImage.dart';
import 'package:xournalpp/widgets/StrokePointBuffer.dart';
import 'package:xournalpp/widgets/StrokePreviewController.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

void main() {
  test(
    'page prefix lookup matches mixed-size linear layout at every scale',
    () {
      final pages = List.generate(
        500,
        (i) => XppPage(
          pageSize: XppPageSize(width: 200, height: 100 + (i % 7) * 50.0),
        ),
      );
      final geometry = PageGeometry(pages);
      for (final width in [40.0, 700.0, 3500.0]) {
        var top = 12.0;
        for (var i = 0; i < pages.length; i++) {
          expect(geometry.offset(i, width, 16, 12), closeTo(top, 1e-7));
          expect(geometry.pageAt(top + .01, width, 16, 12), i);
          expect(geometry.indexOf(pages[i]), i);
          top += width / pages[i].pageSize!.ratio + 16;
        }
      }
      pages.removeAt(1);
      expect(PageGeometry(pages).indexOf(pages[1]), 1);
    },
  );

  test('incremental smoothing matches original batch algorithm exactly', () {
    final random = Random(5);
    final input = List.generate(
      400,
      (_) => XppStrokePoint(
        x: random.nextDouble() * 100,
        y: random.nextDouble() * 100,
        width: random.nextDouble() * 5,
      ),
    );
    XppStrokePoint lerp(XppStrokePoint a, XppStrokePoint b, double t) =>
        XppStrokePoint(
          x: ui.lerpDouble(a.x, b.x, t),
          y: ui.lerpDouble(a.y, b.y, t),
          width: ui.lerpDouble(a.width, b.width, t),
        );
    final smooth = <XppStrokePoint>[input.first];
    for (var i = 0; i < input.length - 1; i++) {
      smooth.add(lerp(input[i], input[i + 1], .25));
      smooth.add(lerp(input[i], input[i + 1], .75));
    }
    smooth.add(input.last);
    final expected = <XppStrokePoint>[smooth.first];
    for (final end in smooth.skip(1)) {
      final start = expected.last;
      final steps = max(1, ((end.offset - start.offset).distance / 1.5).ceil());
      for (var i = 1; i <= steps; i++) {
        expected.add(lerp(start, end, i / steps));
      }
    }
    final buffer = StrokePointBuffer();
    for (final point in input) {
      buffer.add(point);
    }
    final actual = buffer.smoothedPoints();
    expect(
      actual.map((p) => (p.x, p.y, p.width)).toList(),
      expected.map((p) => (p.x, p.y, p.width)).toList(),
    );
    buffer.clear();
    expect(actual, isNotEmpty);
  });

  testWidgets('loaded embedded image has no persistent animation', (
    tester,
  ) async {
    final content = XppImage(
      data: kTransparentImage,
      topLeft: Offset.zero,
      bottomRight: const Offset(40, 40),
    );
    await tester.pumpWidget(MaterialApp(home: content.render()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stroke hit overlay does not swallow text taps', (tester) async {
    final stroke = XppStrokePen(
      color: Colors.black,
      points: [XppStrokePoint(x: 10, y: 10, width: 2)],
    );
    final text = XppText(
      text: 'Select this',
      offset: const Offset(100, 100),
      size: 20,
    );
    final page = XppPage(
      pageSize: XppPageSize(width: 300, height: 300),
      layers: [
        XppLayer(content: [stroke, text]),
      ],
    );
    XppContent? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: XppPageStack(
            page: page,
            activeTool: EditingTool.SELECT,
            onSelectContent: (_, content) => selected = content,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Select this'));
    await tester.pump();
    expect(selected, same(text));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('long preview keeps widget count bounded and fades on frames', (
    tester,
  ) async {
    final preview = StrokePreviewController(colorProvider: () => Colors.black);
    for (var i = 0; i < 2400; i++) {
      preview.addPoint(
        XppStrokePoint(
          x: (i % 100).toDouble(),
          y: (i % 80).toDouble(),
          width: 2,
        ),
        onChunkReady: () {},
      );
    }
    await tester.pumpWidget(
      MaterialApp(home: Stack(children: preview.buildWidgets())),
    );
    expect(find.byType(CustomPaint).evaluate().length, lessThan(6));
    preview.reset();
    for (var i = 0; i < 30; i++) {
      preview.addPoint(
        XppStrokePoint(x: i.toDouble(), y: 10, width: 2),
        onChunkReady: () {},
        fadeOutDuration: const Duration(milliseconds: 100),
      );
    }
    preview.finish(fadeOutDuration: const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    preview.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('raster queue serializes jobs and skips obsolete work', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      final queue = RasterWorkQueue();
      final gate = Completer<void>();
      final started = Completer<void>();
      final finished = Completer<void>();
      final calls = <int>[];
      queue.schedule(
        run: () async {
          calls.add(1);
          started.complete();
          await gate.future;
        },
        isCurrent: () => true,
      );
      await started.future;
      var current = true;
      queue.schedule(
        run: () async {
          calls.add(2);
        },
        isCurrent: () => current,
      );
      queue.schedule(
        run: () async {
          calls.add(3);
          finished.complete();
        },
        isCurrent: () => true,
      );
      expect(calls, [1]);
      current = false;
      gate.complete();
      await finished.future;
      expect(calls, [1, 3]);
    });
  });
}
