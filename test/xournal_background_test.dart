import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/src/PdfExporter.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppPage.dart';

void main() {
  test('Xournal++ A4 ruled paper geometry and colors', () {
    final lines = XppRuledPaper.lines(XppPageSize.a4.height!).toList();
    expect(lines.first, 80);
    expect(lines.last, 776);
    expect(lines, hasLength(30));
    expect(XppRuledPaper.lines(139), isEmpty);
    expect(XppRuledPaper.lineColor(Colors.white), const Color(0xff40a0ff));
    expect(XppRuledPaper.marginColor(Colors.white), const Color(0xffff0080));
    expect(XppRuledPaper.lineColor(Colors.black), const Color(0xff434343));
    expect(XppRuledPaper.marginColor(Colors.black), const Color(0xff220080));
  });

  testWidgets('default lined background draws blue rules and pink margin', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey();
    final page = XppPage.empty();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: page.pageSize!.width,
              height: page.pageSize!.height,
              child: page.background!.render(
                targetPixelWidth: 1191,
                targetPixelHeight: 1684,
              ),
            ),
          ),
        ),
      ),
    );
    for (
      var attempt = 0;
      attempt < 40 && find.byType(RawImage).evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.byType(RawImage), findsOneWidget);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = boundary.toImageSync(pixelRatio: 2);
    final data = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    Color pixel(int x, int y) {
      final offset = (y * image.width + x) * 4;
      return Color.fromARGB(
        data.getUint8(offset + 3),
        data.getUint8(offset),
        data.getUint8(offset + 1),
        data.getUint8(offset + 2),
      );
    }

    final blue = pixel(200, 160);
    expect(blue.b, 1);
    expect(blue.r, lessThan(0.8));
    expect(blue.g, lessThan(0.9));
    final pink = pixel(144, 40);
    expect(pink.r, 1);
    expect(pink.g, lessThan(0.8));
    expect(pink.b, greaterThan(pink.g));
    expect(pixel(200, 48), Colors.white);
    image.dispose();
  });

  test('PDF export includes the same Xournal++ lined paper', () async {
    final pdf = latin1.decode(await exportPdfDocument(XppFile.empty()));
    expect(pdf, contains('0.251 0.6275 1 RG 0.5 w'));
    expect(pdf, contains('0 761.8898 m 595.2756 761.8898 l S'));
    expect(pdf, contains('0 65.8898 m 595.2756 65.8898 l S'));
    expect(pdf, contains('1 0 0.502 RG'));
    expect(pdf, contains('72 0 m 72 841.8898 l S'));
  });
}
