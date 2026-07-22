import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/PdfExporter.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPickedFile.dart';

void main() {
  test('exportPdfDocument appends vector overlay update', () async {
    final pdfPath = await _writePdf(_minimalPdf());
    final file = _pdfBackedFile(
      pdfPath,
      content: [
        XppStrokePen(
          color: const Color(0xff336699),
          points: [
            XppStrokePoint(x: 10, y: 20, width: 2),
            XppStrokePoint(x: 80, y: 90, width: 4),
          ],
        ),
        XppStrokeHighlight(
          color: const Color(0xffffff00),
          points: [
            XppStrokePoint(x: 20, y: 40, width: 8),
            XppStrokePoint(x: 120, y: 40, width: 8),
          ],
        ),
        XppText(
          text: 'Hello PDF',
          offset: const Offset(30, 60),
          size: 14,
          color: const Color(0xff000000),
        ),
      ],
    );

    final exported = await exportPdfDocument(file);
    final text = latin1.decode(exported);

    expect(exported.length, greaterThan(_minimalPdf().length));
    expect(text, startsWith('%PDF-1.4'));
    expect(text, contains('/Prev'));
    expect(text, contains(_isolatedContentsPattern()));
    expect(text, isNot(contains(RegExp(r'/Resources\d'))));
    expect(text, contains(RegExp(r'/Resources \d+ 0 R')));
    expect(text, contains('/FXPHelvetica'));
    expect(text, contains('/FXPHighlight'));
    expect(text, contains('(Hello PDF) Tj'));
  });

  test('exportPdfDocument writes image XObjects', () async {
    final pdfPath = await _writePdf(_minimalPdf());
    final png = img.encodePng(
      img.Image(width: 1, height: 1)..setPixelRgb(0, 0, 255, 0, 0),
    );
    final file = _pdfBackedFile(
      pdfPath,
      content: [
        XppImage(
          data: Uint8List.fromList(png),
          topLeft: const Offset(10, 10),
          bottomRight: const Offset(30, 30),
        ),
      ],
    );

    final exported = await exportPdfDocument(file);
    final text = latin1.decode(exported);

    expect(text, contains('/Subtype /Image'));
    expect(text, contains('/XObject'));
    expect(text, contains('/FXPIm1'));
  });

  test('exportPdfDocument can resolve a missing source PDF', () async {
    final validPdfPath = await _writePdf(_minimalPdf());
    final file = _pdfBackedFile('/missing/source.pdf');

    final exported = await exportPdfDocument(
      file,
      pdfResolver: (_) => _pickedPdf(validPdfPath),
    );

    expect(latin1.decode(exported), contains('/Prev'));
  });

  test('exportPdfDocument supports classic xref Prev chains', () async {
    final pdfPath = await _writePdf(_incrementallyUpdatedPdf());
    final file = _pdfBackedFile(
      pdfPath,
      content: [
        XppStrokePen(
          color: const Color(0xff336699),
          points: [
            XppStrokePoint(x: 10, y: 20, width: 2),
            XppStrokePoint(x: 80, y: 90, width: 2),
          ],
        ),
      ],
    );

    final exported = await exportPdfDocument(file);
    final text = latin1.decode(exported);

    expect(text, contains('/Prev'));
    expect(text, contains('/Info 5 0 R'));
    expect(text, contains(_isolatedContentsPattern()));
    expect(text, contains('/ProcSet [/PDF]'));
    expect(text, contains('/FXPHelvetica'));
  });

  test('exportPdfDocument supports xref streams', () async {
    final pdfPath = await _writePdf(_xrefStreamPdf());
    final file = _pdfBackedFile(
      pdfPath,
      content: [
        XppStrokePen(
          color: const Color(0xff336699),
          points: [
            XppStrokePoint(x: 10, y: 20, width: 2),
            XppStrokePoint(x: 80, y: 90, width: 2),
          ],
        ),
      ],
    );

    final exported = await exportPdfDocument(file);
    final text = latin1.decode(exported);

    expect(text, contains('/Prev'));
    expect(text, contains(_isolatedContentsPattern()));
    expect(text, contains('/FXPHelvetica'));
  });

  test('exportPdfDocument supports xref streams with object streams', () async {
    final pdfPath = await _writePdf(_xrefStreamPdf(useObjectStream: true));
    final file = _pdfBackedFile(
      pdfPath,
      content: [
        XppStrokePen(
          color: const Color(0xff336699),
          points: [
            XppStrokePoint(x: 10, y: 20, width: 2),
            XppStrokePoint(x: 80, y: 90, width: 2),
          ],
        ),
      ],
    );

    final exported = await exportPdfDocument(file);
    final text = latin1.decode(exported);

    expect(text, contains('/Prev'));
    expect(text, contains(_isolatedContentsPattern()));
    expect(text, contains('/FXPHelvetica'));
  });

  test('exportPdfDocument isolates source page graphics state', () async {
    final pdfPath = await _writePdf(_leakyTransformPdf());
    final file = _pdfBackedFile(
      pdfPath,
      content: [
        XppStrokePen(
          color: const Color(0xff336699),
          points: [
            XppStrokePoint(x: 10, y: 20, width: 2),
            XppStrokePoint(x: 80, y: 90, width: 2),
          ],
        ),
      ],
    );

    final exported = await exportPdfDocument(file);
    final text = latin1.decode(exported);

    expect(text, contains('1 0 0 -1 0 200 cm'));
    expect(text, contains('10 180 m 80 110 l S'));
    expect(text, contains(_isolatedContentsPattern()));
    expect(text, contains('stream\nq\nendstream'));
    expect(text, contains('stream\nQ\nendstream'));
  });

  test('exportPdfDocument exports non-PDF-backed notebooks', () async {
    final file = XppFile(
      title: 'plain',
      pages: [
        XppPage(
          pageSize: XppPageSize(width: 200, height: 200),
          background: XppBackgroundSolidGraph(
            size: XppPageSize(width: 200, height: 200),
          ),
          layers: [
            XppLayer(
              content: [
                XppText(
                  text: 'Plain page',
                  offset: const Offset(20, 40),
                  size: 14,
                  color: const Color(0xff000000),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final exported = await exportPdfDocument(file);
    final text = latin1.decode(exported);

    expect(text, startsWith('%PDF-1.4'));
    expect(text, contains('/Type /Page'));
    expect(text, contains('/FXPHelvetica'));
    expect(text, contains('(Plain page) Tj'));
    expect(text, isNot(contains('/Prev')));
  });

  test('exportPdfDocument exports mixed PDF and generated pages', () async {
    final pdfPath = await _writePdf(_minimalPdf());
    final file = _pdfBackedFile(pdfPath)
      ..pages!.add(
        XppPage(
          pageSize: XppPageSize(width: 200, height: 200),
          background: XppBackgroundSolidDot(
            size: XppPageSize(width: 200, height: 200),
          ),
          layers: [
            XppLayer(
              content: [
                XppText(
                  text: 'Generated page',
                  offset: const Offset(20, 40),
                  size: 14,
                  color: const Color(0xff000000),
                ),
              ],
            ),
          ],
        ),
      );

    final exported = await exportPdfDocument(file);
    final text = latin1.decode(exported);

    expect(text, startsWith('%PDF-1.4'));
    expect(text, contains('/Prev'));
    expect(text, contains('/Count 2'));
    expect(text, contains(_isolatedContentsPattern()));
    expect(text, contains('(Generated page) Tj'));
  });

  test('exportPdfDocument rejects multiple PDF sources', () async {
    final firstPdfPath = await _writePdf(_minimalPdf());
    final secondPdfPath = await _writePdf(_minimalPdf());
    final file = _pdfBackedFile(firstPdfPath)
      ..pages!.add(
        XppPage(
          pageSize: XppPageSize(width: 200, height: 200),
          background: XppBackgroundPdf(
            filename: secondPdfPath,
            page: 1,
            onUnavailable: (_, __) async => throw StateError('missing fixture'),
          ),
          layers: [XppLayer.empty()],
        ),
      );

    await expectLater(
      exportPdfDocument(file),
      throwsA(
        isA<PdfExportException>().having(
          (error) => error.message,
          'message',
          contains('single source PDF'),
        ),
      ),
    );
  });

  test('exportPdfDocument rejects duplicated PDF source pages', () async {
    final firstPdfPath = await _writePdf(_minimalPdf());
    final file = _pdfBackedFile(firstPdfPath)
      ..pages!.add(
        XppPage(
          pageSize: XppPageSize(width: 200, height: 200),
          background: XppBackgroundPdf(
            filename: firstPdfPath,
            page: 1,
            onUnavailable: (_, __) async => throw StateError('missing fixture'),
          ),
          layers: [XppLayer.empty()],
        ),
      );

    await expectLater(
      exportPdfDocument(file),
      throwsA(
        isA<PdfExportException>().having(
          (error) => error.message,
          'message',
          contains('same source PDF page'),
        ),
      ),
    );
  });

  test('exportPdfDocument rejects encrypted PDFs', () async {
    final pdfPath = await _writePdf(_minimalPdf(encrypted: true));
    final file = _pdfBackedFile(pdfPath);

    await expectLater(
      exportPdfDocument(file),
      throwsA(
        isA<PdfExportException>().having(
          (error) => error.message,
          'message',
          contains('Encrypted'),
        ),
      ),
    );
  });
}

XppFile _pdfBackedFile(String pdfPath, {List<dynamic> content = const []}) {
  return XppFile(
    title: 'sample',
    pages: [
      XppPage(
        pageSize: XppPageSize(width: 200, height: 200),
        background: XppBackgroundPdf(
          filename: pdfPath,
          page: 1,
          onUnavailable: (_, __) async => throw StateError('missing fixture'),
        ),
        layers: [XppLayer(content: content.cast())],
      ),
    ],
  );
}

Future<String> _writePdf(Uint8List bytes) async {
  final directory = await Directory.systemTemp.createTemp('xpp-pdf-export-');
  final file = File('${directory.path}/source.pdf');
  await file.writeAsBytes(bytes);
  return file.path;
}

Future<XppPickedFile> _pickedPdf(String path) async {
  return XppPickedFile.fromInternalPath(path: path);
}

RegExp _isolatedContentsPattern() {
  return RegExp(r'/Contents \[ \d+ 0 R 4 0 R \d+ 0 R \d+ 0 R \]');
}

Uint8List _minimalPdf({bool encrypted = false}) {
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
        '/Resources << >> /Contents 4 0 R >>',
    '<< /Length 31 >>\nstream\nq 1 1 1 rg 0 0 200 200 re f Q\nendstream',
  ];

  for (var i = 0; i < objects.length; i++) {
    offsets.add(latin1.encode(buffer.toString()).length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }

  final xrefOffset = latin1.encode(buffer.toString()).length;
  buffer.write('xref\n0 ${objects.length + 1}\n');
  buffer.write('0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n');
  buffer.write(
    '<< /Size ${objects.length + 1} /Root 1 0 R'
    '${encrypted ? ' /Encrypt 5 0 R' : ''} >>\n',
  );
  buffer.write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

Uint8List _leakyTransformPdf() {
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
        '/Resources << >> /Contents 4 0 R >>',
    '<< /Length 48 >>\n'
        'stream\n'
        '1 0 0 -1 0 200 cm\n'
        'q 1 1 1 rg 0 0 200 200 re f Q\n'
        'endstream',
  ];

  for (var i = 0; i < objects.length; i++) {
    offsets.add(latin1.encode(buffer.toString()).length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }

  final xrefOffset = latin1.encode(buffer.toString()).length;
  buffer.write('xref\n0 ${objects.length + 1}\n');
  buffer.write('0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n');
  buffer.write('<< /Size ${objects.length + 1} /Root 1 0 R >>\n');
  buffer.write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

Uint8List _incrementallyUpdatedPdf() {
  final base = latin1.decode(_minimalPdf());
  final previousXrefOffset = RegExp(
    r'startxref\s+(\d+)\s+%%EOF\s*$',
    dotAll: true,
  ).firstMatch(base)!.group(1)!;
  final buffer = StringBuffer(base);

  final updatedPageOffset = latin1.encode(buffer.toString()).length;
  buffer.write(
    '3 0 obj\n'
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
    '/Resources << /ProcSet [/PDF] >> /Contents 4 0 R >>\n'
    'endobj\n',
  );
  final infoOffset = latin1.encode(buffer.toString()).length;
  buffer.write('5 0 obj\n<< /Producer (incremental fixture) >>\nendobj\n');

  final xrefOffset = latin1.encode(buffer.toString()).length;
  buffer.write('xref\n');
  buffer.write('3 1\n');
  buffer.write('${updatedPageOffset.toString().padLeft(10, '0')} 00000 n \n');
  buffer.write('5 1\n');
  buffer.write('${infoOffset.toString().padLeft(10, '0')} 00000 n \n');
  buffer.write('trailer\n');
  buffer.write(
    '<< /Size 6 /Root 1 0 R /Info 5 0 R /Prev $previousXrefOffset >>\n',
  );
  buffer.write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

Uint8List _xrefStreamPdf({bool useObjectStream = false}) {
  return useObjectStream
      ? _xrefStreamPdfWithObjectStream()
      : _plainXrefStreamPdf();
}

Uint8List _plainXrefStreamPdf() {
  final buffer = StringBuffer('%PDF-1.5\n');
  final offsets = <int, int>{};
  final objects = <int, String>{
    1: '<< /Type /Catalog /Pages 2 0 R >>',
    2: '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    3:
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
        '/Resources << >> /Contents 4 0 R >>',
    4: '<< /Length 31 >>\nstream\nq 1 1 1 rg 0 0 200 200 re f Q\nendstream',
  };

  objects.forEach((objectNumber, body) {
    offsets[objectNumber] = latin1.encode(buffer.toString()).length;
    buffer.write('$objectNumber 0 obj\n$body\nendobj\n');
  });

  final xrefOffset = latin1.encode(buffer.toString()).length;
  final stream = _xrefStreamEntries(
    size: 6,
    uncompressedOffsets: {...offsets, 5: xrefOffset},
  );
  final compressed = const ZLibEncoder().encodeBytes(stream);
  buffer.write(
    '5 0 obj\n'
    '<< /Type /XRef /Size 6 /Root 1 0 R /W [1 4 2] /Index [0 6] '
    '/Filter /FlateDecode /Length ${compressed.length} >>\n'
    'stream\n${latin1.decode(compressed)}\nendstream\n'
    'endobj\n'
    'startxref\n$xrefOffset\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

Uint8List _xrefStreamPdfWithObjectStream() {
  final buffer = StringBuffer('%PDF-1.5\n');

  final contentOffset = latin1.encode(buffer.toString()).length;
  buffer.write(
    '4 0 obj\n'
    '<< /Length 31 >>\n'
    'stream\nq 1 1 1 rg 0 0 200 200 re f Q\nendstream\n'
    'endobj\n',
  );

  final compressedObjects = <int, String>{
    1: '<< /Type /Catalog /Pages 2 0 R >>',
    2: '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    3:
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
        '/Resources << >> /Contents 4 0 R >>',
  };
  final objectStreamHeader = StringBuffer();
  final objectStreamBodies = StringBuffer();
  final compressedRefs = <int, int>{};
  var objectIndex = 0;
  compressedObjects.forEach((objectNumber, body) {
    compressedRefs[objectNumber] = objectIndex++;
    objectStreamHeader.write(
      '$objectNumber ${latin1.encode(objectStreamBodies.toString()).length} ',
    );
    objectStreamBodies.write('$body\n');
  });
  final objectStreamData =
      '${objectStreamHeader.toString()}${objectStreamBodies.toString()}';
  final objectStreamOffset = latin1.encode(buffer.toString()).length;
  buffer.write(
    '5 0 obj\n'
    '<< /Type /ObjStm /N ${compressedObjects.length} '
    '/First ${latin1.encode(objectStreamHeader.toString()).length} '
    '/Length ${latin1.encode(objectStreamData).length} >>\n'
    'stream\n$objectStreamData\nendstream\n'
    'endobj\n',
  );

  final xrefOffset = latin1.encode(buffer.toString()).length;
  final stream = _xrefStreamEntries(
    size: 7,
    uncompressedOffsets: {
      4: contentOffset,
      5: objectStreamOffset,
      6: xrefOffset,
    },
    compressedRefs: compressedRefs,
  );
  final compressed = const ZLibEncoder().encodeBytes(stream);
  buffer.write(
    '6 0 obj\n'
    '<< /Type /XRef /Size 7 /Root 1 0 R /W [1 4 2] /Index [0 7] '
    '/Filter /FlateDecode /Length ${compressed.length} >>\n'
    'stream\n${latin1.decode(compressed)}\nendstream\n'
    'endobj\n'
    'startxref\n$xrefOffset\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

Uint8List _xrefStreamEntries({
  required int size,
  required Map<int, int> uncompressedOffsets,
  Map<int, int> compressedRefs = const {},
}) {
  final bytes = BytesBuilder();
  for (var objectNumber = 0; objectNumber < size; objectNumber++) {
    final uncompressedOffset = uncompressedOffsets[objectNumber];
    final compressedIndex = compressedRefs[objectNumber];
    if (objectNumber == 0 ||
        (uncompressedOffset == null && compressedIndex == null)) {
      bytes.add([0, 0, 0, 0, 0, 0xff, 0xff]);
    } else if (uncompressedOffset != null) {
      bytes.add([1, ..._uintBytes(uncompressedOffset, 4), 0, 0]);
    } else {
      bytes.add([2, ..._uintBytes(5, 4), ..._uintBytes(compressedIndex!, 2)]);
    }
  }
  return bytes.toBytes();
}

List<int> _uintBytes(int value, int width) {
  return [
    for (var shift = (width - 1) * 8; shift >= 0; shift -= 8)
      (value >> shift) & 0xff,
  ];
}
