import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:pdfrx/pdfrx.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPickedFile.dart';

const double pdfFullPageDpi = 192;
const double pdfThumbnailDpi = 36;
const double _pdfPointsPerInch = 72;
const int pdfThumbnailMaxDimension = 360;
const int pdfFullPageMaxDimension = 3000;

class PdfRenderPixelSize {
  final int width;
  final int height;

  const PdfRenderPixelSize({required this.width, required this.height});

  String get cachePart => '${width}x$height';
}

Future<int> pdfPageCount(XppPickedFile pdf) {
  return _withPdfDocument(pdf, (document) async => document.pages.length);
}

Future<Uint8List> pdfImage(XppPickedFile pdf, int? page) {
  return renderPdfImageBytes(pdf, page, pdfFullPageDpi);
}

Future<Uint8List> pdfThumbnailImage(XppPickedFile pdf, int? page) {
  return renderPdfImageBytes(pdf, page, pdfThumbnailDpi);
}

Future<Uint8List> renderPdfImageBytes(
  XppPickedFile pdf,
  int? page,
  double dpi,
) {
  return _withPdfDocument(pdf, (document) async {
    final pdfPage = document.pages[_pageIndex(page, document)];
    final scale = dpi / _pdfPointsPerInch;
    return renderPdfDocumentPageBytes(
      document,
      page,
      PdfRenderPixelSize(
        width: (pdfPage.width * scale).round(),
        height: (pdfPage.height * scale).round(),
      ),
    );
  });
}

Future<Uint8List> renderPdfDocumentPageBytes(
  PdfDocument document,
  int? page,
  PdfRenderPixelSize targetSize,
) async {
  final pdfPage = document.pages[_pageIndex(page, document)];
  final rendered = await pdfPage.render(
    fullWidth: targetSize.width.toDouble(),
    fullHeight: targetSize.height.toDouble(),
    backgroundColor: 0xffffffff,
  );
  if (rendered == null) throw StateError('Could not render PDF page.');
  try {
    final pixels = Uint8List.fromList(rendered.pixels);
    return compute(
      _encodePdfImagePng,
      _PdfImageEncodeRequest(
        pixels: TransferableTypedData.fromList([pixels]),
        width: rendered.width,
        height: rendered.height,
      ),
    );
  } finally {
    rendered.dispose();
  }
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

String pdfImageCacheKey(
  String sourceId,
  int? page,
  String variant,
  PdfRenderPixelSize size,
) {
  return 'pdf_${variant}_${sourceId}_${page ?? 1}_${size.cachePart}.png';
}

Uint8List _encodePdfImagePng(_PdfImageEncodeRequest request) {
  final pixels = request.pixels.materialize().asUint8List();
  final png = image.encodePng(
    image.Image.fromBytes(
      width: request.width,
      height: request.height,
      bytes: pixels.buffer,
      numChannels: 4,
      order: image.ChannelOrder.bgra,
    ),
  );
  return Uint8List.fromList(png);
}

class _PdfImageEncodeRequest {
  final TransferableTypedData pixels;
  final int width;
  final int height;

  const _PdfImageEncodeRequest({
    required this.pixels,
    required this.width,
    required this.height,
  });
}

String pdfBytesSignature(Uint8List bytes) {
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

String stablePdfHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16);
}
