// Run with flutter run --profile -t tool/rendering_benchmark.dart.
// This opens a deterministic, unsaved synthetic notebook, never a user file.
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/main.dart' show kAppTheme;
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  const pageCount = int.fromEnvironment('PROFILE_PAGES', defaultValue: 12);
  const strokeCount = int.fromEnvironment('PROFILE_STROKES', defaultValue: 800);
  const mixed = bool.fromEnvironment('PROFILE_MIXED', defaultValue: false);
  final random = Random(42);
  final pages = List.generate(pageCount, (pageIndex) {
    final size = XppPageSize(width: 595, height: pageIndex.isEven ? 842 : 700);
    final content = <XppContent>[];
    for (var s = 0; s < strokeCount; s++) {
      final x = random.nextDouble() * 500;
      final y = random.nextDouble() * (size.height! - 50);
      content.add(
        XppStrokePen(
          color: Colors.black,
          points: List.generate(
            40,
            (i) => XppStrokePoint(
              x: x + i * .8,
              y: y + sin(i / 3) * 4,
              width: 1 + (i % 5) * .2,
            ),
          ),
        ),
      );
      if (mixed && s % 80 == 0) {
        content.add(
          XppText(
            text: 'Page ${pageIndex + 1}, note $s',
            offset: Offset(x, y),
            size: 12,
          ),
        );
      }
    }
    return XppPage(
      pageSize: size,
      background: XppBackgroundSolidLined(size: size),
      layers: [XppLayer(content: content)],
    );
  });
  final samples = <ui.FrameTiming>[];
  WidgetsBinding.instance.addTimingsCallback((frames) {
    samples.addAll(frames);
    if (samples.length < 120) return;
    final hz = ui.PlatformDispatcher.instance.views.first.display.refreshRate;
    final budget = 1000 / (hz > 0 ? hz : 60);
    final builds =
        samples.map((f) => f.buildDuration.inMicroseconds / 1000).toList()
          ..sort();
    final rasters =
        samples.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()
          ..sort();
    double percentile(List<double> values, double p) =>
        values[((values.length - 1) * p).round()];
    final overBudget = samples
        .where(
          (f) =>
              max(
                    f.buildDuration.inMicroseconds,
                    f.rasterDuration.inMicroseconds,
                  ) /
                  1000 >
              budget,
        )
        .length;
    developer.log(
      'frames=${samples.length} budgetMs=${budget.toStringAsFixed(2)} '
      'overBudget=$overBudget buildP95=${percentile(builds, .95).toStringAsFixed(2)} '
      'buildP99=${percentile(builds, .99).toStringAsFixed(2)} '
      'rasterP95=${percentile(rasters, .95).toStringAsFixed(2)} '
      'rasterP99=${percentile(rasters, .99).toStringAsFixed(2)}',
      name: 'rendering-benchmark',
    );
    samples.clear();
  });
  runApp(
    MaterialApp(
      theme: kAppTheme,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      home: CanvasPage(
        file: XppFile(title: 'Synthetic rendering benchmark', pages: pages),
      ),
    ),
  );
}
