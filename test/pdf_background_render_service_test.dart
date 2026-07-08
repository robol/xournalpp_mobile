import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xournalpp/src/PdfBackgroundRenderService.dart';
import 'package:xournalpp/src/XppPickedFile.dart';

void main() {
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
  int maxMemoryEntries = 32,
}) {
  final cache = <String, Uint8List>{};
  return PdfBackgroundRenderService(
    maxMemoryEntries: maxMemoryEntries,
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
  Future<void> dispose() async {}

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
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
  }) async {}
}
