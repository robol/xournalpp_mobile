import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/src/XppPickedFile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FilePickerPlatform original;
  late _Picker picker;

  setUp(() {
    original = FilePickerPlatform.instance;
    picker = _Picker();
    FilePickerPlatform.instance = picker;
  });
  tearDown(() => FilePickerPlatform.instance = original);

  test('imports bytes and decodes local file paths', () async {
    picker.file = _File(Uri.file('/tmp/my notes.xopp'));
    final file = await XppPickedFile.importFromStorage(
      type: XppFilePickType.custom,
      fileExtension: '.xopp',
    );
    expect(file.bytes, [1, 2, 3]);
    expect(file.path, '/tmp/my notes.xopp');
    expect(file.fileName, 'my notes.xopp');
    expect(file.fileExtension, 'xopp');
    expect(picker.type, FileType.custom);
    expect(picker.extensions, ['xopp']);
  });

  test('preserves content URIs for subsequent document access', () async {
    final uri = Uri.parse('content://provider/document/primary%3Anotes.xopp');
    picker.file = _File(uri);
    final file = await XppPickedFile.importFromStorage(
      type: XppFilePickType.custom,
    );
    expect(file.path, uri.toString());
    expect(file.bytes, [1, 2, 3]);
  });

  test(
    'reads browser files without treating blob URIs as local paths',
    () async {
      picker.file = _File(Uri.parse('blob:https://example.com/123'));
      final file = await XppPickedFile.importFromStorage(
        type: XppFilePickType.image,
      );
      expect(file.path, isNull);
      expect(file.bytes, [1, 2, 3]);
      expect(picker.type, FileType.image);
      expect(picker.extensions, isNull);
    },
  );

  test('U4: cancelled import is distinguishable from file errors', () async {
    await expectLater(
      XppPickedFile.importFromStorage(type: XppFilePickType.custom),
      throwsA(isA<XppFilePickerCancelled>()),
    );
  });

  test(
    'exports bytes and converts file URI to a reusable local path',
    () async {
      picker.savedUri = Uri.file('/tmp/my notes.xopp');
      final file = XppPickedFile(
        Uint8List.fromList([4, 5]),
        fileName: 'notes.xopp',
      );
      expect(await file.exportToStorage(), '/tmp/my notes.xopp');
      expect(picker.savedBytes, [4, 5]);
      expect(picker.savedName, 'notes.xopp');
    },
  );

  test('export preserves content URI and cancellation', () async {
    final file = XppPickedFile(Uint8List.fromList([4, 5]));
    picker.savedUri = Uri.parse('content://provider/document/42');
    expect(await file.exportToStorage(), picker.savedUri.toString());
    picker.savedUri = null;
    expect(await file.exportToStorage(), isNull);
  });

  test(
    'R2: replacing a local notebook leaves only a complete destination',
    () async {
      final dir = await Directory.systemTemp.createTemp('xpp-replace-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/notes.xopp';
      await File(path).writeAsBytes([1, 2, 3]);
      final saved = XppPickedFile(Uint8List.fromList([4, 5, 6, 7]));
      expect(await saved.saveToPath(path: path), path);
      expect(await File(path).readAsBytes(), [4, 5, 6, 7]);
      expect(await dir.list().length, 1);
    },
  );
  test(
    'replacement follows symbolic links without replacing the link',
    () async {
      if (Platform.isWindows) return;
      final dir = await Directory.systemTemp.createTemp('xpp-link-');
      addTearDown(() => dir.delete(recursive: true));
      final target = File('${dir.path}/target.xopp');
      await target.writeAsBytes([1]);
      final link = Link('${dir.path}/link.xopp');
      await link.create(target.path);
      await XppPickedFile(Uint8List.fromList([2])).saveToPath(path: link.path);
      expect(await link.exists(), isTrue);
      expect(await target.readAsBytes(), [2]);
    },
  );
  test('replacement refuses to weaken restrictive permissions', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('xpp-mode-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/private.xopp');
    await file.writeAsBytes([1]);
    final chmod = await Process.run('chmod', ['600', file.path]);
    expect(chmod.exitCode, 0);
    await expectLater(
      XppPickedFile(Uint8List.fromList([2])).saveToPath(path: file.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsBytes(), [1]);
  });
}

final class _File extends PlatformFile {
  _File(this.uri);
  @override
  final Uri uri;
  @override
  String get name => 'my notes.xopp';
  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList([1, 2, 3]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Picker extends FilePickerPlatform {
  PlatformFile? file;
  FileType? type;
  List<String>? extensions;
  Uri? savedUri;
  Uint8List? savedBytes;
  String? savedName;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    this.type = type;
    extensions = allowedExtensions;
    return file;
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    savedName = fileName;
    savedBytes = bytes;
    return savedUri;
  }
}
