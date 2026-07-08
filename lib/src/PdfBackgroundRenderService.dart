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
  full('full', pdfFullPageMaxDimension),
  thumbnail('thumb', pdfThumbnailMaxDimension);

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

const List<double> pdfFullPageDpiBuckets = [96, 192, 256];
const double _pdfPointsPerInch = 72;

class PdfBackgroundRenderService {
  PdfBackgroundRenderService({
    PdfBackgroundPageRenderer? renderer,
    PdfBackgroundDocumentOpener? documentOpener,
    PdfBackgroundCacheReader? cacheReader,
    PdfBackgroundCacheWriter? cacheWriter,
    int maxMemoryEntries = 40,
    int maxOpenDocuments = 3,
  }) : _renderer = renderer ?? renderPdfDocumentPageBytes,
       _documentOpener = documentOpener ?? _openDefaultDocument,
       _cacheReader = cacheReader ?? readCacheFile,
       _cacheWriter = cacheWriter ?? _writeDefaultCacheFile,
       _maxMemoryEntries = maxMemoryEntries,
       _maxOpenDocuments = maxOpenDocuments;

  final PdfBackgroundPageRenderer _renderer;
  final PdfBackgroundDocumentOpener _documentOpener;
  final PdfBackgroundCacheReader _cacheReader;
  final PdfBackgroundCacheWriter _cacheWriter;
  final int _maxMemoryEntries;
  final int _maxOpenDocuments;

  final _memoryCache = LinkedHashMap<String, Uint8List>();
  final _sourceFutures = <String, Future<PdfBackgroundRenderSource>>{};
  final _sessions = LinkedHashMap<String, _PdfSourceSession>();
  final _inFlight = <String, Future<Uint8List>>{};
  final _queuedTasks = <_PdfRenderTask>[];
  final _controllers =
      <String, StreamController<PdfBackgroundRenderSnapshot>>{};
  bool _isProcessingQueue = false;

  Future<PdfBackgroundRenderSource> sourceForPath(
    String? path, {
    required Future<XppPickedFile> Function() fallback,
  }) {
    final cacheKey = path == null || path.isEmpty ? 'missing' : path;
    final existing = _sourceFutures[cacheKey];
    if (existing != null) return existing;

    late Future<PdfBackgroundRenderSource> sourceFuture;
    sourceFuture =
        () async {
          if (_canOpenFileDirectly(path) && await localPathExists(path!)) {
            return _registerFileSource(path);
          }
          final picked = await fallback();
          return sourceForPickedFile(picked);
        }().catchError((error) {
          if (identical(_sourceFutures[cacheKey], sourceFuture)) {
            _sourceFutures.remove(cacheKey);
          }
          throw error;
        });
    _sourceFutures[cacheKey] = sourceFuture;
    return sourceFuture;
  }

  PdfBackgroundRenderSource sourceForPickedFile(XppPickedFile pdf) {
    final path = pdf.path;
    if (_canOpenFileDirectly(path)) {
      return _registerFileSource(path!);
    }

    final bytes = pdf.toUint8List();
    final sourceName =
        path ?? pdf.fileName ?? 'memory:${identityHashCode(pdf)}';
    return _registerSource(
      PdfBackgroundRenderSource(
        id: stablePdfHash(path ?? pdfBytesSignature(bytes)),
        sourceName: sourceName,
        bytes: bytes,
      ),
    );
  }

  PdfBackgroundRenderSource _registerFileSource(String path) {
    return _registerSource(
      PdfBackgroundRenderSource(
        id: stablePdfHash(path),
        sourceName: path,
        filePath: path,
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
    if (variant == PdfBackgroundRenderVariant.full &&
        pageWidthPoints != null &&
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
  }) {
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
      _raiseQueuedPriority(key, priority);
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
      ),
    );
    _emit(PdfBackgroundRenderSnapshot(key: key, isLoading: true));
    _processQueue();
    return _inFlight[key]!;
  }

  void cancelPrefetchesExcept(Set<String> keepKeys) {
    for (final task in List<_PdfRenderTask>.from(_queuedTasks)) {
      if (task.priority != PdfBackgroundRenderPriority.prefetch) continue;
      if (keepKeys.contains(task.key)) continue;
      _queuedTasks.remove(task);
      _inFlight.remove(task.key);
      task.completer.completeError(StateError('PDF render prefetch canceled.'));
      _emit(PdfBackgroundRenderSnapshot(key: task.key, isLoading: false));
    }
  }

  void clearMemoryCache() {
    _memoryCache.clear();
  }

  Future<void> dispose() async {
    for (final task in _queuedTasks) {
      task.completer.completeError(StateError('PDF render service disposed.'));
    }
    _queuedTasks.clear();
    for (final session in _sessions.values) {
      await session.dispose();
    }
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
    _sessions.clear();
    _memoryCache.clear();
    _inFlight.clear();
  }

  PdfBackgroundRenderSource _registerSource(PdfBackgroundRenderSource source) {
    _sessions.putIfAbsent(
      source.id,
      () => _PdfSourceSession(source: source, opener: _documentOpener),
    );
    return source;
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    try {
      while (_queuedTasks.isNotEmpty) {
        _queuedTasks.sort(
          (a, b) => b.priority.order.compareTo(a.priority.order),
        );
        final task = _queuedTasks.removeAt(0);
        if (task.completer.isCompleted) continue;
        await _runTask(task);
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _runTask(_PdfRenderTask task) async {
    try {
      final cached = await _cacheReader(task.key);
      if (cached != null) {
        _emit(PdfBackgroundRenderSnapshot(key: task.key, bytes: cached));
        task.completer.complete(cached);
        _persistRasterInBackground(task, cached, writeCacheFile: false);
        return;
      }

      final document = await _sessionFor(task.source).document();
      final bytes = await _renderer(document, task.page, task.size);
      _emit(PdfBackgroundRenderSnapshot(key: task.key, bytes: bytes));
      task.completer.complete(bytes);
      _persistRasterInBackground(task, bytes, writeCacheFile: true);
      await _evictIdleDocuments();
    } catch (error, stackTrace) {
      if (task.completer.isCompleted) return;
      _inFlight.remove(task.key);
      _emit(PdfBackgroundRenderSnapshot(key: task.key, error: error));
      task.completer.completeError(error, stackTrace);
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
          _remember(task.key, bytes);
          if (writeCacheFile) await _cacheWriter(task.key, bytes);
        } catch (_) {}
      }).whenComplete(() {
        _inFlight.remove(task.key);
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

  void _raiseQueuedPriority(String key, PdfBackgroundRenderPriority priority) {
    for (final task in _queuedTasks) {
      if (task.key != key) continue;
      if (task.priority.order < priority.order) task.priority = priority;
      return;
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
    return _documentFuture ??= opener(source);
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
  PdfBackgroundRenderPriority priority;
  final Completer<Uint8List> completer;

  _PdfRenderTask({
    required this.key,
    required this.source,
    required this.page,
    required this.size,
    required this.priority,
    required this.completer,
  });
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
