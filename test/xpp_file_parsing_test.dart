import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppPickedFile.dart';

XppPickedFile notebook(String layerXml, {String? fileName = 'notes.xopp'}) {
  final xml =
      '''<xournal><page width="200" height="300">
    <background type="solid" style="plain" color="#ffffff"/>
    <layer>$layerXml</layer>
  </page></xournal>''';
  final bytes = Uint8List.fromList(GZipEncoder().encode(utf8.encode(xml)));
  return XppPickedFile(
    bytes,
    path: 'content://provider/document/123',
    fileName: fileName,
  );
}

Future<XppFile> parseNotebook(XppPickedFile file) =>
    XppFile.fromXppPickedFile(file, null, (_, __) => throw StateError('PDF'));

void main() {
  test('parses mixed content in order and accepts stroke whitespace', () async {
    final file = await parseNotebook(
      notebook('''
        <text font="Sans" size="12" x="1" y="2" color="#000000">First</text>
        <stroke tool="pen" color="#000000" width="1  2">
          10 20
          30\t40
        </stroke>
        <text font="Sans" size="12" x="3" y="4" color="#000000">Last</text>
      '''),
    );

    expect(file.title, 'notes');
    final content = file.pages!.single.layers!.single.content!;
    expect(content, hasLength(3));
    expect((content[0] as XppText).text, 'First');
    expect((content[1] as XppStroke).points, hasLength(2));
    expect((content[2] as XppText).text, 'Last');
  });

  test(
    'stroke serialization rounds to six significant digits and reloads',
    () async {
      final original = await parseNotebook(
        notebook(
          '''<stroke tool="pen" color="#000000" width="0.123456789 0.000000123456789">
        123.456789 -0.000000123456789 9999.99999 0
      </stroke>''',
        ),
      );
      final stroke =
          original.pages!.single.layers!.single.content!.single as XppStroke;
      final xml = stroke.toXmlElement();
      expect(xml.getAttribute('width'), '0.123457 1.23457e-7');
      expect(xml.children.single.value, '123.457 -1.23457e-7 10000.0 0.0');
      // Saving does not round the in-memory model.
      expect(stroke.points!.first.x, 123.456789);
      final saved = XppPickedFile(
        Uint8List.fromList(
          GZipEncoder().encode(utf8.encode(original.toXmlString())),
        ),
      );
      final reloaded = await parseNotebook(saved);
      final points =
          (reloaded.pages!.single.layers!.single.content!.single as XppStroke)
              .points!;
      expect(points.first.x, 123.457);
      expect(points.first.y, -1.23457e-7);
      expect(points.last.width, 1.23457e-7);
      expect(points.last.x, 10000);
    },
  );

  test('rejects unknown content before a lossy save', () async {
    await expectLater(
      parseNotebook(notebook('<unsupported/><text/>')),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('accepts an extensionless display name', () async {
    final file = await parseNotebook(notebook('', fileName: 'notes'));
    expect(file.title, 'notes');
  });

  testWidgets('PDF inheritance and recovery callback survive parsing', (
    tester,
  ) async {
    const xml = '''<xournal>
      <page width="200" height="300"><background type="pdf" filename="missing.pdf" pageno="1"/><layer/></page>
      <page width="200" height="300"><background type="pdf" pageno="2"/><layer/></page>
    </xournal>''';
    final raw = XppPickedFile(
      Uint8List.fromList(GZipEncoder().encode(utf8.encode(xml))),
    );
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final progress = <double>[];
    String? recoveredPath;
    final file = await tester.runAsync(
      () => XppFile.fromXppPickedFile(raw, progress.add, (_, path) async {
        recoveredPath = path;
        return raw;
      }),
    );
    final first = file!.pages![0].background as XppBackgroundPdf;
    final second = file.pages![1].background as XppBackgroundPdf;
    expect(second.filename, first.filename);
    expect(second.page, 2);
    expect(await second.onUnavailable(context, second.filename), same(raw));
    expect(recoveredPath, 'missing.pdf');
    expect(progress, [1.0]);
  });
}
