import 'dart:io';
import 'dart:typed_data';

import 'package:xournalpp/src/XppPickedFile.dart';

XppPickedFile openFileByUri(String url, String extension) {
  Uint8List bytes = File(url).readAsBytesSync();
  return (XppPickedFile(bytes, path: url, fileExtension: extension));
}
