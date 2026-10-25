import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xournalpp/src/PdfImage.dart';
import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:xournalpp/src/conditional/file_storage/file_storage_stub.dart'
    if (dart.library.io) 'package:xournalpp/src/conditional/file_storage/file_storage_io.dart';

enum PdfBackgroundRenderVariant {
  full('full', pdfFullPageMaxDimension);

  final String cacheVariant;
  final int maxDimension;

  const PdfBackgroundRenderVariant(this.cacheVariant, this.maxDimension);
}

enum PdfBackgroundRenderPriority {
  prefetch(0),
  visible(1),
  active(2);

  final int order;

  const PdfBackgroundRenderPriority(this.order);
}

class PdfBackgroundRenderSource {
  final String id;
  final String sourceName;
  final String? filePath;
  final Uint8List? bytes;

  const PdfBackgroundRenderSource({
    required this.id,
    required this.sourceName,
    this.filePath,
    this.bytes,
  });
}

class PdfBackgroundRenderSnapshot {
  final String key;
  final Uint8List? bytes;
  final bool isLoading;
  final Object? error;

  const PdfBackgroundRenderSnapshot({
    required this.key,
    this.bytes,
    this.isLoading = false,
    this.error,
  });

  bool get hasData => bytes != null;
}

typedef PdfBackgroundPageRenderer =
    Future<Uint8List> Function(
      PdfDocument document,
      int? page,
      PdfRenderPixelSize size,
    );
typedef PdfBackgroundDocumentOpener =
    Future<PdfDocument> Function(PdfBackgroundRenderSource source);
typedef PdfBackgroundCacheReader = Future<Uint8List?> Function(String key);
typedef PdfBackgroundCacheWriter =
    Future<void> Function(String key, Uint8List bytes);
typedef PdfBackgroundSourceRevision = Future<String?> Function(String path);
typedef PdfBackgroundSourceReader = Future<Uint8List> Function(String path);

class PdfRenderCanceled implements Exception {
  const PdfRenderCanceled();
}

const List<double> pdfFullPageDpiBuckets = [96, 192, 256];
const double _pdfPointsPerInch = 72;

class PdfBackgroundRenderService {
  PdfBackgroundRenderService({
    PdfBackgroundPageRenderer? renderer,
    PdfBackgroundDocumentOpener? documentOpener,
    PdfBackgroundCacheReader? cacheReader,
    PdfBackgroundCacheWriter? cacheWriter,
    PdfBackgroundSourceRevision? sourceRevision,
    PdfBackgroundSourceReader? sourceReader,
    int maxMemoryEntries = 40,
    int maxOpenDocuments = 3,
  }) : _renderer = renderer ?? renderPdfDocumentPageBytes,
       _documentOpener = documentOpener ?? _openDefaultDocument,
       _cacheReader = cacheReader ?? readCacheFile,
       _cacheWriter = cacheWriter ?? _writeDefaultCacheFile,
       _sourceRevision = sourceRevision ?? localFileRevision,
       _sourceReader = sourceReader ?? readFileBytes,
       _maxMemoryEntries = maxMemoryEntries,
       _maxOpenDocuments = maxOpenDocuments;

  final PdfBackgroundPageRenderer _renderer;
  final PdfBackgroundDocumentOpener _documentOpener;
  final PdfBackgroundCacheReader _cacheReader;
  final PdfBackgroundCacheWriter _cacheWriter;
  final PdfBackgroundSourceRevision _sourceRevision;
  final PdfBackgroundSourceReader _sourceReader;
  final int _maxMemoryEntries;
  final int _maxOpenDocuments;

  final _memoryCache = LinkedHashMap<String, Uint8List>();
  final _sessions = LinkedHashMap<String, _PdfSourceSession>();
  final _inFlight = <String, Future<Uint8List>>{};
  final _queuedTasks = <_PdfRenderTask>[];
  final _controllers =
      <String, StreamController<PdfBackgroundRenderSnapshot>>{};
  bool _isProcessingQueue = false;
  bool _disposed = false;
  _PdfRenderTask? _activeTask;
  Completer<void>? _queueDrained;
  Future<void>? _disposeFuture;

