import 'dart:convert';
import 'dart:io';
import 'package:xournalpp/src/conditional/notebook_cache/cache_io.dart'
    as cache_io;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/src/NotebookCache.dart';
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:xournalpp/src/RecentFiles.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/widgets/CachedNotebookList.dart';
import 'package:xournalpp/widgets/CachedNotebookDialogs.dart';

class MemoryCache implements NotebookCachePersistence {
  final files = <String, Uint8List>{};
  bool failManifests = false;
  @override
  Future<Uint8List?> read(String key) async => files[key];
  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (failManifests && key.endsWith('.json')) throw StateError('disk full');
    files[key] = Uint8List.fromList(bytes);
  }

  @override
  Future<List<String>> list() async => files.keys.toList();
  @override
  Future<void> delete(String key) async {
    files.remove(key);
  }
}

class ReadStorage implements NotebookStorage {
  @override
  String get id => 'remote';
  @override
  String? get iconAsset => null;
  Object? failure;
  bool failSave = false;
  int saves = 0;
  Uint8List bytes = Uint8List(0);
  @override
  Future<Uint8List> readNotebook(StoredNotebook notebook) async {
    if (failure != null) throw failure!;
    return bytes;
  }

  @override
  Future<Uint8List> readPdf(StoredNotebook notebook, String ref) =>
      throw StateError('missing PDF');
  @override
  Future<List<StoredNotebook>> list() async => [];
  @override
  Future<void> forget(StoredNotebook notebook) async {}
  @override
  Future<StoredNotebook?> save({
    required Uint8List bytes,
    required String name,
    StoredNotebook? existing,
    required List<NotebookPdfResource> pdfs,
  }) async {
    saves++;
    if (failSave) throw StateError('offline');
    return existing;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notebook = StoredNotebook(
    backendId: 'remote',
    id: 'one',
    name: 'Notebook',
  );
  late NotebookCache cache;
  late MemoryCache disk;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    disk = MemoryCache();
    cache = NotebookCache(persistence: disk);
    NotebookCache.debugInstance = cache;
  });
  tearDown(() => NotebookCache.debugInstance = null);
  Future<void> record(
    int value, {
    bool dirty = false,
    List<String> refs = const [],
    Map<String, Uint8List> pdfs = const {},
    StoredNotebook ref = notebook,
  }) => cache.record(
    notebook: ref,
    bytes: Uint8List.fromList([value]),
    pdfs: pdfs,
    references: refs,
    dirty: dirty,
  );

  test(
    'native cache defaults on and retains edits separately from baseline',
    () async {
      expect(await cache.enabled, isTrue);
      await record(1);
      await record(2, dirty: true);
      expect((await cache.load(notebook))!.bytes, [2]);
      expect((await cache.load(notebook))!.dirty, isTrue);
      // A fresh provider open cannot silently destroy local unsaved edits.
      await record(3);
      expect((await cache.load(notebook))!.bytes, [2]);
      await cache.discardWorking(notebook);
      expect((await cache.load(notebook))!.bytes, [3]);
      expect((await cache.load(notebook))!.dirty, isFalse);
    },
  );
  test('serialized checkpoints cannot publish out of order', () async {
    await record(0);
    final first = record(1, dirty: true);
    final second = record(2, dirty: true);
    await Future.wait([first, second]);
    expect((await cache.load(notebook))!.bytes, [2]);
  });
  test(
    'failed manifest publication preserves previous complete snapshot',
    () async {
      await record(1);
      disk.failManifests = true;
      await expectLater(record(2, dirty: true), throwsStateError);
      expect((await cache.load(notebook))!.bytes, [1]);
      disk.failManifests = false;
      await record(3, dirty: true);
      expect((await cache.load(notebook))!.bytes, [3]);
    },
  );
  test('PDFs are deduplicated, missing backgrounds are explicit', () async {
    final pdf = Uint8List.fromList([10, 20, 30]);
    await record(
      1,
      refs: ['one.pdf', 'two.pdf', 'missing.pdf'],
      pdfs: {'one.pdf': pdf, 'two.pdf': pdf},
    );
    final loaded = (await cache.load(notebook))!;
    expect(loaded.pdfs.keys, ['one.pdf', 'two.pdf']);
    expect(loaded.missingPdfs, ['missing.pdf']);
    expect(disk.files.keys.where((key) => key.endsWith('.blob')), hasLength(2));
    await record(2, dirty: true, refs: ['one.pdf']);
    expect((await cache.load(notebook))!.pdfs['one.pdf'], pdf);
  });
  test('cache identities isolate providers and accounts', () async {
    const other = StoredNotebook(
      backendId: 'different-account',
      id: 'one',
      name: 'Other',
    );
    await record(1);
    await record(2, ref: other);
    expect((await cache.load(notebook))!.bytes, [1]);
    expect(
      (await cache.list(backendId: 'different-account')).single.name,
      'Other',
    );
  });
  test('disabling stops reads and writes without deleting data', () async {
    await record(1);
    final before = await cache.size();
    await cache.setEnabled(false);
    await record(2);
    expect(await cache.load(notebook), isNull);
    expect(await cache.list(), isEmpty);
    expect(await cache.size(), before);
    await cache.setEnabled(true);
    expect((await cache.load(notebook))!.bytes, [1]);
  });
  test('clear invalidates queued and delayed checkpoints', () async {
    await record(1);
    final oldGeneration = cache.generation;
    final pending = record(2, dirty: true);
    await cache.clear();
    await pending;
    await cache.record(
      notebook: notebook,
      bytes: Uint8List.fromList([3]),
      pdfs: {},
      references: [],
      dirty: true,
      expectedGeneration: oldGeneration,
    );
    expect(await cache.list(), isEmpty);
    expect(await cache.size(), 0);
  });
  test('corrupt entries do not hide other notebooks', () async {
    await record(1);
    disk.files['broken.json'] = Uint8List.fromList(utf8.encode('not JSON'));
    expect(await cache.list(), hasLength(1));
    final manifestKey = disk.files.keys.firstWhere(
      (key) => key.endsWith('.json') && key != 'broken.json',
    );
    final manifest = jsonDecode(utf8.decode(disk.files[manifestKey]!)) as Map;
    disk.files[manifest['baseline']['bytes'] as String] = Uint8List.fromList([
      99,
    ]);
    await expectLater(cache.load(notebook), throwsFormatException);
  });
  test(
    'replacing snapshots does not accumulate historical notebook blobs',
    () async {
      for (var i = 0; i < 10; i++) {
        await record(i);
      }
      expect(
        disk.files.keys.where((key) => key.endsWith('.blob')),
        hasLength(1),
      );
    },
  );
  test(
    'fallback is offered for provider reads, never parsing failures',
    () async {
      // Disable the singleton's disk cache: this test uses an explicit fallback.
      SharedPreferences.setMockInitialValues({
        'notebookCache.enabled.v1': false,
      });
      final bytes = await XppFile.empty(title: 'Cached').toUint8ListAsync();
      final snapshot = CachedNotebook(
        notebook: notebook,
        bytes: bytes,
        pdfs: {},
        missingPdfs: [],
        checkpoint: DateTime(2026),
        dirty: true,
        page: 0,
      );
      final provider = ReadStorage()..failure = StateError('offline');
      var calls = 0;
      Future<CachedNotebook?> fallback(Object error) async {
        calls++;
        return snapshot;
      }

      final file = await XppFile.openStoredNotebook(
        provider,
        notebook,
        (context, name) => throw StateError('missing PDF'),
        onReadFailure: fallback,
      );
      expect(file.openedFromCache, isTrue);
      expect(file.cachedEdits, isTrue);
      provider.failure = null;
      provider.bytes = Uint8List.fromList([0]);
      await expectLater(
        XppFile.openStoredNotebook(
          provider,
          notebook,
          (context, name) => throw StateError('missing PDF'),
          onReadFailure: fallback,
        ),
        throwsA(anything),
      );
      expect(calls, 1);
      provider.bytes = await XppFile.empty(title: 'Fresh').toUint8ListAsync();
      final fresh = await XppFile.openStoredNotebook(
        provider,
        notebook,
        (context, name) => throw StateError('missing PDF'),
        onReadFailure: fallback,
      );
      expect(fresh.openedFromCache, isFalse);
    },
  );
  testWidgets('cached overwrite dialog requires an explicit choice', (
    tester,
  ) async {
    await tester.pumpWidget(XournalppMobile());
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold).first);
    final result = confirmCachedOverwrite(context);
    await tester.pumpAndSettle();
    expect(find.textContaining('may overwrite newer changes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, CachedSaveChoice.cancel);
  });
  for (final failed in [false, true]) {
    testWidgets(
      'cached overwrite ${failed ? 'failure preserves warning' : 'success clears warning'}',
      (tester) async {
        final provider = ReadStorage()..failSave = failed;
        final file = XppFile.empty(title: 'Cached notebook')
          ..storage = provider
          ..storageNotebook = notebook
          ..openedFromCache = true
          ..cachedEdits = true;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: S.delegate.supportedLocales,
            home: CanvasPage(file: file, filePath: notebook.id),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MaterialBanner), findsOneWidget);
        final dynamic canvas = tester.state(find.byType(CanvasPage));
        late Future<bool> saving;
        await tester.runAsync(() async {
          saving = canvas.saveFile();
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(provider.saves, 0);
        await tester.tap(find.text('Overwrite original').last);
        await tester.pump();
        bool? saved;
        saving.then((value) => saved = value);
        for (var i = 0; saved == null && i < 300; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(saved, isNotNull);
        await tester.pumpAndSettle();
        expect(provider.saves, 1);
        expect(saved, !failed);
        expect(file.openedFromCache, failed);
        expect(
          find.byType(MaterialBanner),
          failed ? findsOneWidget : findsNothing,
        );
        await tester.runAsync(() async {
          await file.cacheSnapshot(Uint8List.fromList([1]), dirty: true);
        });
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test(
    'disk cache publishes readable snapshots without temporary files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'notebook-cache-',
      );
      cache_io.debugCacheDirectory = directory.path;
      addTearDown(() async {
        cache_io.debugCacheDirectory = null;
        await directory.delete(recursive: true);
      });
      final native = NotebookCache(persistence: FileNotebookCachePersistence());
      await native.record(
        notebook: notebook,
        bytes: Uint8List.fromList([1, 2]),
        pdfs: {},
        references: [],
        dirty: false,
      );
      expect((await native.load(notebook))!.bytes, [1, 2]);
      expect(
        await native.persistence.list(),
        everyElement(isNot(endsWith('.tmp'))),
      );
      await native.clear();
      expect(await native.size(), 0);
    },
  );
  test('late PDFs enrich checkpoints without replacing newer edits', () async {
    Future<void> snapshot(int value, String session, bool dirty) =>
        cache.record(
          notebook: notebook,
          bytes: Uint8List.fromList([value]),
          pdfs: {},
          references: ['background.pdf'],
          dirty: dirty,
          resourceSession: session,
        );
    await snapshot(1, 'first-open', false);
    await snapshot(2, 'first-open', true);
    await cache.addPdfs(
      notebook,
      {
        'background.pdf': Uint8List.fromList([9]),
      },
      expectedGeneration: cache.generation,
      resourceSession: 'first-open',
    );
    var loaded = (await cache.load(notebook))!;
    expect(loaded.bytes, [2]);
    expect(loaded.pdfs['background.pdf'], [9]);
    expect(loaded.missingPdfs, isEmpty);
    await cache.discardWorking(notebook);
    await snapshot(3, 'second-open', false);
    await cache.addPdfs(
      notebook,
      {
        'background.pdf': Uint8List.fromList([8]),
      },
      expectedGeneration: cache.generation,
      resourceSession: 'first-open',
    );
    loaded = (await cache.load(notebook))!;
    expect(loaded.bytes, [3]);
    expect(loaded.pdfs, isEmpty);
    expect(loaded.missingPdfs, ['background.pdf']);
    final generation = cache.generation;
    await cache.clear();
    await cache.addPdfs(
      notebook,
      {
        'background.pdf': Uint8List.fromList([9]),
      },
      expectedGeneration: generation,
      resourceSession: 'second-open',
    );
    expect(await cache.size(), 0);
  });
  testWidgets(
    'cached browser isolates providers and refreshes after clearing',
    (tester) async {
      const other = StoredNotebook(
        backendId: 'other',
        id: 'two',
        name: 'Other notebook',
      );
      await tester.runAsync(
        () => cache.record(
          notebook: notebook,
          bytes: Uint8List.fromList([1]),
          pdfs: {},
          references: [],
          dirty: false,
        ),
      );
      await tester.runAsync(
        () => cache.record(
          notebook: other,
          bytes: Uint8List.fromList([2]),
          pdfs: {},
          references: [],
          dirty: false,
        ),
      );
      Widget browser(String id) => MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.delegate.supportedLocales,
        home: Scaffold(
          body: CachedNotebookList(backendId: id, onOpen: (_) {}),
        ),
      );
      Future<void> settleBrowser() async {
        for (
          var i = 0;
          i < 100 &&
              find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(browser('remote'));
      await settleBrowser();
      expect(find.text('Notebook'), findsOneWidget);
      expect(find.text('Other notebook'), findsNothing);
      await tester.pumpWidget(browser('other'));
      await settleBrowser();
      expect(find.text('Notebook'), findsNothing);
      expect(find.text('Other notebook'), findsOneWidget);
      await tester.runAsync(() => cache.clear());
      await settleBrowser();
      expect(find.text('Other notebook'), findsNothing);
      expect(find.text('No cached notebooks are available.'), findsOneWidget);
    },
  );

  testWidgets('cached PDF bytes remain usable without a connected provider', (
    tester,
  ) async {
    final original = XppFile.empty(title: 'With PDF');
    original.pages!.first.background = XppBackgroundPdf(
      filename: 'background.pdf',
      page: 1,
      onUnavailable: (context, name) => throw StateError('unexpected recovery'),
    );
    final bytes = (await tester.runAsync(() => original.toUint8ListAsync()))!;
    final cached = CachedNotebook(
      notebook: notebook,
      bytes: bytes,
      pdfs: {
        'background.pdf': Uint8List.fromList([1, 2, 3]),
      },
      missingPdfs: [],
      checkpoint: DateTime(2026),
      dirty: true,
      page: 0,
    );
    final file = (await tester.runAsync(
      () => XppFile.fromCachedNotebook(
        cached,
        null,
        (context, name) => throw StateError('unexpected recovery'),
      ),
    ))!;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final context = tester.element(find.byType(Scaffold));
    final pdf = await file.readBackgroundPdf(
      context,
      file.pages!.first.background as XppBackgroundPdf,
    );
    expect(pdf.bytes, [1, 2, 3]);
    expect(file.storage, isNull);
    expect(file.openedFromCache, isTrue);
  });
  testWidgets(
    'failed recent open offers cached edits and cancelled overwrite never saves',
    (tester) async {
      final provider = ReadStorage()..failure = StateError('provider offline');
      notebookStorageBackends.add(provider);
      addTearDown(() => notebookStorageBackends.remove(provider));
      await tester.runAsync(() async {
        final bytes = await XppFile.empty(title: 'Notebook').toUint8ListAsync();
        await cache.record(
          notebook: notebook,
          bytes: bytes,
          pdfs: {},
          references: [],
          dirty: true,
        );
        await RecentFiles.remember(
          currentPage: 0,
          path: notebook.id,
          name: notebook.name,
          backendId: notebook.backendId,
        );
      });
      await tester.pumpWidget(XournalppMobile());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notebook'));
      Future<void> until(Finder finder) async {
        for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(finder, findsWidgets);
      }

      await until(find.text('Open cached copy?'));
      expect(find.textContaining('Includes unsaved edits'), findsOneWidget);
      await tester.tap(find.text('Open cached copy'));
      await until(find.byType(CanvasPage));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsOneWidget);
      final dynamic canvas = tester.state(find.byType(CanvasPage));
      late Future<bool> saving;
      await tester.runAsync(() async {
        saving = canvas.saveFile();
      });
      await until(find.text('Overwrite original?'));
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(await tester.runAsync(() => saving), isFalse);
      expect(provider.saves, 0);
      expect(find.byType(MaterialBanner), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
