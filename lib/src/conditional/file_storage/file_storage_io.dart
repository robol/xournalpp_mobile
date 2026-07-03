import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _storageChannel = MethodChannel('it.robol.xournal.mobile/storage');

Future<Uint8List> readFileBytes(String path) async {
  final documentUri = _androidDocumentUriForPath(path);
  if (documentUri != null) {
    final bytes = await _storageChannel.invokeMethod<Uint8List>(
      'readDocument',
      {'uri': documentUri},
    );
    if (bytes == null) {
      throw FileSystemException('Could not read document', path);
    }
    return bytes;
  }

  return File(path).readAsBytes();
}

Future<String> writeFileBytes(String path, Uint8List bytes) async {
  final documentUri = _androidDocumentUriForPath(path);
  if (documentUri != null) {
    await _storageChannel.invokeMethod<void>('writeDocument', {
      'uri': documentUri,
      'bytes': bytes,
    });
    return path;
  }

  final file = await _writableFileForPath(path);
  await file.writeAsBytes(bytes);
  return file.path;
}

Future<String?> saveDocumentBytes(Uint8List bytes, {String? fileName}) async {
  if (!Platform.isAndroid) return null;

  return _storageChannel.invokeMethod<String>('createDocument', {
    'fileName': fileName ?? 'xournalpp-export',
    'bytes': bytes,
  });
}

Future<bool> persistDocumentAccess(String path, {bool writable = false}) async {
  final documentUri = _androidDocumentUriForPath(path);
  if (documentUri == null) return false;

  return await _storageChannel.invokeMethod<bool>('persistDocumentAccess', {
        'uri': documentUri,
        'writable': writable,
      }) ??
      false;
}

Future<void> deleteFile(String path) => File(path).delete();

Future<Uint8List?> readCacheFile(String key) async {
  final file = await _cacheFile(key);
  if (!await file.exists()) return null;
  return file.readAsBytes();
}

Future<String> writeCacheFile(String key, Uint8List bytes) async {
  final file = await _cacheFile(key);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: false);
  return file.path;
}

Future<String> writeTemporaryFile(Uint8List bytes, {String? fileName}) async {
  final directory = await Directory.systemTemp.createTemp('xournalpp_mobile_');
  final safeName = (fileName == null || fileName.isEmpty)
      ? 'background.pdf'
      : fileName.replaceAll(RegExp(r'[/\\]'), '_');
  final path = '${directory.path}/$safeName';
  await File(path).writeAsBytes(bytes);
  return path;
}

Future<File> _cacheFile(String key) async {
  final directory = await getTemporaryDirectory();
  return File('${directory.path}/xournalpp_mobile_pdf_cache/$key');
}

Future<File> _writableFileForPath(String path) async {
  final file = File(path);
  if (!Platform.isAndroid) return file.absolute;
  if (file.isAbsolute && file.parent.path != '/') {
    return file;
  }

  final directory = await getApplicationDocumentsDirectory();
  final safeName = _safeFileName(path);
  return File('${directory.path}/$safeName');
}

String _safeFileName(String path) {
  final parts = path
      .split(RegExp(r'[/\\]'))
      .where((part) => part.isNotEmpty)
      .toList();
  return parts.isEmpty ? 'xournalpp-file' : parts.last;
}

String? _androidDocumentUriForPath(String path) {
  if (!Platform.isAndroid) return null;
  if (path.startsWith('content://')) return path;

  const marker = 'primary:';
  final markerIndex = path.indexOf(marker);
  if (markerIndex < 0) return null;

  var documentId = path.substring(markerIndex).replaceAll('\\', '/');
  while (documentId.startsWith('/')) {
    documentId = documentId.substring(1);
  }
  if (documentId == marker) return null;

  return Uri(
    scheme: 'content',
    host: 'com.android.externalstorage.documents',
    pathSegments: ['document', documentId],
  ).toString();
}