  Future<PdfBackgroundRenderSource> sourceForPath(
    String? path, {
    required Future<XppPickedFile> Function() fallback,
    bool Function()? isCurrent,
  }) async {
    void checkCurrent() {
      _checkNotDisposed();
      if (isCurrent != null && !isCurrent()) throw const PdfRenderCanceled();
    }

    checkCurrent();
    if (path != null && path.isNotEmpty) {
      Uint8List? bytes;
      try {
        final readable =
            !_canOpenFileDirectly(path) || await _sourceRevision(path) != null;
        checkCurrent();
        if (readable) bytes = await _sourceReader(path);
      } on PdfRenderCanceled {
        rethrow;
      } catch (_) {
        // Storage providers and local files both fall back to recovery only
        // after an actual read failure. Never retain a failed selection.
      }
      checkCurrent();
      if (bytes != null) {
        return sourceForPickedFile(XppPickedFile(bytes, path: path));
      }
    }
    // Do not share UI callbacks across callers or retain successful lookups
    // forever. The document owner can deduplicate recovery within its lifetime.
    final picked = await fallback();
    checkCurrent();
    return sourceForPickedFile(picked);
  }

  PdfBackgroundRenderSource sourceForPickedFile(XppPickedFile pdf) {
    _checkNotDisposed();
    final path = pdf.path;
    // Identity and native rendering must refer to exactly the same snapshot,
    // even if the path is replaced or the caller mutates its input later.
    final bytes = Uint8List.fromList(pdf.toUint8List()).asUnmodifiableView();
    final sourceName =
        path ?? pdf.fileName ?? 'memory:${identityHashCode(pdf)}';
    return _registerSource(
      PdfBackgroundRenderSource(
        id: stablePdfHash('${path ?? "memory"}:${pdfBytesSignature(bytes)}'),
        sourceName: sourceName,
        bytes: bytes,
      ),
    );
  }

  String keyFor(
    PdfBackgroundRenderSource source,
    int? page,
    PdfBackgroundRenderVariant variant, {
    double? targetWidth,
    double? targetHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
  }) {
    final size = renderSizeFor(
      variant,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      pageWidthPoints: pageWidthPoints,
      pageHeightPoints: pageHeightPoints,
    );
    return pdfImageCacheKey(source.id, page, variant.cacheVariant, size);
  }

  PdfRenderPixelSize renderSizeFor(
    PdfBackgroundRenderVariant variant, {
    double? targetWidth,
    double? targetHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
  }) {
    if (pageWidthPoints != null &&
        pageHeightPoints != null &&
        pageWidthPoints > 0 &&
        pageHeightPoints > 0) {
      return _clampToMaxDimension(
        _fullPageBucketSizeFor(
          pageWidthPoints: pageWidthPoints,
          pageHeightPoints: pageHeightPoints,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        ),
        variant.maxDimension,
      );
    }

    final maxDimension = variant.maxDimension;
    final width = max(1, (targetWidth ?? maxDimension).round());
    final height = max(1, (targetHeight ?? maxDimension).round());
    return _bucketSize(
      _clampToMaxDimension(
        PdfRenderPixelSize(width: width, height: height),
        maxDimension,
      ),
    );
  }

  Uint8List? peek(String key) {
    final bytes = _memoryCache.remove(key);
    if (bytes == null) return null;
    _memoryCache[key] = bytes;
    return bytes;
  }

  Stream<PdfBackgroundRenderSnapshot> watch(String key) {
    _checkNotDisposed();
    return _controllerFor(key).stream;
  }

  Future<Uint8List> request(
    PdfBackgroundRenderSource source,
    int? page,
    PdfBackgroundRenderVariant variant, {
    double? targetWidth,
    double? targetHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
    PdfBackgroundRenderPriority priority = PdfBackgroundRenderPriority.visible,
    Object? owner,
  }) {
    if (_disposed)
      return Future.error(StateError('PDF render service disposed.'));
    final size = renderSizeFor(
      variant,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      pageWidthPoints: pageWidthPoints,
      pageHeightPoints: pageHeightPoints,
    );
    final key = pdfImageCacheKey(source.id, page, variant.cacheVariant, size);
    final cached = peek(key);
    if (cached != null) return Future.value(cached);

    final existing = _inFlight[key];
    if (existing != null) {
      for (final task in [
        ..._queuedTasks,
        if (_activeTask != null) _activeTask!,
      ]) {
        if (task.key == key && !task.completer.isCompleted) {
          task.addOwner(owner, priority);
        }
      }
      return existing;
    }

    final completer = Completer<Uint8List>();
    _inFlight[key] = completer.future;
    _queuedTasks.add(
      _PdfRenderTask(
        key: key,
        source: source,
        page: page,
        size: size,
        priority: priority,
        completer: completer,
        owner: owner,
      ),
    );
    _emit(PdfBackgroundRenderSnapshot(key: key, isLoading: true));
    _processQueue();
    return completer.future;
  }

  /// Release only this consumer. A shared visible request must remain alive.
  void cancelRequests(Object owner) {
    for (final task in [
      ..._queuedTasks,
      if (_activeTask != null) _activeTask!,
    ]) {
      task.owners.remove(owner);
      if (task.owners.isEmpty && !task.completer.isCompleted) _cancelTask(task);
    }
  }

