import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xournalpp/src/PdfBackgroundRenderService.dart';
import 'package:xournalpp/src/XppPickedFile.dart';

void main() {
  test(
    'queued rendering uses immutable bytes even after the path is replaced',
    () async {
      var fileBytes = Uint8List.fromList([1, 2, 3]);
      final originalBytes = fileBytes;
      final cacheGate = Completer<Uint8List?>();
      final opened = <Uint8List?>[];
      final service = _testService(
        sourceRevision: (_) async => 'same metadata',
        sourceReader: (_) async => fileBytes,
        cacheReader: (_) => cacheGate.future,
        documentOpener: (source) async {
          opened.add(source.bytes);
          return _FakePdfDocument(source.id);
        },
      );
      Future<XppPickedFile> fallback() async =>
          throw StateError('unexpected recovery');
      final source = await service.sourceForPath(
        '/snapshot.pdf',
        fallback: fallback,
      );
      final request = service.request(
        source,
        1,
        PdfBackgroundRenderVariant.full,
      );
      originalBytes[0] = 9;
      fileBytes = Uint8List.fromList([4, 5, 6]);
      cacheGate.complete(null);
      await request;
      expect(opened.single, [1, 2, 3]);
      expect(() => source.bytes![0] = 0, throwsUnsupportedError);
      final replaced = await service.sourceForPath(
        '/snapshot.pdf',
        fallback: fallback,
      );
      expect(replaced.id, isNot(source.id));
      expect(replaced.bytes, [4, 5, 6]);
      await service.dispose();
    },
  );

  test('readable document URI does not invoke recovery', () async {
    final service = _testService(
      sourceReader: (path) async {
        expect(path, 'content://provider/document');
        return Uint8List.fromList([7]);
      },
    );
    final source = await service.sourceForPath(
      'content://provider/document',
      fallback: () async => throw StateError('unexpected recovery'),
    );
    expect(source.bytes, [7]);
    await service.dispose();
  });

  test('canceled opens enforce the native document limit', () async {
    final documents = <_FakePdfDocument>[];
    late Completer<PdfDocument> opening;
    late Completer<void> started;
    final service = _testService(
      maxOpenDocuments: 1,
      documentOpener: (_) {
        started.complete();
        return opening.future;
      },
    );
    for (var i = 0; i < 5; i++) {
      opening = Completer<PdfDocument>();
      started = Completer<void>();
      final owner = Object();
      final source = service.sourceForPickedFile(
        XppPickedFile(Uint8List.fromList([i])),
      );
      final request = service.request(
        source,
        1,
        PdfBackgroundRenderVariant.full,
        owner: owner,
      );
      final error = expectLater(request, throwsA(isA<PdfRenderCanceled>()));
      await started.future;
      service.cancelRequests(owner);
      final document = _FakePdfDocument('$i');
      documents.add(document);
      opening.complete(document);
      await error;
      await Future<void>.delayed(Duration.zero);
      expect(
        documents.where((doc) => !doc.disposed).length,
        lessThanOrEqualTo(1),
      );
    }
    await service.dispose();
    expect(documents.every((doc) => doc.disposed), isTrue);
  });

  test('failed renders enforce the native document limit', () async {
    final documents = <_FakePdfDocument>[];
    final service = _testService(
      maxOpenDocuments: 1,
      documentOpener: (source) async {
        final document = _FakePdfDocument(source.id);
        documents.add(document);
        return document;
      },
      renderer: (_, __, ___) async => throw StateError('render failed'),
    );
    for (var i = 0; i < 5; i++) {
      final source = service.sourceForPickedFile(
        XppPickedFile(Uint8List.fromList([i])),
      );
      await expectLater(
        service.request(source, 1, PdfBackgroundRenderVariant.full),
        throwsStateError,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        documents.where((doc) => !doc.disposed).length,
        lessThanOrEqualTo(1),
      );
    }
    await service.dispose();
  });

  test(
    'canceling an owner removes obsolete queued and cache-reading work',
    () async {
      final readStarted = Completer<void>();
      final releaseRead = Completer<Uint8List?>();
      final rendered = <int?>[];
      var reads = 0;
      final service = _testService(
        cacheReader: (_) {
          if (++reads == 1) {
            readStarted.complete();
            return releaseRead.future;
          }
          return Future.value(null);
        },
        renderer: (_, page, __) async {
          rendered.add(page);
          return Uint8List.fromList([page!]);
        },
      );
      final source = service.sourceForPickedFile(XppPickedFile(Uint8List(1)));
      final obsolete = Object();
      final first = service.request(
        source,
        1,
        PdfBackgroundRenderVariant.full,
        owner: obsolete,
      );
      final second = service.request(
        source,
        2,
        PdfBackgroundRenderVariant.full,
        owner: obsolete,
      );
      final errors = Future.wait([
        expectLater(first, throwsA(isA<PdfRenderCanceled>())),
        expectLater(second, throwsA(isA<PdfRenderCanceled>())),
      ]);
      await readStarted.future;
      service.cancelRequests(obsolete);
      final visible = service.request(
        source,
        3,
        PdfBackgroundRenderVariant.full,
        priority: PdfBackgroundRenderPriority.active,
      );
      releaseRead.complete(null);
      await errors;
      expect(await visible, [3]);
      expect(rendered, [3]);
      await service.dispose();
    },
  );

  test(
    'canceling prefetch ownership preserves shared visible requests',
    () async {
      final release = Completer<Uint8List?>();
      final service = _testService(cacheReader: (_) => release.future);
      final source = service.sourceForPickedFile(XppPickedFile(Uint8List(1)));
      final prefetchOwner = Object();
      final visibleOwner = Object();
      final prefetch = service.request(
        source,
        1,
        PdfBackgroundRenderVariant.full,
        priority: PdfBackgroundRenderPriority.prefetch,
        owner: prefetchOwner,
      );
      final visible = service.request(
        source,
        1,
        PdfBackgroundRenderVariant.full,
        priority: PdfBackgroundRenderPriority.active,
        owner: visibleOwner,
      );
      service.cancelRequests(prefetchOwner);
      release.complete(null);
      expect(await visible, [1]);
      expect(await prefetch, [1]);
      await service.dispose();
    },
  );

  test('canceled opening work does not start rendering', () async {
    final opening = Completer<void>();
    final document = Completer<PdfDocument>();
    var renders = 0;
    final service = _testService(
      documentOpener: (_) {
        opening.complete();
        return document.future;
      },
      renderer: (_, __, ___) async {
        renders++;
        return Uint8List(1);
      },
    );
    final source = service.sourceForPickedFile(XppPickedFile(Uint8List(1)));
    final owner = Object();
    final request = service.request(
      source,
      1,
      PdfBackgroundRenderVariant.full,
      owner: owner,
    );
    final error = expectLater(request, throwsA(isA<PdfRenderCanceled>()));
    await opening.future;
    service.cancelRequests(owner);
    document.complete(_FakePdfDocument('opening'));
    await error;
    await service.dispose();
    expect(renders, 0);
  });

  test('dispose drains native rendering before closing the document', () async {
    final started = Completer<void>();
    final release = Completer<Uint8List>();
    final document = _FakePdfDocument('drain');
    final service = _testService(
      documentOpener: (_) async => document,
      renderer: (_, __, ___) {
        started.complete();
        return release.future;
      },
    );
    final source = service.sourceForPickedFile(XppPickedFile(Uint8List(1)));
    final request = service.request(source, 1, PdfBackgroundRenderVariant.full);
    final error = expectLater(request, throwsA(isA<PdfRenderCanceled>()));
    await started.future;
    var disposed = false;
    final disposal = service.dispose().then((_) => disposed = true);
    await Future<void>.delayed(Duration.zero);
    expect(disposed, isFalse);
    expect(document.disposed, isFalse);
    await expectLater(
      service.request(source, 2, PdfBackgroundRenderVariant.full),
      throwsStateError,
    );
    release.complete(Uint8List.fromList([7]));
    await error;
    await disposal;
    expect(document.disposed, isTrue);
    expect(
      service.peek(service.keyFor(source, 1, PdfBackgroundRenderVariant.full)),
      isNull,
    );
    await service.dispose();
  });

  test(
    'late cache writer completion cannot repopulate a disposed service',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final service = _testService(
        cacheWriter: (_, __) async {
          started.complete();
          await release.future;
        },
      );
      final source = service.sourceForPickedFile(XppPickedFile(Uint8List(1)));
      await service.request(source, 1, PdfBackgroundRenderVariant.full);
      await started.future;
      await service.dispose();
      release.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        service.peek(
          service.keyFor(source, 1, PdfBackgroundRenderVariant.full),
        ),
        isNull,
      );
    },
  );

  test(
    'file revision changes invalidate source, session, and raster identity',
    () async {
      var revision = 'first';
      var opens = 0;
      final service = _testService(
        sourceRevision: (_) async => revision,
        sourceReader: (_) async => Uint8List.fromList(revision.codeUnits),
        documentOpener: (_) async {
          opens++;
          return _FakePdfDocument('revision');
        },
      );
      Future<XppPickedFile> fallback() async =>
          throw StateError('unexpected recovery');
      final first = await service.sourceForPath(
        '/document.pdf',
        fallback: fallback,
      );
      await service.request(first, 1, PdfBackgroundRenderVariant.full);
      final same = await service.sourceForPath(
        '/document.pdf',
        fallback: fallback,
      );
      expect(same.id, first.id);
      revision = 'replaced';
      final replacement = await service.sourceForPath(
        '/document.pdf',
        fallback: fallback,
      );
      expect(replacement.id, isNot(first.id));
      await service.request(replacement, 1, PdfBackgroundRenderVariant.full);
      expect(opens, 2);
      await service.dispose();
    },
  );

  test(
    'picked source identity includes middle bytes even for the same URI',
    () async {
      final service = _testService();
      final original = Uint8List(512);
      final changed = Uint8List(512)..[256] = 1;
      final first = service.sourceForPickedFile(
        XppPickedFile(original, path: 'content://same'),
      );
      final second = service.sourceForPickedFile(
        XppPickedFile(changed, path: 'content://same'),
      );
      expect(first.id, isNot(second.id));
      await service.dispose();
    },
  );

  test('source lookup checks lifetime before invoking UI recovery', () async {
    final revision = Completer<String?>();
    var current = true;
    var recovery = 0;
    final service = _testService(sourceRevision: (_) => revision.future);
    final lookup = service.sourceForPath(
      '/missing.pdf',
      isCurrent: () => current,
      fallback: () async {
        recovery++;
        return XppPickedFile(Uint8List(1));
      },
    );
    final error = expectLater(lookup, throwsA(isA<PdfRenderCanceled>()));
    current = false;
    revision.complete(null);
    await error;
    expect(recovery, 0);
    await service.dispose();
  });

  test(
    'concurrent source callers do not inherit another caller recovery',
    () async {
      final firstRecovery = Completer<XppPickedFile>();
      final service = _testService(sourceRevision: (_) async => null);
      final first = service.sourceForPath(
        '/missing.pdf',
        fallback: () => firstRecovery.future,
      );
      final second = await service.sourceForPath(
        '/missing.pdf',
        fallback: () async => XppPickedFile(Uint8List.fromList([2])),
      );
      firstRecovery.complete(XppPickedFile(Uint8List.fromList([1])));
      expect((await first).id, isNot(second.id));
      await service.dispose();
    },
  );

  test('failed document opening can be retried', () async {
    var opens = 0;
    final service = _testService(
      documentOpener: (_) async {
        if (++opens == 1) throw StateError('temporary failure');
        return _FakePdfDocument('retry');
      },
    );
    final source = service.sourceForPickedFile(XppPickedFile(Uint8List(1)));
    await expectLater(
      service.request(source, 1, PdfBackgroundRenderVariant.full),
      throwsStateError,
    );
    expect(await service.request(source, 1, PdfBackgroundRenderVariant.full), [
      1,
    ]);
    await service.dispose();
  });

  test('deduplicates concurrent requests for the same page', () async {
    var renderCount = 0;
    final service = _testService(
      renderer: (_, __, ___) async {
        renderCount++;
        await Future<void>.delayed(Duration.zero);
        return Uint8List.fromList([1, 2, 3]);
      },
    );
    final source = service.sourceForPickedFile(
      XppPickedFile(Uint8List.fromList([1, 2, 3]), path: 'a.pdf'),
    );

    final first = service.request(source, 1, PdfBackgroundRenderVariant.full);
    final second = service.request(source, 1, PdfBackgroundRenderVariant.full);

    expect(await first, [1, 2, 3]);
    expect(await second, [1, 2, 3]);
    expect(renderCount, 1);

    await service.dispose();
  });

  test('serves later requests from memory cache', () async {
    var renderCount = 0;
    final service = _testService(
      renderer: (_, __, ___) async {
        renderCount++;
        return Uint8List.fromList([4, 5, 6]);
      },
    );
    final source = service.sourceForPickedFile(
      XppPickedFile(Uint8List.fromList([4, 5, 6]), path: 'b.pdf'),
    );

    await service.request(source, 2, PdfBackgroundRenderVariant.full);
    final cached = await service.request(
      source,
      2,
      PdfBackgroundRenderVariant.full,
    );

    expect(cached, [4, 5, 6]);
    expect(renderCount, 1);

    await service.dispose();
  });

  test('completes rendered requests before cache writer finishes', () async {
    final writerStarted = Completer<void>();
    final writerRelease = Completer<void>();
    var writerCompleted = false;
    final service = _testService(
      renderer: (_, __, ___) async => Uint8List.fromList([10, 11, 12]),
      cacheWriter: (_, __) async {
        writerStarted.complete();
        await writerRelease.future;
        writerCompleted = true;
      },
    );
    final source = service.sourceForPickedFile(
      XppPickedFile(Uint8List.fromList([10]), path: 'cache-wait.pdf'),
    );

    final bytes = await service.request(
      source,
      1,
      PdfBackgroundRenderVariant.full,
    );

    expect(bytes, [10, 11, 12]);
    await writerStarted.future;
    expect(writerCompleted, isFalse);

    writerRelease.complete();
    await Future<void>.delayed(Duration.zero);
    await service.dispose();
  });

  test('publishes ready snapshot before cache writer finishes', () async {
    final writerStarted = Completer<void>();
    final writerRelease = Completer<void>();
    var writerCompleted = false;
    final service = _testService(
      renderer: (_, __, ___) async => Uint8List.fromList([13]),
      cacheWriter: (_, __) async {
        writerStarted.complete();
        await writerRelease.future;
        writerCompleted = true;
      },
    );
    final source = service.sourceForPickedFile(
      XppPickedFile(Uint8List.fromList([13]), path: 'snapshot-wait.pdf'),
    );
    final key = service.keyFor(source, 1, PdfBackgroundRenderVariant.full);
    final readySnapshot = Completer<PdfBackgroundRenderSnapshot>();
    final subscription = service.watch(key).listen((snapshot) {
      if (snapshot.bytes != null && !readySnapshot.isCompleted) {
        readySnapshot.complete(snapshot);
      }
    });

    final request = service.request(source, 1, PdfBackgroundRenderVariant.full);
    final snapshot = await readySnapshot.future;

    expect(snapshot.bytes, [13]);
    expect(await request, [13]);
    await writerStarted.future;
    expect(writerCompleted, isFalse);

    writerRelease.complete();
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    await service.dispose();
  });

  test('cache writer failures do not fail rendered requests', () async {
    final service = _testService(
      renderer: (_, __, ___) async => Uint8List.fromList([14]),
      cacheWriter: (_, __) async {
        throw StateError('disk full');
      },
    );
    final source = service.sourceForPickedFile(
      XppPickedFile(Uint8List.fromList([14]), path: 'writer-fails.pdf'),
    );

    final bytes = await service.request(
      source,
      1,
      PdfBackgroundRenderVariant.full,
    );

    expect(bytes, [14]);
    await Future<void>.delayed(Duration.zero);
    await service.dispose();
  });

  test(
    'same-key requests reuse in-flight result while writer is pending',
    () async {
      final writerStarted = Completer<void>();
      final writerRelease = Completer<void>();
      var renderCount = 0;
      final service = _testService(
        renderer: (_, __, ___) async {
          renderCount++;
          return Uint8List.fromList([15]);
        },
        cacheWriter: (_, __) async {
          writerStarted.complete();
          await writerRelease.future;
        },
      );
      final source = service.sourceForPickedFile(
        XppPickedFile(Uint8List.fromList([15]), path: 'pending-writer.pdf'),
      );

      expect(
        await service.request(source, 1, PdfBackgroundRenderVariant.full),
        [15],
      );
      await writerStarted.future;
      expect(
        await service.request(source, 1, PdfBackgroundRenderVariant.full),
        [15],
      );
      expect(renderCount, 1);

      writerRelease.complete();
      await Future<void>.delayed(Duration.zero);
      await service.dispose();
    },
  );

  test('reuses an open document session for the same source', () async {
    var openCount = 0;
    final service = _testService(
      documentOpener: (source) async {
        openCount++;
        return _FakePdfDocument(source.sourceName);
      },
      renderer: (_, page, ___) async => Uint8List.fromList([page ?? 0]),
    );
    final source = service.sourceForPickedFile(
      XppPickedFile(Uint8List.fromList([7, 8, 9]), path: 'c.pdf'),
    );

    await service.request(source, 1, PdfBackgroundRenderVariant.full);
    await service.request(source, 2, PdfBackgroundRenderVariant.full);

    expect(openCount, 1);

    await service.dispose();
  });

  test('evicts least recently used memory entries', () async {
    final service = _testService(
      maxMemoryEntries: 1,
      renderer: (_, page, ___) async => Uint8List.fromList([page ?? 0]),
    );
    final source = service.sourceForPickedFile(
      XppPickedFile(Uint8List.fromList([7, 8, 9]), path: 'd.pdf'),
    );

    final firstKey = service.keyFor(source, 1, PdfBackgroundRenderVariant.full);
    final secondKey = service.keyFor(
      source,
      2,
      PdfBackgroundRenderVariant.full,
    );

    await service.request(source, 1, PdfBackgroundRenderVariant.full);
    await service.request(source, 2, PdfBackgroundRenderVariant.full);
    await Future<void>.delayed(Duration.zero);

    expect(service.peek(firstKey), isNull);
    expect(service.peek(secondKey), [2]);

    await service.dispose();
  });

  test('publishes loading and ready snapshots', () async {
    final service = _testService(
      renderer: (_, __, ___) async => Uint8List.fromList([9]),
    );
    final source = service.sourceForPickedFile(
      XppPickedFile(Uint8List.fromList([9]), path: 'e.pdf'),
    );
    final key = service.keyFor(source, 1, PdfBackgroundRenderVariant.full);
    final snapshots = <PdfBackgroundRenderSnapshot>[];
    final subscription = service.watch(key).listen(snapshots.add);

    await service.request(source, 1, PdfBackgroundRenderVariant.full);
    await Future<void>.delayed(Duration.zero);

    expect(snapshots.map((snapshot) => snapshot.isLoading), contains(true));
    expect(snapshots.any((snapshot) => snapshot.bytes != null), isTrue);

    await subscription.cancel();
    await service.dispose();
  });

  test('prioritizes active requests ahead of queued prefetches', () async {
    final firstRender = Completer<void>();
    final renderedPages = <int?>[];
    final service = _testService(
      renderer: (_, page, ___) async {
        renderedPages.add(page);
        if (page == 1) await firstRender.future;
        return Uint8List.fromList([page ?? 0]);
      },
    );
    final source = service.sourceForPickedFile(
      XppPickedFile(Uint8List.fromList([1]), path: 'f.pdf'),
    );

    final first = service.request(
      source,
      1,
      PdfBackgroundRenderVariant.full,
      priority: PdfBackgroundRenderPriority.prefetch,
    );
    final second = service.request(
      source,
      2,
      PdfBackgroundRenderVariant.full,
      priority: PdfBackgroundRenderPriority.prefetch,
    );
    final active = service.request(
      source,
      3,
      PdfBackgroundRenderVariant.full,
      priority: PdfBackgroundRenderPriority.active,
    );

    firstRender.complete();
    await Future.wait([first, second, active]);

    expect(renderedPages, [1, 3, 2]);

    await service.dispose();
  });

  test('full page render sizes snap to dpi buckets', () {
    final service = _testService();

    sizeForDpi(double dpi) => service.renderSizeFor(
      PdfBackgroundRenderVariant.full,
      targetWidth: 720 / 72 * dpi,
      targetHeight: 1080 / 72 * dpi,
      pageWidthPoints: 720,
      pageHeightPoints: 1080,
    );

    expect(sizeForDpi(72).cachePart, '960x1440');
    expect(sizeForDpi(120).cachePart, '1920x2880');
    expect(sizeForDpi(220).cachePart, '2000x3000');
    expect(sizeForDpi(320).cachePart, '2000x3000');
  });

  test('cache keys reuse full page dpi buckets', () {
    final service = _testService();
    final source = service.sourceForPickedFile(
      XppPickedFile(Uint8List.fromList([1]), path: 'g.pdf'),
    );

    final first96Dpi = service.keyFor(
      source,
      1,
      PdfBackgroundRenderVariant.full,
      targetWidth: 800,
      targetHeight: 1200,
      pageWidthPoints: 720,
      pageHeightPoints: 1080,
    );
    final second96Dpi = service.keyFor(
      source,
      1,
      PdfBackgroundRenderVariant.full,
      targetWidth: 900,
      targetHeight: 1350,
      pageWidthPoints: 720,
      pageHeightPoints: 1080,
    );
    final dpi192 = service.keyFor(
      source,
      1,
      PdfBackgroundRenderVariant.full,
      targetWidth: 1600,
      targetHeight: 2400,
      pageWidthPoints: 720,
      pageHeightPoints: 1080,
    );

    expect(first96Dpi, second96Dpi);
    expect(first96Dpi, isNot(dpi192));
  });

  test('uses fallback when a direct file path is missing', () async {
    var fallbackCount = 0;
    final service = _testService();

    final source = await service.sourceForPath(
      '/definitely/missing/background.pdf',
      fallback: () async {
        fallbackCount++;
        return XppPickedFile(Uint8List.fromList([1, 2, 3]));
      },
    );

    expect(fallbackCount, 1);
    expect(source.bytes, [1, 2, 3]);

    await service.dispose();
  });

  test('does not cache failed missing-file fallback selections', () async {
    var fallbackCount = 0;
    final service = _testService();

    Future<XppPickedFile> failingFallback() async {
      fallbackCount++;
      throw UnsupportedError('not selected');
    }

    await expectLater(
      service.sourceForPath(
        '/definitely/missing/retry.pdf',
        fallback: failingFallback,
      ),
      throwsUnsupportedError,
    );
    await expectLater(
      service.sourceForPath(
        '/definitely/missing/retry.pdf',
        fallback: failingFallback,
      ),
      throwsUnsupportedError,
    );

    expect(fallbackCount, 2);

    await service.dispose();
  });
}

