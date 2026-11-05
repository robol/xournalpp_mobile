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
  test(
    'PDF 1.7 classic-only source keeps a classic incremental table',
    () async {
      final source = Uint8List.fromList(
        latin1.encode(
          latin1.decode(_minimalPdf()).replaceFirst('%PDF-1.4', '%PDF-1.7'),
        ),
      );
      final exported = await exportPdfDocument(
        _pdfBackedFile(await _writePdf(source)),
      );
      expect(
        latin1.decode(exported).substring(_lastXref(exported)),
        startsWith('xref\n'),
      );
    },
  );

  for (final compressed in [false, true]) {
    test(
      'stream output and repeated export with compressed objects: $compressed',
      () async {
        final source = _xrefStreamPdf(useObjectStream: compressed);
        final first = await exportPdfDocument(
          _pdfBackedFile(await _writePdf(source)),
        );
        _checkStreamRevision(source, first);
        final second = await exportPdfDocument(
          _pdfBackedFile(await _writePdf(first)),
        );
        _checkStreamRevision(first, second);
      },
    );
  }
  test(
    'hybrid references and mixed revision chains retain stream output',
    () async {
      for (final hybrid in [false, true]) {
        final source = _classicTail(
          _xrefStreamPdf(useObjectStream: true),
          hybrid: hybrid,
        );
        _checkStreamRevision(
          source,
          await exportPdfDocument(_pdfBackedFile(await _writePdf(source))),
        );
      }
    },
  );
  test(
    'linearized source retains final startxref rather than last physical section',
    () async {
      final source = Uint8List.fromList(
        await File('test/fixtures/linearized-xref-stream.pdf').readAsBytes(),
      );
      final text = latin1.decode(source);
      expect(text, contains('/Linearized'));
      expect(_lastXref(source), lessThan(text.lastIndexOf('/Type /XRef')));
      _checkStreamRevision(
        source,
        await exportPdfDocument(_pdfBackedFile(await _writePdf(source))),
      );
    },
  );
  final qpdf = Platform.environment['PDF_EXPORT_QPDF'] ?? 'qpdf';
  final gs = Platform.environment['PDF_EXPORT_GS'] ?? 'gs';
  final missing = [
    for (final tool in [qpdf, gs])
      if (!_toolAvailable(tool)) tool,
  ];
  test(
    'independent qpdf and Ghostscript validation and rendering over two exports',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'xpp-independent-',
      );
      addTearDown(() => directory.delete(recursive: true));
      var source = Uint8List.fromList(
        await File('test/fixtures/linearized-xref-stream.pdf').readAsBytes(),
      );
      for (var revision = 0; revision < 3; revision++) {
        final input = File(directory.path + '/revision-$revision.pdf');
        await input.writeAsBytes(source);
        final check = await Process.run(qpdf, ['--check', input.path]);
        expect(
          check.exitCode,
          0,
          reason: check.stdout.toString() + check.stderr.toString(),
        );
        final render = await Process.run(gs, [
          '-q',
          '-dBATCH',
          '-dNOPAUSE',
          '-sDEVICE=pngalpha',
          '-r72',
          '-sOutputFile=' + directory.path + '/$revision-%d.png',
          input.path,
        ]);
        expect(render.exitCode, 0, reason: render.stderr.toString());
        expect(
          render.stdout.toString() + render.stderr.toString(),
          isNot(
            matches(
              RegExp(r'repair|recover|warning|error', caseSensitive: false),
            ),
          ),
        );
        for (var page = 1; page <= 2; page++) {
          final raster = img.decodePng(
            await File(directory.path + '/$revision-$page.png').readAsBytes(),
          )!;
          var green = 0;
          var blue = 0;
          for (final pixel in raster) {
            if (pixel.g > 100 && pixel.r < 80 && pixel.b < 80) green++;
            if (pixel.b > 100 && pixel.r < 80 && pixel.g < 100) blue++;
          }
          expect(green, greaterThan(1000));
          if (revision > 0) expect(blue, greaterThan(20));
        }
        if (revision == 2) break;
        List<XppStroke> ink() => revision == 0
            ? [
                XppStrokePen(
                  color: const Color(0xff0000ff),
                  points: [
                    XppStrokePoint(x: 20, y: 30, width: 3),
                    XppStrokePoint(x: 110, y: 90, width: 3),
                  ],
                ),
              ]
            : [];
        final notebook = _pdfBackedFile(input.path, content: ink());
        notebook.pages!.add(
          XppPage(
            pageSize: XppPageSize(width: 200, height: 200),
            background: XppBackgroundPdf(
              filename: input.path,
              page: 2,
              onUnavailable: (_, __) async => throw StateError('fixture'),
            ),
            layers: [XppLayer(content: ink())],
          ),
        );
        final output = await exportPdfDocument(notebook);
        _checkStreamRevision(source, output);
        source = output;
      }
    },
    skip: missing.isEmpty
        ? false
        : 'Independent PDF tools unavailable: ' + missing.join(', '),
  );

  for (final xml in [
    '<background type="pixmap" domain="absolute" filename="image.png" custom="keep"/>',
    '<background type="pixmap" domain="attach" filename="image.png"/>',
    '<background type="pixmap" domain="clone" filename="0"/>',
    '<background type="image" filename="image.png"/>',
    '<background type="future-background" custom="keep"/>',
    '<background type="solid" style="future-style" color="#ffffff"/>',
    '<background custom="missing-type"/>',
  ]) {
    test('PDF refuses preserved background and .xopp retains it: $xml', () async {
      Future<XppFile> parse(Uint8List bytes) => XppFile.fromXppPickedFile(
        XppPickedFile(bytes, fileName: 'Preserved.xopp'),
        null,
        (_, _) => throw StateError('No PDF read expected'),
      );
      final file = await parse(
        Uint8List.fromList(
          const GZipEncoder().encode(
            utf8.encode(
              '<xournal><page width="200" height="300">$xml<layer/></page></xournal>',
            ),
          ),
        ),
      );
      final background = file.pages!.single.background;
      expect(background, isA<XppBackgroundPreserved>());
      final originalXml = background!.toXmlElement().toXmlString();
      file.pages!.single.layers!.single.content!.add(
        XppText(text: 'Annotation', offset: const Offset(10, 10), size: 12),
      );
      await expectLater(
        exportPdfDocument(file),
        throwsA(
          isA<PdfExportException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Page 1'),
              contains('unsupported'),
              contains('.xopp'),
            ),
          ),
        ),
      );
      // Refusing PDF export must leave both the background XML and edits intact.
      final reopened = await parse(await file.toUint8ListAsync());
      expect(
        reopened.pages!.single.background!.toXmlElement().toXmlString(),
        originalXml,
      );
      expect(
        (reopened.pages!.single.layers!.single.content!.single as XppText).text,
        'Annotation',
      );
      file.pages!.insert(0, _pdfBackedFile('unread-source.pdf').pages!.first);
      var reads = 0;
      await expectLater(
        exportPdfDocument(
          file,
          pdfResolver: (_) async {
            reads++;
            throw StateError(
              'Preflight must run before resolving PDF resources',
            );
          },
        ),
        throwsA(
          isA<PdfExportException>().having(
            (e) => e.message,
            'message',
            contains('Page 2'),
          ),
        ),
      );
      expect(reads, 0);
    });
  }
  test('PDF refuses unimplemented image background objects', () async {
    final file = XppFile.empty();
    file.pages!.single.background = XppBackgroundImage(filename: 'image.png');
    await expectLater(
      exportPdfDocument(file),
      throwsA(
        isA<PdfExportException>().having(
          (e) => e.message,
          'message',
          contains('pixmap/image'),
        ),
      ),
    );
  });

  test(
    'generated and classic-source incremental PDF xref offsets point to objects',
    () async {
      final generated = await exportPdfDocument(XppFile.empty());
      final path = await _writePdf(_minimalPdf());
      final incremental = await exportPdfDocument(_pdfBackedFile(path));
      for (final bytes in [generated, incremental]) {
        final text = latin1.decode(bytes);
        final start = RegExp(
          r'startxref\s+(\d+)\s+%%EOF',
        ).allMatches(text).last;
        final offset = int.parse(start.group(1)!);
        expect(text.substring(offset), startsWith('xref\n'));
        final section = text.substring(offset, text.indexOf('trailer', offset));
        final lines = section.split('\n');
        var i = 1;
        while (i < lines.length && lines[i].isNotEmpty) {
          final header = lines[i++].split(' ');
          final first = int.parse(header[0]);
          final count = int.parse(header[1]);
          for (var j = 0; j < count; j++) {
            final entry = lines[i++];
            if (entry[17] != 'n') continue;
            final objectOffset = int.parse(entry.substring(0, 10));
            expect(
              text.substring(objectOffset),
              startsWith('${first + j} 0 obj\n'),
            );
          }
        }
      }
    },
  );
  test('exports opaque filled strokes and rejects translucent fills', () async {
    final file = XppFile.empty();
    final stroke = XppStrokePen(
      color: const Color(0xffff0000),
      points: [
        XppStrokePoint(x: 10, y: 10, width: 1),
        XppStrokePoint(x: 50, y: 10, width: 1),
        XppStrokePoint(x: 50, y: 50, width: 1),
        XppStrokePoint(x: 10, y: 10, width: 1),
      ],
    )..fill = 255;
    file.pages!.first.layers!.last.content!.add(stroke);
    expect(latin1.decode(await exportPdfDocument(file)), contains('h f'));
    stroke.fill = 128;
    await expectLater(
      exportPdfDocument(file),
      throwsA(isA<PdfExportException>()),
    );
  });
  test('PDF generation yields to the calling isolate', () async {
    final file = XppFile.empty();
    var timerRan = false;
    final export = exportPdfDocument(file);
    await Future<void>.delayed(Duration.zero, () => timerRan = true);
    expect(timerRan, isTrue);
    expect(latin1.decode(await export), startsWith('%PDF-'));
  });

  test('F4: export rejects text it cannot encode without data loss', () async {
    final file = XppFile.empty();
    file.pages!.single.layers!.single.content!.add(
      XppText(
        text: 'Greek Ω and Japanese 日本語',
        offset: const Offset(10, 10),
        size: 14,
        color: const Color(0xff000000),
      ),
    );
    await expectLater(
      exportPdfDocument(file),
      throwsA(isA<PdfExportException>()),
    );
  });

  test('F5: unresolved PDF backgrounds never silently disappear', () async {
    final file = XppFile.empty();
    file.pages!.single.background = XppBackgroundPdf(
      onUnavailable: (_, __) => throw StateError('not reachable'),
      page: 1,
    );
    await expectLater(
      exportPdfDocument(file),
      throwsA(isA<PdfExportException>()),
    );
  });

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

  test('F3: transparent images retain a PDF soft mask', () async {
    final png = img.Image(width: 2, height: 1, numChannels: 4)
      ..setPixelRgba(0, 0, 255, 0, 0, 0)
      ..setPixelRgba(1, 0, 0, 255, 0, 255);
    final file = XppFile.empty();
    file.pages!.single.layers!.single.content!.add(
      XppImage(
        data: Uint8List.fromList(img.encodePng(png)),
        topLeft: const Offset(10, 10),
        bottomRight: const Offset(30, 30),
      ),
    );
    final output = latin1.decode(await exportPdfDocument(file));
    expect(output, contains('/SMask'));
    expect(output, contains('/DeviceGray'));
  });

  test('16-bit PNG channels are scaled to PDF 8-bit samples', () async {
    final png = img.Image(
      width: 1,
      height: 1,
      numChannels: 4,
      format: img.Format.uint16,
    )..setPixelRgba(0, 0, 65535, 0, 0, 32768);
    final file = XppFile.empty();
    file.pages!.single.layers!.single.content!.add(
      XppImage(
        data: Uint8List.fromList(img.encodePng(png)),
        topLeft: const Offset(0, 0),
        bottomRight: const Offset(10, 10),
      ),
    );
    final output = latin1.decode(await exportPdfDocument(file));
    expect(
      output,
      contains('stream\n${String.fromCharCodes([128])}\nendstream'),
    );
    expect(
      output,
      contains('stream\n${String.fromCharCodes([255, 0, 0])}\nendstream'),
    );
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
    '<< /Length 30 >>\nstream\nq 1 1 1 rg 0 0 200 200 re f Q\nendstream',
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
    4: '<< /Length 30 >>\nstream\nq 1 1 1 rg 0 0 200 200 re f Q\nendstream',
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
    '<< /Length 30 >>\n'
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

bool _toolAvailable(String executable) {
  try {
    return Process.runSync(executable, ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

int _lastXref(Uint8List bytes) => int.parse(
  RegExp(
    r'startxref\s+(\d+)\s+%%EOF\s*$',
  ).firstMatch(latin1.decode(bytes))!.group(1)!,
);

void _checkStreamRevision(Uint8List source, Uint8List output) {
  expect(output.sublist(0, source.length), source);
  final text = latin1.decode(output);
  final offset = _lastXref(output);
  final header = RegExp(
    r'^(\d+) 0 obj\n(<<.*?>>)\nstream\n',
    dotAll: true,
  ).matchAsPrefix(text.substring(offset))!;
  final self = int.parse(header.group(1)!);
  final dictionary = header.group(2)!;
  expect(dictionary, contains('/Type /XRef'));
  expect(dictionary, contains('/W [1 4 2]'));
  expect(dictionary, contains('/Prev ' + _lastXref(source).toString()));
  for (final key in ['XRefStm', 'Filter', 'DecodeParms']) {
    expect(dictionary, isNot(contains('/$key ')));
  }
  final sourceText = latin1.decode(source);
  for (final key in ['Root', 'Info']) {
    final ref = RegExp('/$key ' + r'(\d+ \d+ R)').firstMatch(sourceText);
    if (ref != null) expect(dictionary, contains('/$key ' + ref.group(1)!));
  }
  final id = RegExp(r'/ID\s*(\[[^\]]*\])').firstMatch(sourceText);
  if (id != null) expect(dictionary, contains('/ID ' + id.group(1)!));
  final index = RegExp(r'/Index \[([^\]]*)\]')
      .firstMatch(dictionary)!
      .group(1)!
      .trim()
      .split(RegExp(r'\s+'))
      .map(int.parse)
      .toList();
  final length = int.parse(
    RegExp(r'/Length (\d+)').firstMatch(dictionary)!.group(1)!,
  );
  final size = int.parse(
    RegExp(r'/Size (\d+)').firstMatch(dictionary)!.group(1)!,
  );
  final expected = <int, int>{};
  for (final object in RegExp(
    r'^(\d+) 0 obj\n',
    multiLine: true,
  ).allMatches(text.substring(source.length))) {
    expected[int.parse(object.group(1)!)] = source.length + object.start;
  }
  expect(expected[self], offset);
  final numbers = <int>[];
  for (var i = 0; i < index.length; i += 2) {
    expect(index[i + 1], greaterThan(0));
    if (numbers.isNotEmpty) expect(index[i], greaterThan(numbers.last));
    numbers.addAll(List.generate(index[i + 1], (j) => index[i] + j));
  }
  expect(numbers, expected.keys.toList()..sort());
  expect(length, numbers.length * 7);
  final data = ByteData.sublistView(
    output,
    offset + header.end,
    offset + header.end + length,
  );
  for (var i = 0; i < numbers.length; i++) {
    expect(data.getUint8(i * 7), 1);
    expect(data.getUint32(i * 7 + 1), expected[numbers[i]]);
    expect(data.getUint16(i * 7 + 5), 0);
  }
  expect(
    text.substring(offset + header.end + length),
    startsWith('\nendstream\nendobj\nstartxref\n$offset\n%%EOF'),
  );
  expect(size, greaterThan(numbers.last));
  for (final m in RegExp(r'/Size (\d+)').allMatches(sourceText)) {
    expect(size, greaterThanOrEqualTo(int.parse(m.group(1)!)));
  }
  expect(text.substring(source.length), isNot(contains('\nxref\n')));
  expect(text.substring(source.length), isNot(contains('\ntrailer\n')));
}

Uint8List _classicTail(Uint8List source, {required bool hybrid}) {
  final buffer = StringBuffer(latin1.decode(source));
  final previous = _lastXref(source);
  final size = int.parse(
    RegExp(r'/Size (\d+)').firstMatch(latin1.decode(source))!.group(1)!,
  );
  final offset = buffer.length;
  final link = hybrid ? '/XRefStm $previous' : '/Prev $previous';
  buffer.write(
    'xref\n0 1\n0000000000 65535 f \ntrailer\n'
    '<< /Size $size /Root 1 0 R $link >>\n'
    'startxref\n$offset\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}