  void _cancelTask(_PdfRenderTask task) {
    _queuedTasks.remove(task);
    if (identical(_inFlight[task.key], task.completer.future)) {
      _inFlight.remove(task.key);
    }
    task.completer.completeError(const PdfRenderCanceled());
    _emit(PdfBackgroundRenderSnapshot(key: task.key, isLoading: false));
  }

  void cancelPrefetchesExcept(Set<String> keepKeys) {
    for (final task in List<_PdfRenderTask>.from(_queuedTasks)) {
      if (task.priority != PdfBackgroundRenderPriority.prefetch) continue;
      if (keepKeys.contains(task.key)) continue;
      _cancelTask(task);
    }
  }

  void clearMemoryCache() {
    _memoryCache.clear();
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    for (final task in [
      ..._queuedTasks,
      if (_activeTask != null) _activeTask!,
    ]) {
      if (!task.completer.isCompleted) _cancelTask(task);
    }
    // A native render cannot safely be interrupted by closing its document.
    await _queueDrained?.future;
    final sessions = _sessions.values.toList();
    final controllers = _controllers.values.toList();
    _controllers.clear();
    _sessions.clear();
    _memoryCache.clear();
    _inFlight.clear();
    for (final session in sessions) {
      await session.dispose();
    }
    for (final controller in controllers) {
      await controller.close();
    }
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('PDF render service disposed.');
  }

  PdfBackgroundRenderSource _registerSource(PdfBackgroundRenderSource source) {
    _checkNotDisposed();
    return source;
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    _queueDrained = Completer<void>();
    try {
      while (_queuedTasks.isNotEmpty) {
        _queuedTasks.sort(
          (a, b) => b.priority.order.compareTo(a.priority.order),
        );
        final task = _queuedTasks.removeAt(0);
        if (task.completer.isCompleted) continue;
        _activeTask = task;
        await _runTask(task);
        _activeTask = null;
      }
    } finally {
      _isProcessingQueue = false;
      _queueDrained!.complete();
    }
  }

  Future<void> _runTask(_PdfRenderTask task) async {
    try {
      final cached = await _cacheReader(task.key);
      if (_disposed || task.completer.isCompleted) return;
      if (cached != null) {
        _emit(PdfBackgroundRenderSnapshot(key: task.key, bytes: cached));
        task.completer.complete(cached);
        _persistRasterInBackground(task, cached, writeCacheFile: false);
        return;
      }

      final document = await _sessionFor(task.source).document();
      if (_disposed || task.completer.isCompleted) return;
      final bytes = await _renderer(document, task.page, task.size);
      if (_disposed || task.completer.isCompleted) return;
      _emit(PdfBackgroundRenderSnapshot(key: task.key, bytes: bytes));
      task.completer.complete(bytes);
      _persistRasterInBackground(task, bytes, writeCacheFile: true);
    } catch (error, stackTrace) {
      if (task.completer.isCompleted) return;
      _inFlight.remove(task.key);
      _emit(PdfBackgroundRenderSnapshot(key: task.key, error: error));
      task.completer.completeError(error, stackTrace);
    } finally {
      // Canceled and failed work can also have opened a native document.
      // The awaited open/render above has finished, so eviction is now safe.
      await _evictIdleDocuments();
    }
  }

  void _persistRasterInBackground(
    _PdfRenderTask task,
    Uint8List bytes, {
    required bool writeCacheFile,
  }) {
    unawaited(
      Future<void>(() async {
        try {
          if (_disposed) return;
          _remember(task.key, bytes);
          if (writeCacheFile) await _cacheWriter(task.key, bytes);
        } catch (_) {}
      }).whenComplete(() {
        if (identical(_inFlight[task.key], task.completer.future)) {
          _inFlight.remove(task.key);
        }
      }),
    );
  }

  _PdfSourceSession _sessionFor(PdfBackgroundRenderSource source) {
    final session =
        _sessions.remove(source.id) ??
        _PdfSourceSession(source: source, opener: _documentOpener);
    _sessions[source.id] = session..touch();
    return session;
  }

  Future<void> _evictIdleDocuments() async {
    while (_sessions.length > _maxOpenDocuments) {
      final oldestKey = _sessions.keys.first;
      final oldest = _sessions.remove(oldestKey);
      await oldest?.dispose();
    }
  }

