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
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(image.debugDisposed, isTrue);
  });
}
