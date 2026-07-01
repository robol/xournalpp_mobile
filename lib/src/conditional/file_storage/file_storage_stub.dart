import 'dart:typed_data';

Future<Uint8List> readFileBytes(String path) {
  throw UnsupportedError('Reading local file paths is not supported here.');
}

Future<String> writeFileBytes(String path, Uint8List bytes) {
  throw UnsupportedError('Writing local file paths is not supported here.');
}

Future<String?> saveDocumentBytes(Uint8List bytes, {String? fileName}) async {
  return null;
}

Future<void> deleteFile(String path) {
  throw UnsupportedError('Deleting local file paths is not supported here.');
}

Future<String> writeTemporaryFile(Uint8List bytes, {String? fileName}) {
  throw UnsupportedError(
    'Writing temporary local files is not supported here.',
  );
}
