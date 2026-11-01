import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/PdfExporter.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';

/// Opt-in measurements, not flaky machine-specific timing assertions.
/// flutter test --dart-define=RUN_SCALABILITY_BENCHMARKS=true \
///   test/scalability_benchmark_test.dart -r expanded
const _runBenchmarks = bool.fromEnvironment('RUN_SCALABILITY_BENCHMARKS');

XppFile _notebook(int pageCount, int strokeCount) {
  var remainingStrokes = strokeCount;
  final pages = <XppPage>[];
  for (var index = 0; index < pageCount; index++) {
    final count = (remainingStrokes / (pageCount - index)).ceil();
    remainingStrokes -= count;
    final page = XppPage.empty();
    page.layers = [
      XppLayer(
        content: List.generate(
          count,
          (stroke) => XppStrokePen(
            color: Colors.black,
            points: List.generate(
              8,
              (point) => XppStrokePoint(
                x: (stroke % 50) * 5.0 + point,
                y: (stroke ~/ 50) * 5.0 + point,
                width: 1,
              ),
            ),
          ),
        ),
      ),
    ];
    pages.add(page);
  }
  return XppFile.empty(title: 'benchmark')..pages = pages;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final pageCount in [10, 100, 500]) {
    for (final strokeCount in [1000, 10000]) {
      test(
        'benchmark ${pageCount}p ${strokeCount}s serialization and PDF',
        () async {
          final file = _notebook(pageCount, strokeCount);
          final afterBuildRss = ProcessInfo.currentRss;
          final timer = Stopwatch()..start();
          final xopp = await file.toUint8ListAsync();
          final serializeMs = timer.elapsedMilliseconds;
          timer.reset();
          final pdf = await exportPdfDocument(file);
          final pdfMs = timer.elapsedMilliseconds;
          timer.stop();
          expect(xopp, isNotEmpty);
          expect(pdf, isNotEmpty);
          print(
            'BENCHMARK_JSON ${jsonEncode({'pages': pageCount, 'strokes': strokeCount, 'xoppBytes': xopp.length, 'pdfBytes': pdf.length, 'serializeMs': serializeMs, 'pdfExportMs': pdfMs, 'rssAfterBuildBytes': afterBuildRss, 'rssAfterExportBytes': ProcessInfo.currentRss})}',
          );
        },
        skip: !_runBenchmarks,
      );
    }
  }
}
