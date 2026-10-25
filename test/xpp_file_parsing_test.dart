import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/XppFile.dart';
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
}