PdfBackgroundRenderService _testService({
  PdfBackgroundPageRenderer? renderer,
  PdfBackgroundDocumentOpener? documentOpener,
  PdfBackgroundCacheReader? cacheReader,
  PdfBackgroundCacheWriter? cacheWriter,
  PdfBackgroundSourceRevision? sourceRevision,
  PdfBackgroundSourceReader? sourceReader,
  int maxMemoryEntries = 32,
  int maxOpenDocuments = 3,
}) {
  final cache = <String, Uint8List>{};
  return PdfBackgroundRenderService(
    sourceRevision: sourceRevision,
    sourceReader: sourceReader,
    maxMemoryEntries: maxMemoryEntries,
    maxOpenDocuments: maxOpenDocuments,
    cacheReader: cacheReader ?? (key) async => cache[key],
    cacheWriter:
        cacheWriter ??
        (key, bytes) async {
          cache[key] = bytes;
        },
    documentOpener:
        documentOpener ?? (source) async => _FakePdfDocument(source.sourceName),
    renderer:
        renderer ?? (_, page, __) async => Uint8List.fromList([page ?? 0]),
  );
}

class _FakePdfDocument extends PdfDocument {
  _FakePdfDocument(String sourceName) : super(sourceName: sourceName);

  List<PdfPage> _pages = [];
  bool disposed = false;

  @override
  PdfPermissions? get permissions => null;

  @override
  bool get isEncrypted => false;

  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();

  @override
  List<PdfPage> get pages => _pages;

  @override
  set pages(List<PdfPage> value) => _pages = value;

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<List<PdfOutlineNode>> loadOutline() async => [];

  @override
  bool isIdenticalDocumentHandle(Object? other) => identical(this, other);

  @override
  Future<bool> assemble() async => true;

  @override
  Future<Uint8List> encodePdf({
    bool incremental = false,
    bool removeSecurity = false,
  }) async => Uint8List(0);

  @override
  Future<T> useNativeDocumentHandle<T>(
    FutureOr<T> Function(int nativeDocumentHandle) task,
  ) async {
    return task(0);
  }

  @override
  Future<void> reloadPages({List<int>? pageNumbersToReload}) async {}

  @override
  Future<void> loadPagesProgressively<T>({
    int? startPageNumber,
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
  }) async {}
}
