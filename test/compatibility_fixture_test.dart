import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppPickedFile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'S4: a checked-in multi-layer interoperability fixture round-trips',
    () async {
      final xml = await File(
        'test/fixtures/interop_synthetic.xml',
      ).readAsString();
      final picked = XppPickedFile(
        Uint8List.fromList(const GZipEncoder().encode(utf8.encode(xml))),
        fileName: 'interop_synthetic.xopp',
      );
      Future<XppFile> read(XppPickedFile input) => XppFile.fromXppPickedFile(
        input,
        null,
        (_, __) => throw StateError('No PDF read required'),
      );

      final file = await read(picked);
      expect(file.pages, hasLength(3));
      expect(file.pages!.first.layers, hasLength(2));
      expect(file.pages!.first.background, isA<XppBackgroundPreserved>());
      final content = file.pages!.first.layers!.first.content!;
      expect((content.first as XppText).text, 'A & B &amp; < C Ω');
      expect(
        (file.pages![1].background as XppBackgroundPdf).domain,
        XppBackgroundImageDomain.ATTACH,
      );
      expect(
        (file.pages![2].background as XppBackgroundPdf).filename,
        'source.pdf',
      );

      final serialized = await file.toUint8ListAsync();
      final roundTripped = await read(XppPickedFile(serialized));
      expect(roundTripped.pages!.first.layers, hasLength(2));
      expect(
        (roundTripped.pages!.first.layers!.first.content!.first as XppText)
            .text,
        'A & B &amp; < C Ω',
      );
      expect(
        utf8.decode(const GZipDecoder().decodeBytes(serialized)),
        contains('custom="preserve-this"'),
      );
    },
  );
}
