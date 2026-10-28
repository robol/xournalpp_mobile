import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';

XppPage _page() => XppPage(
  pageSize: XppPageSize(width: 40, height: 40),
  background: XppBackgroundSolidLined(size: XppPageSize(width: 40, height: 40)),
  layers: [
    XppLayer(
      content: [
        XppStrokePen(
          color: Colors.black,
          points: [
            XppStrokePoint(x: 1, y: 1, width: 1),
            XppStrokePoint(x: 10, y: 10, width: 1),
          ],
        ),
      ],
    ),
  ],
);

Widget _app(XppPage page, double scale) => MaterialApp(
  home: XppPageStack(page: page, rasterScale: scale),
);

Future<void> _startRaster(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 130));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
}

Future<ui.Image> _image(WidgetTester tester) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.black, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return (await tester.runAsync(() => picture.toImage(1, 1)))!;
  } finally {
    picture.dispose();
  }
}

void main() {
  tearDown(() => XppPageStack.debugRasterizePicture = null);

  testWidgets('stroke raster survives remount but not content replacement', (
    tester,
  ) async {
    var calls = 0;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final images = <ui.Image>[];
    for (var i = 0; i < 2; i++) {
      images.add(await _image(tester));
    }
    XppPageStack.debugRasterizePicture = (_, width, height) async {
      expect(width, 40);
      expect(height, 40);
      return images[calls++];
    };
    final page = _page();
    await tester.pumpWidget(_app(page, 1));
    await _startRaster(tester);
    await tester.pump();
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(page, 1));
    expect(find.byType(RawImage), findsWidgets);
    await _startRaster(tester);
    expect(calls, 1);
    page.layers!.first.content![0] = XppStrokePen(
      color: Colors.red,
      points: [XppStrokePoint(x: 3, y: 3, width: 2)],
    );
    await tester.pumpWidget(_app(page, 1));
    await _startRaster(tester);
    await tester.pump();
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'chunked pen recording preserves pressure and translucent overlays',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final points = List.generate(
        1100,
        (i) => XppStrokePoint(
          x: 2 + (i % 30).toDouble(),
          y: 2 + (i % 25).toDouble(),
          width: 1 + (i % 3).toDouble(),
        ),
      );
      final pen = XppStrokePen(color: Colors.black, points: points);
      final highlight = XppStrokeHighlight(
        color: Colors.yellow,
        points: [
          XppStrokePoint(x: 2, y: 15, width: 8),
          XppStrokePoint(x: 35, y: 15, width: 8),
        ],
      );
      final page = XppPage(
        pageSize: XppPageSize(width: 40, height: 40),
        layers: [
          XppLayer(content: [pen, highlight]),
        ],
      );
      ui.Image? actual;
      XppPageStack.debugRasterizePicture = (picture, width, height) async {
        actual = await picture.toImage(width, height);
        return actual!;
      };
      await tester.pumpWidget(_app(page, 1));
      await _startRaster(tester);
      for (var i = 0; i < 8 && actual == null; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(actual, isNotNull);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      XppStrokePainter(
        points: points,
        color: Colors.black,
        topLeft: Offset.zero,
        smoothPressure: true,
      ).paint(canvas, Size.zero);
      XppStrokePainter(
        points: highlight.points,
        color: Colors.yellow.withValues(alpha: .5),
        topLeft: Offset.zero,
        smoothPressure: false,
      ).paint(canvas, Size.zero);
      final picture = recorder.endRecording();
      await tester.runAsync(() async {
        final expected = await picture.toImage(40, 40);
        final expectedBytes = await expected.toByteData();
        final actualBytes = await actual!.toByteData();
        expect(
          actualBytes!.buffer.asUint8List(),
          expectedBytes!.buffer.asUint8List(),
        );
        expected.dispose();
      });
      picture.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('large stroke rasters respect pixel budget', (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);
    final image = await _image(tester);
    var calls = 0;
    XppPageStack.debugRasterizePicture = (_, width, height) async {
      calls++;
      expect(width * height, lessThanOrEqualTo(4 * 1024 * 1024));
      expect(width, lessThanOrEqualTo(4096));
      expect(height, lessThanOrEqualTo(4096));
      return image;
    };
    final page = _page()..pageSize = XppPageSize(width: 595, height: 842);
    await tester.pumpWidget(_app(page, 5));
    await _startRaster(tester);
    await tester.pump();
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pending rerasterization does not access a disposed page', (
    tester,
  ) async {
    final result = Completer<ui.Image>();
    var calls = 0;
    late ui.Picture picture;
    XppPageStack.debugRasterizePicture = (value, _, __) {
      picture = value;
      calls++;
      return result.future;
    };
    final page = _page();
    await tester.pumpWidget(_app(page, 1));
    await _startRaster(tester);
    expect(calls, 1);
    await tester.pumpWidget(_app(page, 2));
    await tester.pumpWidget(const SizedBox());
    final image = await _image(tester);
    result.complete(image);
    await tester.pump();
    await _startRaster(tester);
    expect(calls, 1);
    expect(image.debugDisposed, isTrue);
    expect(picture.debugDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed raster releases resources and can retry on update', (
    tester,
  ) async {
    final result = Completer<ui.Image>();
    var calls = 0;
    late ui.Picture failedPicture;
    final image = await _image(tester);
    XppPageStack.debugRasterizePicture = (value, _, __) {
      calls++;
      if (calls == 1) {
        failedPicture = value;
        return result.future;
      }
      return Future.value(image);
    };
    final page = _page();
    await tester.pumpWidget(_app(page, 1));
    await _startRaster(tester);
    expect(calls, 1);
    result.completeError(StateError('native raster failed'));
    await tester.pump();
    expect(failedPicture.debugDisposed, isTrue);
    await tester.pumpWidget(_app(page, 1));
    await _startRaster(tester);
    await tester.pump();
    expect(calls, 2);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is RawImage && identical(widget.image, image),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(image.debugDisposed, isTrue);
  });
}
