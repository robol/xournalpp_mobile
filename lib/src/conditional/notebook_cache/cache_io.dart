import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

String? debugCacheDirectory;

Future<Directory> _root() async {
  final path =
      debugCacheDirectory ??
      '${(await getApplicationSupportDirectory()).path}/notebook_cache';
  return Directory(path).create(recursive: true);
}

Future<Uint8List?> readCacheFile(String key) async {
  final file = File('${(await _root()).path}/$key');
  return await file.exists() ? file.readAsBytes() : null;
}

Future<void> writeCacheFile(String key, Uint8List bytes) async {
  final file = File('${(await _root()).path}/$key');
  final temp = File('${file.path}.tmp');
  await temp.writeAsBytes(bytes, flush: true);
  await temp.rename(file.path);
}

Future<List<String>> cacheFiles() async => [
  await for (final item in (await _root()).list())
    if (item is File) item.uri.pathSegments.last,
];

Future<void> deleteCacheFile(String key) async {
  final file = File('${(await _root()).path}/$key');
  if (await file.exists()) await file.delete();
}
