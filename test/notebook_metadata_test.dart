import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/src/NotebookMetadata.dart';

Uint8List notebook(String xml) =>
    Uint8List.fromList(const GZipEncoder().encode(utf8.encode(xml)));

void main() {
  test(
    'reads escaped root metadata without parsing the rest of the document',
    () {
      final bytes = notebook(
        '<?xml version="1.0"?><xournal xournalpp-mobile-pdf-map="map&amp;name"><page/></xournal>',
      );
      expect(
        notebookRootAttribute(bytes, 'xournalpp-mobile-pdf-map'),
        'map&name',
      );
      expect(notebookRootAttribute(bytes, 'missing'), isNull);
    },
  );
  test('rejects a missing or incorrect root', () {
    expect(
      () => notebookRootAttribute(notebook('<other/>'), 'map'),
      throwsFormatException,
    );
    expect(
      () => notebookRootAttribute(notebook(''), 'map'),
      throwsFormatException,
    );
  });
}
