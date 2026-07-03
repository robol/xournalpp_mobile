import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:pdfrx/pdfrx.dart';
import 'package:xournalpp/src/conditional/file_storage/file_storage_stub.dart'
    if (dart.library.io) 'package:xournalpp/src/conditional/file_storage/file_storage_io.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPickedFile.dart';

const double DPI = 192;
const double _thumbnailDpi = 36;
const double _pdfPointsPerInch = 72;
const int _maxMemoryThumbnails = 80;

final Map<String, Uint8List> _thumbnailMemoryCache = {};
final Map<String, Future<Uint8List>> _thumbnailRequests = {};
final Map<String, Future<Uint8List>> _fullPageRequests = {};

Future<int> pdfPageCount(XppPickedFile pdf) {
  return _withPdfDocument(pdf, (document) async => document.pages.length);
}

Future<Uint8List> pdfImage(XppPickedFile pdf, int? page) {
  final cacheKey = _cacheKey(pdf, page, DPI, 'full');
  return _fullPageRequests
      .putIfAbsent(cacheKey, () async {
        final cached = await readCacheFile(cacheKey);
        if (cached != null) return cached;

        final bytes = await _renderPdfImage(pdf, page, DPI);
        await writeCacheFile(cacheKey, bytes);
        return bytes;
      })
      .whenComplete(() => _fullPageRequests.remove(cacheKey));
}

Future<Uint8List> pdfThumbnailImage(XppPickedFile pdf, int? page) {
  final cacheKey = _cacheKey(pdf, page, _thumbnailDpi, 'thumb');
  final cached = _thumbnailMemoryCache[cacheKey];
  if (cached != null) return Future.value(cached);

  return _thumbnailRequests
      .putIfAbsent(cacheKey, () async {
        final bytes = await _renderPdfImage(pdf, page, _thumbnailDpi);
        if (_thumbnailMemoryCache.length >= _maxMemoryThumbnails) {
          _thumbnailMemoryCache.remove(_thumbnailMemoryCache.keys.first);
        }
        _thumbnailMemoryCache[cacheKey] = bytes;
        return bytes;
      })
      .whenComplete(() => _thumbnailRequests.remove(cacheKey));
}

Future<Uint8List> _renderPdfImage(XppPickedFile pdf, int? page, double dpi) {
  return _withPdfDocument(pdf, (document) async {
    final pdfPage = document.pages[_pageIndex(page, document)];
    final scale = dpi / _pdfPointsPerInch;
    final rendered = await pdfPage.render(
      fullWidth: pdfPage.width * scale,
      fullHeight: pdfPage.height * scale,
      backgroundColor: 0xffffffff,
    );
    if (rendered == null) throw StateError('Could not render PDF page.');
    try {
      final png = image.encodePng(rendered.createImageNF());
      return Uint8List.fromList(png);
    } finally {
      rendered.dispose();
    }
  });
}

Future<XppPageSize> pdfPageSize(XppPickedFile pdf, int page) {
  return _withPdfDocument(pdf, (document) async {
    return _pageSize(document.pages[_pageIndex(page + 1, document)]);
  });
}

Future<List<XppPageSize>> pdfPageSizes(XppPickedFile pdf) {
  return _withPdfDocument(pdf, (document) async {
    return document.pages.map(_pageSize).toList();
  });
}

Future<T> _withPdfDocument<T>(
  XppPickedFile pdf,
  Future<T> Function(PdfDocument document) callback,
) async {
  final document = await PdfDocument.openData(
    pdf.toUint8List(),
    sourceName: pdf.path ?? pdf.fileName ?? 'memory:${identityHashCode(pdf)}',
    allowDataOwnershipTransfer: false,
  );
  try {
    return await callback(document);
  } finally {
    await document.dispose();
  }
}

XppPageSize _pageSize(PdfPage page) {
  return XppPageSize(width: page.width, height: page.height);
}

int _pageIndex(int? page, PdfDocument document) {
  final pageNumber = page ?? 1;
  return pageNumber.clamp(1, document.pages.length).toInt() - 1;
}

String _cacheKey(XppPickedFile pdf, int? page, double dpi, String variant) {
  final source = pdf.path ?? _bytesSignature(pdf.toUint8List());
  return 'pdf_${variant}_${_stableHash(source)}_${page ?? 1}_${dpi.round()}.png';
}

String _bytesSignature(Uint8List bytes) {
  final buffer = StringBuffer(bytes.length);
  final sampleLength = bytes.length < 64 ? bytes.length : 64;
  for (var i = 0; i < sampleLength; i++) {
    buffer.writeCharCode(bytes[i]);
  }
  for (var i = bytes.length - sampleLength; i < bytes.length; i++) {
    if (i >= sampleLength && i >= 0) buffer.writeCharCode(bytes[i]);
  }
  return buffer.toString();
}

String _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16);
}
