import 'dart:typed_data';

import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:printing/printing.dart';
import 'package:xournalpp/src/XppPage.dart';

const double DPI = 192;

Future<int> pdfPageCount(XppPickedFile pdf) async =>
    pdfPageSizes(pdf).then((sizes) => sizes.length);

Future<Uint8List> pdfImage(XppPickedFile pdf, int? page) async {
  final pageNumber = page ?? 1;
  final pageIndex = pageNumber <= 0 ? 0 : pageNumber - 1;
  final raster = await Printing.raster(
    pdf.toUint8List(),
    pages: [pageIndex],
    dpi: DPI,
  ).single;
  return raster.toPng();
}

Future<XppPageSize> pdfPageSize(XppPickedFile pdf, int page) async {
  final sizes = _parsePdfPageSizes(pdf.toUint8List());
  if (page >= 0 && page < sizes.length) return sizes[page];

  final raster = await Printing.raster(
    pdf.toUint8List(),
    pages: [page],
    dpi: DPI,
  ).single;
  return XppPageSize(
    width: raster.width / DPI * 72,
    height: raster.height / DPI * 72,
  );
}

Future<List<XppPageSize>> pdfPageSizes(XppPickedFile pdf) async {
  final bytes = pdf.toUint8List();
  final sizes = _parsePdfPageSizes(bytes);
  if (sizes.isNotEmpty) return sizes;

  final raster = await Printing.raster(bytes, pages: [0], dpi: DPI).single;
  return [
    XppPageSize(
      width: raster.width / DPI * 72,
      height: raster.height / DPI * 72,
    ),
  ];
}

List<XppPageSize> _parsePdfPageSizes(Uint8List bytes) {
  final source = String.fromCharCodes(bytes);
  final defaultMediaBox = _parseMediaBox(source);
  final pages = <XppPageSize>[];
  final objectPattern = RegExp(r'\d+\s+\d+\s+obj\b(.*?)endobj', dotAll: true);

  for (final object in objectPattern.allMatches(source)) {
    final body = object.group(1)!;
    if (!RegExp(r'/Type\s*/Page\b').hasMatch(body)) continue;

    final mediaBox = _parseMediaBox(body) ?? defaultMediaBox;
    if (mediaBox == null) continue;

    final rotation = _parsePageRotation(body);
    final rotated = rotation == 90 || rotation == 270;
    pages.add(
      XppPageSize(
        width: rotated ? mediaBox.height : mediaBox.width,
        height: rotated ? mediaBox.width : mediaBox.height,
      ),
    );
  }

  return pages;
}

_PdfMediaBox? _parseMediaBox(String source) {
  final number = r'-?(?:\d+\.?\d*|\.\d+)';
  final match = RegExp(
    '/MediaBox\\s*\\[\\s*($number)\\s+($number)\\s+($number)\\s+($number)\\s*\\]',
  ).firstMatch(source);
  if (match == null) return null;

  final left = double.parse(match.group(1)!);
  final bottom = double.parse(match.group(2)!);
  final right = double.parse(match.group(3)!);
  final top = double.parse(match.group(4)!);
  return _PdfMediaBox(
    width: (right - left).abs(),
    height: (top - bottom).abs(),
  );
}

int _parsePageRotation(String source) {
  final match = RegExp(r'/Rotate\s+(-?\d+)').firstMatch(source);
  if (match == null) return 0;
  return int.parse(match.group(1)!).abs() % 360;
}

class _PdfMediaBox {
  final double width;
  final double height;

  const _PdfMediaBox({required this.width, required this.height});
}
