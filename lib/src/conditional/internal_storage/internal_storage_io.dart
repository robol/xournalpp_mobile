import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

@visibleForTesting
String? debugInternalDirectory;

Future<Directory> _directory() async {
  final path =
      debugInternalDirectory ??
      '${(await getApplicationSupportDirectory()).path}/internal_notebooks';
  return Directory(path).create(recursive: true);
}

/// Coordinate staging, publication and garbage collection across app processes.
Future<T> withInternalLock<T>(Future<T> Function() action) async {
  final lock = await File(
    '${(await _directory()).path}/.lock',
  ).open(mode: FileMode.append);
  try {
    await lock.lock();
    try {
      return await action();
    } finally {
      await lock.unlock();
    }
  } finally {
    await lock.close();
  }
}

String _safeName(String name) {
  if (!RegExp(r'^(?:[a-f0-9]{32}\.json|[a-f0-9]{64}\.blob)$').hasMatch(name)) {
    throw const FormatException('Invalid internal storage filename');
  }
  return name;
}

Future<List<String>> listInternalFiles() async => [
  await for (final item in (await _directory()).list())
    if (item is File &&
        RegExp(r'^[a-f0-9]{32}\.json$').hasMatch(item.uri.pathSegments.last))
      item.uri.pathSegments.last.substring(0, 32),
];
Future<List<String>> listInternalBlobs() async => [
  await for (final item in (await _directory()).list())
    if (item is File &&
        RegExp(r'^[a-f0-9]{64}\.blob$').hasMatch(item.uri.pathSegments.last))
      item.uri.pathSegments.last,
];
Future<Uint8List> readInternalFile(String name) async =>
    File('${(await _directory()).path}/${_safeName(name)}').readAsBytes();
Future<void> writeInternalFile(String name, Uint8List data) async {
  final file = File('${(await _directory()).path}/${_safeName(name)}');
  final temp = File('${file.path}.tmp');
  await temp.writeAsBytes(data, flush: true);
  await temp.rename(file.path);
}

Future<void> deleteInternalFile(String name) async {
  final file = File('${(await _directory()).path}/${_safeName(name)}');
  if (!await file.exists())
    throw FileSystemException('Internal file not found', name);
  await file.delete();
}
