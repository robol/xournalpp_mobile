import 'dart:ui';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/PdfImage.dart';
import 'package:xournalpp/src/XppPickedFile.dart';

void main() {
  test('eraseWhere splits a stroke around erased points', () {
    final stroke = XppStrokePen(
      points: [
        XppStrokePoint(x: 0, y: 0, width: 4),
        XppStrokePoint(x: 10, y: 0, width: 4),
        XppStrokePoint(x: 20, y: 0, width: 4),
      ],
    );

    final delta = stroke.eraseWhere(coordinates: Offset(10, 0), radius: 4);

    expect(delta.affected, isTrue);
    expect(delta.delete, isFalse);
    expect(delta.newContent, hasLength(2));

    final firstStroke = delta.newContent[0] as XppStroke;
    final secondStroke = delta.newContent[1] as XppStroke;

    expect(firstStroke.points!.map((point) => point.x), [0]);
    expect(secondStroke.points!.map((point) => point.x), [20]);
  });

  test('stroke offset includes render padding', () {
    final stroke = XppStrokePen(
      points: [
        XppStrokePoint(x: 20, y: 30, width: 10),
        XppStrokePoint(x: 40, y: 50, width: 6),
      ],
    );

    expect(stroke.getOffset(), const Offset(13, 23));
    expect(stroke.bottomRight, const Offset(47, 57));
  });

  test('stroke exposes cached erase bounds', () {
    final stroke = XppStrokePen(
      points: [
        XppStrokePoint(x: 20, y: 30, width: 10),
        XppStrokePoint(x: 40, y: 50, width: 6),
      ],
    );

    expect(stroke.eraseBounds, const Rect.fromLTRB(13, 23, 47, 57));
  });

  test('solid background without a color serializes as white', () {
    final background = XppBackgroundSolidPlain();

    final element = background.toXmlElement();

    expect(element.getAttribute('color'), '#FFFFFFFF');
  });

  test('pdf page sizes are read from metadata', () async {
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(200, 300),
        build: (_) => pw.SizedBox(),
      ),
    );
    document.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(400, 250),
        build: (_) => pw.SizedBox(),
      ),
    );

    final sizes = await pdfPageSizes(XppPickedFile(await document.save()));

    expect(sizes, hasLength(2));
    expect(sizes[0].width, 200);
    expect(sizes[0].height, 300);
    expect(sizes[1].width, 400);
    expect(sizes[1].height, 250);
  });
}