  void _remember(String key, Uint8List bytes) {
    _memoryCache.remove(key);
    _memoryCache[key] = bytes;
    while (_memoryCache.length > _maxMemoryEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
  }

  void _emit(PdfBackgroundRenderSnapshot snapshot) {
    final controller = _controllers[snapshot.key];
    if (controller == null || controller.isClosed) return;
    controller.add(snapshot);
  }

  StreamController<PdfBackgroundRenderSnapshot> _controllerFor(String key) {
    return _controllers.putIfAbsent(
      key,
      () => StreamController<PdfBackgroundRenderSnapshot>.broadcast(
        onCancel: () {
          final controller = _controllers[key];
          if (controller != null && !controller.hasListener) {
            _controllers.remove(key);
            controller.close();
          }
        },
      ),
    );
  }
}

class _PdfSourceSession {
  final PdfBackgroundRenderSource source;
  final PdfBackgroundDocumentOpener opener;
  Future<PdfDocument>? _documentFuture;
  DateTime lastUsed = DateTime.now();

  _PdfSourceSession({required this.source, required this.opener});

  Future<PdfDocument> document() {
    touch();
    return _documentFuture ??= opener(source).catchError((Object error) {
      _documentFuture = null;
      throw error;
    });
  }

  void touch() {
    lastUsed = DateTime.now();
  }

  Future<void> dispose() async {
    final documentFuture = _documentFuture;
    _documentFuture = null;
    if (documentFuture == null) return;
    final document = await documentFuture;
    await document.dispose();
  }
}

class _PdfRenderTask {
  final String key;
  final PdfBackgroundRenderSource source;
  final int? page;
  final PdfRenderPixelSize size;
  final owners = <Object?, PdfBackgroundRenderPriority>{};
  PdfBackgroundRenderPriority get priority => owners.values.fold(
    PdfBackgroundRenderPriority.prefetch,
    (a, b) => a.order >= b.order ? a : b,
  );
  void addOwner(Object? owner, PdfBackgroundRenderPriority priority) {
    final previous = owners[owner];
    if (previous == null || priority.order > previous.order)
      owners[owner] = priority;
  }

  final Completer<Uint8List> completer;

  _PdfRenderTask({
    required this.key,
    required this.source,
    required this.page,
    required this.size,
    required PdfBackgroundRenderPriority priority,
    Object? owner,
    required this.completer,
  }) {
    addOwner(owner, priority);
  }
}

final pdfBackgroundRenderService = PdfBackgroundRenderService();

bool _canOpenFileDirectly(String? path) {
  if (kIsWeb || path == null || path.isEmpty) return false;
  if (path.startsWith('content://')) return false;
  if (path.contains('primary:')) return false;
  return true;
}

PdfRenderPixelSize _bucketSize(PdfRenderPixelSize size) {
  const bucket = 128;
  int bucketDimension(int value) {
    return max(bucket, (value / bucket).ceil() * bucket);
  }

  return PdfRenderPixelSize(
    width: bucketDimension(size.width),
    height: bucketDimension(size.height),
  );
}

PdfRenderPixelSize _fullPageBucketSizeFor({
  required double pageWidthPoints,
  required double pageHeightPoints,
  double? targetWidth,
  double? targetHeight,
}) {
  final requestedWidth = targetWidth ?? pageWidthPoints;
  final requestedHeight = targetHeight ?? pageHeightPoints;
  final requestedDpi =
      max(
        requestedWidth / pageWidthPoints,
        requestedHeight / pageHeightPoints,
      ) *
      _pdfPointsPerInch;
  final dpi = pdfFullPageDpiBuckets.firstWhere(
    (bucket) => bucket >= requestedDpi,
    orElse: () => pdfFullPageDpiBuckets.last,
  );

  return PdfRenderPixelSize(
    width: max(1, (pageWidthPoints / _pdfPointsPerInch * dpi).round()),
    height: max(1, (pageHeightPoints / _pdfPointsPerInch * dpi).round()),
  );
}

PdfRenderPixelSize _clampToMaxDimension(
  PdfRenderPixelSize size,
  int maxDimension,
) {
  final scale = min(1.0, maxDimension / max(size.width, size.height));
  return PdfRenderPixelSize(
    width: max(1, (size.width * scale).round()),
    height: max(1, (size.height * scale).round()),
  );
}

Future<PdfDocument> _openDefaultDocument(
  PdfBackgroundRenderSource source,
) async {
  final filePath = source.filePath;
  if (filePath != null && _canOpenFileDirectly(filePath)) {
    return PdfDocument.openFile(filePath);
  }
  final bytes = source.bytes;
  if (bytes == null) {
    throw StateError('PDF source ${source.sourceName} has no readable bytes.');
  }
  return PdfDocument.openData(
    bytes,
    sourceName: source.sourceName,
    allowDataOwnershipTransfer: false,
  );
}

Future<void> _writeDefaultCacheFile(String key, Uint8List bytes) async {
  await writeCacheFile(key, bytes);
}
