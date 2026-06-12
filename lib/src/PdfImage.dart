import 'dart:typed_data';

import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:printing/printing.dart';
import 'package:xournalpp/src/XppPage.dart';

const double DPI = 96;

Future<int> pdfPageCount(XppPickedFile pdf) =>
    Printing.raster(pdf.toUint8List()).length;

Future<Uint8List> pdfImage(XppPickedFile pdf, int? page) async {
  final pageIndex = page ?? 0;
  final raster = await Printing.raster(
    pdf.toUint8List(),
    pages: [pageIndex],
    dpi: DPI,
  ).single;
  return raster.toPng();
}

Future<XppPageSize> pdfPageSize(XppPickedFile pdf, int page) async {
  final raster = await Printing.raster(
    pdf.toUint8List(),
    pages: [page],
    dpi: DPI,
  ).single;
  return XppPageSize(
    width: raster.width.toDouble(),
    height: raster.height.toDouble(),
  );
}
