import 'dart:typed_data';

final Map<String, Uint8List> _cache = {};

Future<Uint8List> readFileBytes(String path) {
  throw UnsupportedError('Reading local file paths is not supported here.');
}

Future<String> writeFileBytes(String path, Uint8List bytes) {
  throw UnsupportedError('Writing local file paths is not supported here.');
}

Future<String?> saveDocumentBytes(Uint8List bytes, {String? fileName}) async {
  return null;
}

Future<bool> persistDocumentAccess(String path, {bool writable = false}) async {
  return false;
}

Future<void> deleteFile(String path) {
  throw UnsupportedError('Deleting local file paths is not supported here.');
}

Future<Uint8List?> readCacheFile(String key) async => _cache[key];

Future<String> writeCacheFile(String key, Uint8List bytes) async {
  _cache[key] = bytes;
  return key;
}

Future<String> writeTemporaryFile(Uint8List bytes, {String? fileName}) {
  throw UnsupportedError(
    'Writing temporary local files is not supported here.',
  );
}
