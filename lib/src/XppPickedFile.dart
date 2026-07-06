import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'conditional/file_storage/file_storage_stub.dart'
    if (dart.library.io) 'conditional/file_storage/file_storage_io.dart';

enum XppFilePickType { custom, image }

class XppPickedFile {
  XppPickedFile(this.bytes, {this.path, this.fileExtension, String? fileName})
    : fileName = fileName ?? _basename(path);

  final Uint8List bytes;
  final String? path;
  final String? fileExtension;
  final String? fileName;

  Uint8List toUint8List() => bytes;

  static Future<XppPickedFile> importFromStorage({
    required XppFilePickType type,
    String? fileExtension,
  }) async {
    final result = await FilePicker.pickFiles(
      type: type == XppFilePickType.image ? FileType.image : FileType.custom,
      allowedExtensions: type == XppFilePickType.custom && fileExtension != null
          ? [fileExtension.replaceFirst('.', '')]
          : null,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) throw UnsupportedError('No file selected.');
    final path = file.identifier ?? file.path;
    if (path != null) {
      await persistDocumentAccess(
        path,
        writable: type == XppFilePickType.custom,
      );
    }
    final bytes =
        file.bytes ?? (path == null ? null : await readFileBytes(path));
    if (bytes == null) throw UnsupportedError('Could not read selected file.');
    return XppPickedFile(
      bytes,
      path: path,
      fileName: file.name,
      fileExtension: file.extension,
    );
  }

  static Future<XppPickedFile> fromInternalPath({required String path}) async {
    return XppPickedFile(
      await readFileBytes(path),
      path: path,
      fileName: _basename(path),
      fileExtension: _extension(path),
    );
  }

  static Future<XppPickedFile> fromExternalPath({
    required String path,
    String? fileName,
    String? fileExtension,
  }) async {
    return XppPickedFile(
      await readFileBytes(path),
      path: path,
      fileName: fileName ?? _basename(path),
      fileExtension: fileExtension ?? _extension(fileName ?? path),
    );
  }

  Future<String?> exportToStorage() async {
    final savedDocumentPath = await saveDocumentBytes(
      bytes,
      fileName: fileName ?? 'xournalpp-export',
    );
    if (savedDocumentPath != null) return savedDocumentPath;

    final savedPath = await FilePicker.saveFile(
      fileName: fileName ?? 'xournalpp-export',
      bytes: bytes,
    );
    return savedPath;
  }

  Future<String> saveToPath({required String path}) async {
    return writeFileBytes(path, bytes);
  }

  Future<String> saveToTemporaryPath() {
    return writeTemporaryFile(bytes, fileName: fileName);
  }

  static Future<void> delete({required String path}) => deleteFile(path);

  static String? _basename(String? path) {
    if (path == null || path.isEmpty) return null;
    return _decodePathForDisplay(path).split(RegExp(r'[/\\]')).last;
  }

  static String? _extension(String? path) {
    final name = _basename(path);
    final dot = name?.lastIndexOf('.') ?? -1;
    if (name == null || dot < 0 || dot == name.length - 1) return null;
    return name.substring(dot + 1);
  }

  static String _decodePathForDisplay(String path) {
    try {
      return Uri.decodeFull(path);
    } on FormatException {
      return path;
    }
  }
}
