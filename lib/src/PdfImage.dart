import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';
import 'package:printing/printing.dart';
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
  return _withPdfDocument(
    pdf,
    (document) async => document.pagesCount,
    fallback: (bytes) async => (await _rasterPageSizes(bytes)).length,
  );
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
  return _withPdfDocument(
    pdf,
    (document) async {
      final pdfPage = await document.getPage(_pageNumber(page, document));
      try {
        final image = await pdfPage.render(
          width: _pixelsForPoints(pdfPage.width, dpi),
          height: _pixelsForPoints(pdfPage.height, dpi),
          format: PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
          forPrint: true,
        );
        if (image == null) throw StateError('Could not render PDF page.');
        return image.bytes;
      } finally {
        await pdfPage.close();
      }
    },
    fallback: (bytes) {
      final pageNumber = page ?? 1;
      final pageIndex = pageNumber <= 0 ? 0 : pageNumber - 1;
      return Printing.raster(
        bytes,
        pages: [pageIndex],
        dpi: dpi,
      ).single.then((raster) => raster.toPng());
    },
  );
}

Future<XppPageSize> pdfPageSize(XppPickedFile pdf, int page) {
  return _withPdfDocument(pdf, (document) async {
    final pdfPage = await document.getPage(_pageNumber(page + 1, document));
    try {
      return _pageSize(pdfPage);
    } finally {
      await pdfPage.close();
    }
  }, fallback: (bytes) => _rasterPageSize(bytes, page));
}

Future<List<XppPageSize>> pdfPageSizes(XppPickedFile pdf) {
  return _withPdfDocument(pdf, (document) async {
    final sizes = <XppPageSize>[];
    for (var pageNumber = 1; pageNumber <= document.pagesCount; pageNumber++) {
      final pdfPage = await document.getPage(pageNumber);
      try {
        sizes.add(_pageSize(pdfPage));
      } finally {
        await pdfPage.close();
      }
    }
    return sizes;
  }, fallback: _rasterPageSizes);
}

Future<T> _withPdfDocument<T>(
  XppPickedFile pdf,
  Future<T> Function(PdfDocument document) callback, {
  required Future<T> Function(Uint8List bytes) fallback,
}) async {
  final bytes = pdf.toUint8List();
  if (!await hasPdfSupport()) return fallback(bytes);

  final document = await PdfDocument.openData(bytes);
  try {
    return await callback(document);
  } finally {
    await document.close();
  }
}

XppPageSize _pageSize(PdfPage page) {
  return XppPageSize(width: page.width, height: page.height);
}

int _pageNumber(int? page, PdfDocument document) {
  final pageNumber = page ?? 1;
  return pageNumber.clamp(1, document.pagesCount).toInt();
}

Future<XppPageSize> _rasterPageSize(Uint8List bytes, int page) async {
  final raster = await Printing.raster(bytes, pages: [page], dpi: DPI).single;
  return _rasterSize(raster);
}

Future<List<XppPageSize>> _rasterPageSizes(Uint8List bytes) {
  return Printing.raster(bytes, dpi: DPI).map(_rasterSize).toList();
}

XppPageSize _rasterSize(PdfRaster raster) {
  return XppPageSize(
    width: raster.width / DPI * _pdfPointsPerInch,
    height: raster.height / DPI * _pdfPointsPerInch,
  );
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

double _pixelsForPoints(double points, double dpi) {
  return points / _pdfPointsPerInch * dpi;
}
