import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();

Future<void> writeFileBytes(String path, Uint8List bytes) =>
    File(path).writeAsBytes(bytes);

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
