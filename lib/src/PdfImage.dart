import 'dart:typed_data';

import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:printing/printing.dart';
import 'package:xournalpp/src/XppPage.dart';

const double DPI = 96;

Future<int> pdfPageCount(XppPickedFile pdf) =>
    Printing.raster(pdf.toUint8List()).length;

Future<Uint8List> pdfImage(XppPickedFile pdf, int? page) async =>
    Printing.raster(
      pdf.toUint8List(),
      dpi: 96,
    ).toList().then((value) => value[page!].toPng());

Future<XppPageSize> pdfPageSize(XppPickedFile pdf, int page) async {
  final raster = await Printing.raster(
    pdf.toUint8List(),
    dpi: DPI,
  ).toList().then((value) => value[page]);
  return XppPageSize(
    width: raster.width.toDouble(),
    height: raster.height.toDouble(),
  );
}
