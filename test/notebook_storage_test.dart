import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:xournalpp/src/TransparentImage.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';

class MemoryStorage implements NotebookStorage {
  @override
  String? get iconAsset => null;
  @override
  String get id => 'memory';
  Uint8List? notebook;
  final pdfs = <String, Uint8List>{};
  @override
  Future<StoredNotebook?> save({
    required Uint8List bytes,
    required String name,
    StoredNotebook? existing,
    required List<NotebookPdfResource> pdfs,
  }) async {
    final captured = <String, Uint8List>{};
    for (final pdf in pdfs) {
      captured[pdf.reference] = await pdf.read();
    }
    notebook = bytes;
    this.pdfs.addAll(captured);
    return StoredNotebook(backendId: id, id: 'opaque-not-a-path', name: name);
  }

  @override
  Future<List<StoredNotebook>> list() async => notebook == null
      ? []
      : [
          StoredNotebook(
            backendId: id,
            id: 'opaque-not-a-path',
            name: 'Notebook',
          ),
        ];
  @override
  Future<Uint8List> readNotebook(StoredNotebook notebook) async =>
      this.notebook!;
  @override
  Future<Uint8List> readPdf(StoredNotebook notebook, String reference) async =>
      pdfs[reference]!;
  @override
  Future<void> forget(StoredNotebook notebook) async {
    this.notebook = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'local saves persist, replace and forget without deleting files',
    () async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('notebook-storage-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/note.xopp';
      final storage = LocalNotebookStorage();
      final ref = StoredNotebook(backendId: storage.id, id: path, name: 'One');
      await storage.save(
        bytes: Uint8List.fromList([1, 2]),
        name: 'One',
        existing: ref,
        pdfs: [],
      );
      await storage.save(
        bytes: Uint8List.fromList([3]),
        name: 'Updated',
        existing: ref,
        pdfs: [],
      );
      final entries = await LocalNotebookStorage().list();
      expect(entries, hasLength(1));
      expect(entries.single.name, 'Updated');
      expect(await storage.readNotebook(entries.single), [3]);
      final invalid = StoredNotebook(
        backendId: storage.id,
        id: '${dir.path}/missing/note.xopp',
        name: 'Invalid',
      );
      await expectLater(
        storage.save(
          bytes: Uint8List.fromList([9]),
          name: 'Invalid',
          existing: invalid,
          pdfs: [],
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect((await storage.list()).single.id, path);
      await storage.forget(entries.single);
      expect(await storage.list(), isEmpty);
      expect(await File(path).exists(), isTrue);
    },
  );

  testWidgets(
    'opaque notebook can reopen its associated PDF through its backend',
    (tester) async {
      final storage = MemoryStorage();
      final file = XppFile.empty(title: 'Notebook');
      file.previewImage = kTransparentImage;
      file.pages!.first.background = XppBackgroundPdf(
        filename: 'original.pdf',
        page: 1,
        onUnavailable: (_, __) async => throw StateError('unexpected recovery'),
      );
      final pdf = Uint8List.fromList([1, 4, 8]);
      final saved = (await storage.save(
        bytes: file.toUint8List()!,
        name: 'Notebook',
        pdfs: [
          NotebookPdfResource(reference: 'original.pdf', read: () async => pdf),
        ],
      ))!;
      expect((await storage.list()).single.id, 'opaque-not-a-path');
      final reopened = (await tester.runAsync(
        () => XppFile.openStoredNotebook(
          storage,
          saved,
          (_, __) async => throw StateError('unexpected recovery'),
        ),
      ))!;
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final background = reopened.pages!.first.background! as XppBackgroundPdf;
      expect(
        (await reopened.readBackgroundPdf(context, background)).bytes,
        pdf,
      );
    },
  );
}
