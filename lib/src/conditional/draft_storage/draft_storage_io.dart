import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

@visibleForTesting
String? debugDraftDirectory;

Future<Directory> _directory() async {
  if (debugDraftDirectory != null) {
    return Directory(debugDraftDirectory!).create(recursive: true);
  }
  final root = await getApplicationSupportDirectory();
  return Directory('${root.path}/recovery_drafts').create(recursive: true);
}

String _safeId(String id) {
  if (!RegExp(r'^\d+_\d+$').hasMatch(id))
    throw const FormatException('Invalid draft id');
  return id;
}

Future<void> writeDraft(String id, String data) async {
  final dir = await _directory();
  final path = '${dir.path}/${_safeId(id)}.json';
  final temp = File('$path.tmp');
  await temp.writeAsString(data, flush: true);
  await temp.rename(path);
}

Future<void> deleteDraft(String id) async {
  final dir = await _directory();
  final file = File('${dir.path}/${_safeId(id)}.json');
  if (await file.exists()) await file.delete();
}

Future<List<String>> listDrafts() async {
  final dir = await _directory();
  final files = await dir
      .list()
      .where((item) => item is File && item.path.endsWith('.json'))
      .cast<File>()
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  final records = <String>[];
  for (final file in files) {
    try {
      records.add(await file.readAsString());
    } on FileSystemException {
      /* Preserve unreadable drafts. */
    }
  }
  return records;
}
