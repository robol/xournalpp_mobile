import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:xournalpp/src/NotebookTransfer.dart';
import 'package:xournalpp/src/NotebookCache.dart';
import 'package:xournalpp/src/RecentFiles.dart';
import 'package:xournalpp/src/DraftRecovery.dart';
import 'package:xournalpp/src/conditional/draft_storage/draft_storage_io.dart'
    as drafts;
import 'package:xournalpp/src/conditional/internal_storage/internal_storage_io.dart'
    as internal;
import 'package:xournalpp/src/conditional/notebook_cache/cache_io.dart'
    as cache;

class MemoryStorage
    implements NotebookStorage, NotebookDeletion, NotebookTransfer {
  MemoryStorage(this.id, this.events);
  @override
  final String id;
  final List<String> events;
  bool failDelete = false,
      failCopy = false,
      failRead = false,
      permitted = true,
      cancel = false;
  Uint8List sourceBytes = Uint8List.fromList([1]);
  void Function()? onCopy;
  Uint8List? copied;
  @override
  String? get iconAsset => null;
  @override
  bool canDelete(StoredNotebook notebook) => permitted;
  @override
  Future<void> delete(StoredNotebook notebook) async {
    events.add('delete');
    if (failDelete) throw StateError('denied');
  }

  @override
  Future<Uint8List> readNotebook(StoredNotebook notebook) async {
    events.add('read');
    if (failRead) throw StateError('offline');
    return Uint8List.fromList(sourceBytes);
  }

  @override
  Future<StoredNotebook?> createInFolder({
    required NotebookFolder folder,
    required String name,
    required Uint8List bytes,
    required List<NotebookPdfResource> pdfs,
  }) async {
    events.add('copy');
    onCopy?.call();
    if (failCopy) throw StateError('conflict');
    for (final pdf in pdfs) {
      expect(await pdf.read(), [9]);
    }
    copied = bytes;
    return cancel ? null : StoredNotebook(backendId: id, id: 'new', name: name);
  }

  @override
  Future<NotebookFolder?> parentOf(StoredNotebook notebook) async =>
      NotebookFolder(id, 'folder');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late List<String> events;
  late MemoryStorage source, target;
  const original = StoredNotebook(backendId: 'source', id: 'old', name: 'Old');
  setUp(() async {
    SharedPreferences.setMockInitialValues({'notebookCache.enabled.v1': false});
    directory = await Directory.systemTemp.createTemp('transfer-');
    cache.debugCacheDirectory = '${directory.path}/cache';
    drafts.debugDraftDirectory = '${directory.path}/drafts';
    DraftRecovery.resetForTesting();
    internal.debugInternalDirectory = '${directory.path}/internal';
    NotebookCache.debugInstance = NotebookCache();
    InternalNotebookStorage.resetForTesting();
    events = [];
    source = MemoryStorage('source', events);
    target = MemoryStorage('target', events);
  });
  tearDown(() async {
    NotebookCache.debugInstance = null;
    cache.debugCacheDirectory = null;
    drafts.debugDraftDirectory = null;
    internal.debugInternalDirectory = null;
    await directory.delete(recursive: true);
  });
  Future<NotebookTransferResult> move({
    List<NotebookPdfResource> pdfs = const [],
    bool cached = false,
  }) => NotebookTransferCoordinator().move(
    source: source,
    original: original,
    destination: target,
    folder: const NotebookFolder('target', 'folder'),
    name: 'New',
    bytes: Uint8List.fromList([5, 6]),
    pdfs: pdfs,
    cachedOrigin: cached,
  );

  test(
    'copies edited snapshot and resources before deletion, removes old recent',
    () async {
      await RecentFiles.remember(
        path: original.id,
        name: original.name,
        currentPage: 0,
        backendId: original.backendId,
      );
      final result = await move(
        pdfs: [
          NotebookPdfResource(
            reference: 'p',
            read: () async {
              events.add('pdf');
              return Uint8List.fromList([9]);
            },
          ),
        ],
      );
      expect(result.status, NotebookTransferStatus.moved);
      expect(events, ['read', 'pdf', 'copy', 'read', 'delete']);
      expect(target.copied, [5, 6]);
      expect(result.notebook!.id, 'new');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('recentFiles'), isNot(contains('old')));
    },
  );
  test(
    'successful move relocates matching recovery drafts and delete keeps them',
    () async {
      await DraftRecovery.save(
        RecoveryDraft(
          id: '1_1',
          bytes: Uint8List.fromList([7]),
          page: 2,
          title: 'Old',
          originalPath: original.id,
          backendId: original.backendId,
        ),
      );
      final result = await move();
      final draft = (await DraftRecovery.list()).single;
      expect(draft.originalPath, result.notebook!.id);
      expect(draft.backendId, 'target');
      expect(draft.bytes, [7]);
      await NotebookTransferCoordinator().delete(target, result.notebook!);
      expect(await DraftRecovery.list(), hasLength(1));
    },
  );
  test('failed destination leaves source untouched', () async {
    target.failCopy = true;
    expect((await move()).status, NotebookTransferStatus.failedBeforeCopy);
    expect(events, ['read', 'copy']);
  });
  test('failed resource leaves both providers untouched', () async {
    final result = await move(
      pdfs: [
        NotebookPdfResource(
          reference: 'p',
          read: () async => throw StateError('missing PDF'),
        ),
      ],
    );
    expect(result.status, NotebookTransferStatus.failedBeforeCopy);
    expect(events, ['read']);
  });
  test('offline source cannot move an editor snapshot', () async {
    source.failRead = true;
    expect((await move()).status, NotebookTransferStatus.failedBeforeCopy);
    expect(events, ['read']);
  });
  test(
    'cached source and unsupported permission cannot create a copy',
    () async {
      expect(
        (await move(cached: true)).status,
        NotebookTransferStatus.failedBeforeCopy,
      );
      source.permitted = false;
      expect((await move()).status, NotebookTransferStatus.failedBeforeCopy);
      expect(events, isEmpty);
    },
  );
  test('cancelled creation never deletes', () async {
    target.cancel = true;
    expect((await move()).status, NotebookTransferStatus.cancelled);
    expect(events, ['read', 'copy']);
  });
  test(
    'partial move retains copy; retry deletes without copying again',
    () async {
      source.failDelete = true;
      final result = await move();
      expect(result.status, NotebookTransferStatus.copiedSourceRetained);
      expect(result.notebook!.id, 'new');
      source.failDelete = false;
      await NotebookTransferCoordinator().retrySourceDeletion(
        source,
        original,
        result.notebook!,
        sourceDigest: result.sourceDigest!,
      );
      expect(events, ['read', 'copy', 'read', 'delete', 'read', 'delete']);
    },
  );
  test('retains source if it changes while destination is created', () async {
    target.onCopy = () => source.sourceBytes = Uint8List.fromList([9]);
    final result = await move();
    expect(result.status, NotebookTransferStatus.copiedSourceRetained);
    expect(result.error, isA<NotebookEditConflict>());
    expect(events, ['read', 'copy', 'read']);
    expect(target.copied, [5, 6]);
  });
  test('retry never deletes a source that changed after copying', () async {
    source.failDelete = true;
    final result = await move();
    source.failDelete = false;
    source.sourceBytes = Uint8List.fromList([8]);
    await expectLater(
      NotebookTransferCoordinator().retrySourceDeletion(
        source,
        original,
        result.notebook!,
        sourceDigest: result.sourceDigest!,
      ),
      throwsA(isA<NotebookEditConflict>()),
    );
    expect(events.where((event) => event == 'delete'), hasLength(1));
  });
  test('Local destination blocks provider-owned PDFs before IO', () async {
    final result = await NotebookTransferCoordinator().move(
      source: source,
      original: original,
      destination: LocalNotebookStorage(),
      folder: NotebookFolder('local', directory.path),
      name: 'New',
      bytes: Uint8List(0),
      pdfs: [
        NotebookPdfResource(reference: 'p', read: () async => Uint8List(0)),
      ],
    );
    expect(result.error, isA<UnsafeNotebookTransfer>());
    expect(events, isEmpty);
    expect(await directory.list().toList(), isEmpty);
  });
  test(
    'Local exclusive create refuses conflicts and delete preserves PDFs',
    () async {
      final storage = LocalNotebookStorage();
      final pdf = File('${directory.path}/background.pdf');
      await pdf.writeAsBytes([9]);
      final folder = NotebookFolder('local', directory.path);
      final saved = (await storage.createInFolder(
        folder: folder,
        name: 'New',
        bytes: Uint8List.fromList([1]),
        pdfs: [],
      ))!;
      await expectLater(
        storage.createInFolder(
          folder: folder,
          name: 'New',
          bytes: Uint8List.fromList([2]),
          pdfs: [],
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await storage.readNotebook(saved), [1]);
      expect((await storage.parentOf(saved))!.id, directory.path);
      await storage.delete(saved);
      expect(await pdf.readAsBytes(), [9]);
      expect(await storage.list(), isEmpty);
    },
  );
  test(
    'Internal rename copies all PDF resources before manifest deletion',
    () async {
      final storage = InternalNotebookStorage();
      final saved = (await storage.save(
        bytes: Uint8List.fromList([1]),
        name: 'Old',
        pdfs: [
          NotebookPdfResource(
            reference: 'p',
            read: () async => Uint8List.fromList([9]),
          ),
        ],
      ))!;
      final result = await NotebookTransferCoordinator().move(
        source: storage,
        original: saved,
        destination: storage,
        folder: (await storage.parentOf(saved))!,
        name: 'New',
        bytes: Uint8List.fromList([2]),
        pdfs: [
          NotebookPdfResource(
            reference: 'p',
            read: () => storage.readPdf(saved, 'p'),
          ),
        ],
      );
      expect(result.status, NotebookTransferStatus.moved);
      expect((await storage.list()).single.name, 'New');
      expect(await storage.readNotebook(result.notebook!), [2]);
      expect(await storage.readPdf(result.notebook!, 'p'), [9]);
    },
  );
  test('rejects names with separators and control characters', () {
    for (final name in ['', '..', 'a/b', r'a\b', 'a\n']) {
      expect(() => validateNotebookName(name), throwsArgumentError);
    }
  });
  test(
    'moving to the current Local folder with the same filename is a no-op',
    () async {
      final storage = LocalNotebookStorage();
      final folder = NotebookFolder('local', directory.path);
      final saved = (await storage.createInFolder(
        folder: folder,
        name: 'Original',
        bytes: Uint8List.fromList([1]),
        pdfs: [],
      ))!;
      final result = await NotebookTransferCoordinator().move(
        source: storage,
        original: saved,
        destination: storage,
        folder: folder,
        name: 'Original.xopp',
        bytes: Uint8List.fromList([2]),
        pdfs: [],
      );
      expect(result.status, NotebookTransferStatus.cancelled);
      expect(await storage.readNotebook(saved), [1]);
      expect(await storage.list(), hasLength(1));
    },
  );
}
