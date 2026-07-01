import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();

Future<String> writeFileBytes(String path, Uint8List bytes) async {
  final file = await _writableFileForPath(path);
  await file.writeAsBytes(bytes);
  return file.path;
}

Future<void> deleteFile(String path) => File(path).delete();

Future<String> writeTemporaryFile(Uint8List bytes, {String? fileName}) async {
  final directory = await Directory.systemTemp.createTemp('xournalpp_mobile_');
  final safeName = (fileName == null || fileName.isEmpty)
      ? 'background.pdf'
      : fileName.replaceAll(RegExp(r'[/\\]'), '_');
  final path = '${directory.path}/$safeName';
  await File(path).writeAsBytes(bytes);
  return path;
}

Future<File> _writableFileForPath(String path) async {
  final file = File(path);
  if (file.isAbsolute || !Platform.isAndroid) return file.absolute;

  final directory = await getApplicationDocumentsDirectory();
  final safeName = path.replaceAll(RegExp(r'[/\\]'), '_');
  return File('${directory.path}/$safeName');
}
