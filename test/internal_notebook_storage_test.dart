import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/DraftRecovery.dart';
import 'package:xournalpp/src/conditional/draft_storage/draft_storage_io.dart'
    as draft_disk;
import 'package:xournalpp/main.dart';
import 'package:xournalpp/src/NotebookCache.dart';
import 'package:xournalpp/src/RecentFiles.dart';
import 'package:xournalpp/src/conditional/notebook_cache/cache_io.dart'
    as cache_disk;
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/PdfBackgroundRenderService.dart';
import 'package:xournalpp/src/TransparentImage.dart';
import 'package:xournalpp/src/conditional/internal_storage/internal_storage_io.dart'
    as disk;

class CountingPicker extends FilePickerPlatform {
  int calls = 0;
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
    calls++;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late InternalNotebookStorage storage;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'notebookCache.enabled.v1': false});
    directory = await Directory.systemTemp.createTemp('internal-notebooks-');
    disk.debugInternalDirectory = directory.path;
    storage = InternalNotebookStorage();
  });
  tearDown(() async {
    disk.debugInternalDirectory = null;
    await directory.delete(recursive: true);
  });
  test(
    'saves, reopens and updates a flat notebook with PDF resources',
    () async {
      final ref = (await storage.save(
        bytes: Uint8List.fromList([1, 2]),
        name: 'Notebook',
        pdfs: [
          NotebookPdfResource(
            reference: '../original.pdf',
            read: () async => Uint8List.fromList([3, 4]),
          ),
        ],
      ))!;
      expect(ref.backendId, 'internal');
      expect(ref.id, matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(await storage.readNotebook(ref), [1, 2]);
      expect(await storage.readPdf(ref, '../original.pdf'), [3, 4]);
      expect((await InternalNotebookStorage().list()).single.name, 'Notebook');
      final updated = (await storage.save(
        bytes: Uint8List.fromList([5]),
        name: 'Notebook',
        existing: ref,
        pdfs: [
          NotebookPdfResource(
            reference: '../original.pdf',
            read: () async => Uint8List.fromList([7]),
          ),
        ],
      ))!;
      expect(updated.id, ref.id);
      expect(await storage.readNotebook(updated), [5]);
      expect(await storage.readPdf(updated, '../original.pdf'), [7]);
      expect(
        (await directory.list().toList()).where(
          (entry) => entry.path.endsWith('.json'),
        ),
        hasLength(1),
      );
    },
  );
  test('a failed atomic write leaves the previous notebook readable', () async {
    final notebook = (await storage.save(
      bytes: Uint8List.fromList([1]),
      name: 'Safe',
      pdfs: [],
    ))!;
    final obstruction = Directory('${directory.path}/${notebook.id}.json.tmp');
    await obstruction.create();
    await expectLater(
      storage.save(
        bytes: Uint8List.fromList([2]),
        name: 'Safe',
        existing: notebook,
        pdfs: [],
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await storage.readNotebook(notebook), [1]);
  });

  test(
    'a competing save during PDF reads is detected before publication',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final pending = storage.save(
        bytes: Uint8List.fromList([1]),
        name: 'Contended',
        pdfs: [
          NotebookPdfResource(
            reference: 'pdf',
            read: () async {
              started.complete();
              await release.future;
              return Uint8List.fromList([9]);
            },
          ),
        ],
      );
      await started.future;
      final winner = (await storage.save(
        bytes: Uint8List.fromList([2]),
        name: 'Contended',
        pdfs: [],
      ))!;
      release.complete();
      await expectLater(pending, throwsA(isA<InternalNameConflict>()));
      expect(await storage.readNotebook(winner), [2]);
      expect(await storage.list(), hasLength(1));
    },
  );

  test(
    'garbage collection preserves blobs when a manifest is damaged',
    () async {
      final orphan = File('${directory.path}/${'a' * 64}.blob');
      await orphan.writeAsBytes([8]);
      await File('${directory.path}/${'b' * 32}.json').writeAsString(
        '{"version":1,"name":"broken","notebook":"invalid","pdfs":{}}',
      );
      final valid = (await storage.save(
        bytes: Uint8List.fromList([1]),
        name: 'Valid',
        pdfs: [],
      ))!;
      expect(await orphan.exists(), isTrue);
      expect(await storage.readNotebook(valid), [1]);
    },
  );

  test(
    'duplicate names require confirmation and replacement keeps the ID',
    () async {
      final first = (await storage.save(
        bytes: Uint8List.fromList([1]),
        name: 'Same',
        pdfs: [],
      ))!;
      await expectLater(
        storage.save(bytes: Uint8List.fromList([2]), name: 'Same', pdfs: []),
        throwsA(
          isA<InternalNameConflict>().having(
            (e) => e.notebook.id,
            'existing ID',
            first.id,
          ),
        ),
      );
      expect(await storage.readNotebook(first), [1]);
      final replaced = (await storage.save(
        bytes: Uint8List.fromList([2]),
        name: 'Same',
        existing: first,
        pdfs: [],
      ))!;
      expect(replaced.id, first.id);
      expect(await storage.readNotebook(first), [2]);
    },
  );
  test(
    'resaving an Internal notebook can read its own PDF without deadlock',
    () async {
      final first = (await storage.save(
        bytes: Uint8List.fromList([1]),
        name: 'PDF',
        pdfs: [
          NotebookPdfResource(
            reference: 'background.pdf',
            read: () async => Uint8List.fromList([3, 4]),
          ),
        ],
      ))!;
      final updated = await storage
          .save(
            bytes: Uint8List.fromList([2]),
            name: 'PDF',
            existing: first,
            pdfs: [
              NotebookPdfResource(
                reference: 'background.pdf',
                read: () => storage.readPdf(first, 'background.pdf'),
              ),
            ],
          )
          .timeout(const Duration(seconds: 5));
      expect(await storage.readNotebook(updated!), [2]);
      expect(await storage.readPdf(updated, 'background.pdf'), [3, 4]);
    },
  );

  test(
    'PDF resources shared between notebooks survive deletion of either notebook',
    () async {
      Future<StoredNotebook> create(String name, int byte) async =>
          (await storage.save(
            bytes: Uint8List.fromList([byte]),
            name: name,
            pdfs: [
              NotebookPdfResource(
                reference: 'background.pdf',
                read: () async => Uint8List.fromList([8, 9]),
              ),
            ],
          ))!;
      final first = await create('One', 1);
      final second = await create('Two', 2);
      expect(
        (await directory.list().toList()).where(
          (item) => item.path.endsWith('.blob'),
        ),
        hasLength(3),
      );
      await storage.delete(first);
      expect(await storage.readPdf(second, 'background.pdf'), [8, 9]);
      expect(await storage.readNotebook(second), [2]);
      expect(
        (await directory.list().toList()).where(
          (item) => item.path.endsWith('.blob'),
        ),
        hasLength(2),
      );
      await storage.delete(second);
      expect(
        (await directory.list().toList()).where(
          (item) => item.path.endsWith('.blob'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'resource failure does not replace the last successful version',
    () async {
      final first = (await storage.save(
        bytes: Uint8List.fromList([1]),
        name: 'Safe',
        pdfs: [],
      ))!;
      await expectLater(
        storage.save(
          bytes: Uint8List.fromList([2]),
          name: 'Safe',
          existing: first,
          pdfs: [
            NotebookPdfResource(
              reference: 'missing.pdf',
              read: () async => throw StateError('missing'),
            ),
          ],
        ),
        throwsStateError,
      );
      expect(await storage.readNotebook(first), [1]);
      expect((await storage.list()).single.id, first.id);
    },
  );
  test(
    'forget keeps content; explicit delete removes only the selected notebook',
    () async {
      final first = (await storage.save(
        bytes: Uint8List.fromList([1]),
        name: 'One',
        pdfs: [],
      ))!;
      final second = (await storage.save(
        bytes: Uint8List.fromList([2]),
        name: 'Two',
        pdfs: [],
      ))!;
      await storage.forget(first);
      expect(await storage.readNotebook(first), [1]);
      await storage.delete(first);
      expect((await storage.list()).map((item) => item.id), [second.id]);
      await expectLater(
        storage.readNotebook(first),
        throwsA(isA<FileSystemException>()),
      );
      expect(await storage.readNotebook(second), [2]);
    },
  );
  test(
    'concurrent same-name creates cannot silently replace each other',
    () async {
      final first = storage.save(
        bytes: Uint8List.fromList([1]),
        name: 'Same',
        pdfs: [],
      );
      final second = storage.save(
        bytes: Uint8List.fromList([2]),
        name: 'Same',
        pdfs: [],
      );
      await first;
      await expectLater(second, throwsA(isA<InternalNameConflict>()));
      expect(await storage.list(), hasLength(1));
    },
  );
  testWidgets('new named notebook saves internally without opening a picker', (
    tester,
  ) async {
    final original = FilePickerPlatform.instance;
    final picker = CountingPicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = original);
    final file = XppFile.empty(title: 'Private notebook');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: CanvasPage(file: file),
      ),
    );
    await tester.pumpAndSettle();
    final dynamic canvas = tester.state(find.byType(CanvasPage));
    late Future<bool> saving;
    await tester.runAsync(() async {
      saving = canvas.saveFile();
    });
    bool? result;
    saving.then((value) => result = value);
    for (var i = 0; result == null && i < 400; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(result, isTrue);
    expect(picker.calls, 0);
    expect(file.storage, same(internalNotebookStorage));
    final prefs = await tester.runAsync(() => SharedPreferences.getInstance());
    final recent = jsonDecode(prefs!.getString('recentFiles')!) as List;
    expect(recent.single['backendId'], 'internal');
    expect(recent.single['path'], file.storageNotebook!.id);
    expect(
      (await tester.runAsync(() => storage.list()))!.single.name,
      'Private notebook',
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('duplicate Internal name prompts before replacing', (
    tester,
  ) async {
    final original = (await tester.runAsync(
      () =>
          storage.save(bytes: Uint8List.fromList([1]), name: 'Same', pdfs: []),
    ))!;
    final file = XppFile.empty(title: 'Same');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: CanvasPage(file: file),
      ),
    );
    await tester.pumpAndSettle();
    final dynamic canvas = tester.state(find.byType(CanvasPage));
    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 400 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(finder, findsWidgets);
    }

    Future<bool?> saveAndChoose(String label) async {
      late Future<bool> future;
      await tester.runAsync(() async {
        future = canvas.saveFile();
      });
      await waitFor(find.text('Replace notebook?'));
      await tester.tap(find.text(label));
      await tester.pump();
      bool? result;
      future.then((value) => result = value);
      for (var i = 0; result == null && i < 400; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      return result;
    }

    expect(await saveAndChoose('Cancel'), isFalse);
    expect(await tester.runAsync(() => storage.readNotebook(original)), [1]);
    expect(await saveAndChoose('Replace'), isTrue);
    expect(file.storageNotebook!.id, original.id);
    expect(
      await tester.runAsync(() => storage.readNotebook(original)),
      isNot([1]),
    );
    expect((await tester.runAsync(() => storage.list()))!, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Save As Local uses the external picker', (tester) async {
    final original = FilePickerPlatform.instance;
    final picker = CountingPicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = original);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: CanvasPage(file: XppFile.empty(title: 'External')),
      ),
    );
    await tester.pumpAndSettle();
    final dynamic canvas = tester.state(find.byType(CanvasPage));
    late Future<bool> saving;
    await tester.runAsync(() async {
      saving = canvas.saveFile(saveAs: true);
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Local storage'));
    await tester.pump();
    bool? result;
    saving.then((value) => result = value);
    for (var i = 0; result == null && i < 400; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(result, isFalse); // The picker returned cancellation.
    expect(picker.calls, 1);
    expect(await tester.runAsync(() => storage.list()), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'clearing disposable cache leaves authoritative Internal notebooks intact',
    () async {
      final cache = NotebookCache();
      cache_disk.debugCacheDirectory = '${directory.path}/cache';
      addTearDown(() => cache_disk.debugCacheDirectory = null);
      await cache.setEnabled(true);
      final notebook = (await storage.save(
        bytes: Uint8List.fromList([1]),
        name: 'Keep',
        pdfs: [],
      ))!;
      await cache.record(
        notebook: notebook,
        bytes: Uint8List.fromList([1]),
        pdfs: {},
        references: [],
        dirty: false,
      );
      expect(await cache.load(notebook), isNotNull);
      await cache.clear();
      expect(await cache.load(notebook), isNull);
      expect(await storage.readNotebook(notebook), [1]);
    },
  );

  testWidgets(
    'deleting Internal requires confirmation and removes recent and cache entries',
    (tester) async {
      cache_disk.debugCacheDirectory = '${directory.path}/cache';
      addTearDown(() => cache_disk.debugCacheDirectory = null);
      late NotebookCache cache;
      addTearDown(() => NotebookCache.debugInstance = null);
      late StoredNotebook notebook;
      await tester.runAsync(() async {
        InternalNotebookStorage.resetForTesting();
        cache = NotebookCache();
        NotebookCache.debugInstance = cache;
        await cache.setEnabled(true);
        notebook = (await storage.save(
          bytes: Uint8List.fromList([1]),
          name: 'Remove me',
          pdfs: [],
        ))!;
        await cache.record(
          notebook: notebook,
          bytes: Uint8List.fromList([1]),
          pdfs: {},
          references: [],
          dirty: false,
        );
        await RecentFiles.remember(
          path: notebook.id,
          name: notebook.name,
          backendId: notebook.backendId,
          currentPage: 0,
        );
      });
      await tester.pumpWidget(XournalppMobile());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Saved notebooks'));
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 400 && finder.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(finder, findsWidgets);
      }

      await waitFor(find.byTooltip('Delete notebook'));
      await tester.tap(find.byTooltip('Delete notebook'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect((await tester.runAsync(() => storage.list()))!, hasLength(1));
      await tester.tap(find.byTooltip('Delete notebook'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete notebook').last);
      await tester.pump();
      await waitFor(find.text('No saved notebooks yet.'));
      for (
        var i = 0;
        i < 400 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(await tester.runAsync(() => storage.list()), isEmpty);
      expect(await tester.runAsync(() => cache.load(notebook)), isNull);
      final prefs = await tester.runAsync(
        () => SharedPreferences.getInstance(),
      );
      expect(prefs!.getString('recentFiles'), '[]');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Internal recent notebook reopens after restart', (tester) async {
    late StoredNotebook notebook;
    await tester.runAsync(() async {
      final bytes = await XppFile.empty(
        title: 'Restarted.v1',
      ).toUint8ListAsync();
      notebook = (await storage.save(
        bytes: bytes,
        name: 'Restarted.v1',
        pdfs: [],
      ))!;
      await RecentFiles.remember(
        path: notebook.id,
        name: notebook.name,
        backendId: notebook.backendId,
        currentPage: 0,
      );
    });
    await tester.pumpWidget(XournalppMobile());
    await tester.pumpAndSettle();
    expect(find.text('Restarted.v1'), findsOneWidget);
    await tester.ensureVisible(find.text('Restarted.v1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restarted.v1'));
    for (
      var i = 0;
      i < 200 && find.byType(CanvasPage).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.byType(CanvasPage), findsOneWidget);
    final canvas = tester.widget<CanvasPage>(find.byType(CanvasPage));
    expect(canvas.file!.title, 'Restarted.v1');
    expect(canvas.file!.storage, same(internalNotebookStorage));
    expect(canvas.file!.storageNotebook!.id, notebook.id);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('recovered Internal notebook saves back to the same provider', (
    tester,
  ) async {
    draft_disk.debugDraftDirectory = '${directory.path}/drafts';
    addTearDown(() {
      NotebookCache.debugInstance = null;
      draft_disk.debugDraftDirectory = null;
      DraftRecovery.resetForTesting();
    });
    late StoredNotebook notebook;
    await tester.runAsync(() async {
      NotebookCache.debugInstance = NotebookCache();
      InternalNotebookStorage.resetForTesting();
      DraftRecovery.resetForTesting();
      final bytes = await XppFile.empty(title: 'Recovered').toUint8ListAsync();
      notebook = (await storage.save(
        bytes: bytes,
        name: 'Recovered',
        pdfs: [],
      ))!;
      await DraftRecovery.save(
        RecoveryDraft(
          id: '100_200',
          bytes: bytes,
          page: 0,
          title: 'Recovered',
          originalPath: notebook.id,
          backendId: 'internal',
        ),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: const OpenPage(),
      ),
    );
    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 400 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(finder, findsWidgets);
    }

    await waitFor(find.text('Recover unsaved work?'));
    await tester.tap(find.text('Recover'));
    await waitFor(find.byType(CanvasPage));
    await tester.pump(const Duration(milliseconds: 300));
    final canvasWidget = tester.widget<CanvasPage>(find.byType(CanvasPage));
    expect(canvasWidget.file!.storage, same(internalNotebookStorage));
    expect(canvasWidget.file!.storageNotebook!.id, notebook.id);
    final dynamic canvas = tester.state(find.byType(CanvasPage));
    late Future<bool> saving;
    await tester.runAsync(() async {
      saving = canvas.saveFile();
    });
    bool? result;
    saving.then((value) => result = value);
    for (var i = 0; result == null && i < 400; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(result, isTrue);
    expect(
      (await tester.runAsync(() => storage.list()))!.single.id,
      notebook.id,
    );
    expect(await tester.runAsync(DraftRecovery.list), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Local export of an Internal PDF notebook warns before the picker',
    (tester) async {
      final originalPicker = FilePickerPlatform.instance;
      final picker = CountingPicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = originalPicker);
      final notebook = (await tester.runAsync(
        () => storage.save(
          bytes: Uint8List.fromList([1]),
          name: 'With PDF',
          pdfs: [
            NotebookPdfResource(
              reference: 'background.pdf',
              read: () async => Uint8List.fromList([1, 2, 3]),
            ),
          ],
        ),
      ))!;
      final file = XppFile.empty(title: 'With PDF')
        ..storage = storage
        ..storageNotebook = notebook;
      file.pages!.first.background = XppBackgroundPdf(
        filename: 'background.pdf',
        page: 1,
        onUnavailable: (_, __) async => throw StateError('unexpected recovery'),
      );
      final service = PdfBackgroundRenderService(
        cacheReader: (_) async => kTransparentImage,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: CanvasPage(
            file: file,
            filePath: notebook.id,
            pdfRenderService: service,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final dynamic canvas = tester.state(find.byType(CanvasPage));
      late Future<bool> saving;
      await tester.runAsync(() async {
        saving = canvas.saveFile(saveAs: true);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Local storage'));
      for (
        var i = 0;
        i < 400 &&
            find.text('PDF backgrounds are not copied').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.text('PDF backgrounds are not copied'), findsOneWidget);
      expect(picker.calls, 0);
      await tester.tap(find.text('Cancel').last);
      await tester.pump();
      bool? result;
      saving.then((value) => result = value);
      for (var i = 0; result == null && i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(result, isFalse);
      expect(picker.calls, 0);
      expect(file.storage, same(storage));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Save As copies an existing Local notebook into Internal', (
    tester,
  ) async {
    final originalPicker = FilePickerPlatform.instance;
    final picker = CountingPicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = originalPicker);
    final file = XppFile.empty(title: 'External');
    final path = '${directory.path}/original.xopp';
    late Uint8List initial;
    addTearDown(() => NotebookCache.debugInstance = null);
    await tester.runAsync(() async {
      InternalNotebookStorage.resetForTesting();
      DraftRecovery.resetForTesting();
      NotebookCache.debugInstance = NotebookCache();
      initial = await file.toUint8ListAsync();
      await File(path).writeAsBytes(initial);
    });
    file.storage = localNotebookStorage;
    file.storageNotebook = StoredNotebook(
      backendId: 'local',
      id: path,
      name: 'External',
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: CanvasPage(file: file, filePath: path),
      ),
    );
    await tester.pumpAndSettle();
    final dynamic canvas = tester.state(find.byType(CanvasPage));
    late Future<bool> saving;
    await tester.runAsync(() async {
      saving = canvas.saveFile(saveAs: true);
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Internal'));
    bool? result;
    saving.then((value) => result = value);
    for (var i = 0; result == null && i < 400; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(result, isTrue);
    expect(picker.calls, 0);
    expect(file.storage, same(internalNotebookStorage));
    expect(await tester.runAsync(() => File(path).readAsBytes()), initial);
    final copies = await tester.runAsync(() => storage.list());
    expect(copies!.single.name, 'External');
    expect(
      (await tester.runAsync(() => storage.readNotebook(copies.single)))!,
      isNotEmpty,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
