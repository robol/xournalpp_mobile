import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml_events.dart';

/// Read a root attribute without constructing a second document tree.
String? notebookRootAttribute(Uint8List bytes, String attribute) {
  final text = utf8.decode(const GZipDecoder().decodeBytes(bytes));
  for (final event in parseEvents(text)) {
    if (event is XmlStartElementEvent) {
      if (event.name != 'xournal') {
        throw const FormatException('Invalid Xournal notebook root');
      }
      for (final item in event.attributes) {
        if (item.name == attribute) return item.value;
      }
      return null;
    }
  }
  throw const FormatException('Missing Xournal notebook root');
}
