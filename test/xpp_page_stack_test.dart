import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';
import 'package:xml/xml.dart';

void main() {
  testWidgets(
    'rasterScale change does not rerender background with explicit target',
    (WidgetTester tester) async {
      final background = _RecordingBackground();
      final page = XppPage(
        pageSize: XppPageSize(width: 100, height: 100),
        background: background,
        layers: [XppLayer.empty()],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: XppPageStack(
            page: page,
            rasterScale: 1,
            backgroundTargetPixelWidth: 100,
            backgroundTargetPixelHeight: 100,
          ),
        ),
      );

      expect(background.targetSizes, [const Size(100, 100)]);

      await tester.pumpWidget(
        MaterialApp(
          home: XppPageStack(
            page: page,
            rasterScale: 2,
            backgroundTargetPixelWidth: 100,
            backgroundTargetPixelHeight: 100,
          ),
        ),
      );

      expect(background.targetSizes, [const Size(100, 100)]);
    },
  );

  testWidgets('background target change rerenders background', (
    WidgetTester tester,
  ) async {
    final background = _RecordingBackground();
    final page = XppPage(
      pageSize: XppPageSize(width: 100, height: 100),
      background: background,
      layers: [XppLayer.empty()],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: XppPageStack(
          page: page,
          rasterScale: 1,
          backgroundTargetPixelWidth: 100,
          backgroundTargetPixelHeight: 100,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: XppPageStack(
          page: page,
          rasterScale: 2,
          backgroundTargetPixelWidth: 200,
          backgroundTargetPixelHeight: 200,
        ),
      ),
    );

    expect(background.targetSizes, [
      const Size(100, 100),
      const Size(200, 200),
    ]);
  });

  testWidgets(
    'pdf background target changes within one dpi bucket do not rerender',
    (WidgetTester tester) async {
      final background = _RecordingPdfBackground();
      final page = XppPage(
        pageSize: XppPageSize(width: 720, height: 1080),
        background: background,
        layers: [XppLayer.empty()],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: XppPageStack(
            page: page,
            rasterScale: 1,
            backgroundTargetPixelWidth: 800,
            backgroundTargetPixelHeight: 1200,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: XppPageStack(
            page: page,
            rasterScale: 1,
            backgroundTargetPixelWidth: 900,
            backgroundTargetPixelHeight: 1350,
          ),
        ),
      );

      expect(background.targetSizes, [const Size(800, 1200)]);
    },
  );

  testWidgets('pdf background target changes across dpi buckets rerender', (
    WidgetTester tester,
  ) async {
    final background = _RecordingPdfBackground();
    final page = XppPage(
      pageSize: XppPageSize(width: 720, height: 1080),
      background: background,
      layers: [XppLayer.empty()],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: XppPageStack(
          page: page,
          rasterScale: 1,
          backgroundTargetPixelWidth: 900,
          backgroundTargetPixelHeight: 1350,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: XppPageStack(
          page: page,
          rasterScale: 1,
          backgroundTargetPixelWidth: 1600,
          backgroundTargetPixelHeight: 2400,
        ),
      ),
    );

    expect(background.targetSizes, [
      const Size(900, 1350),
      const Size(1600, 2400),
    ]);
  });
}

class _RecordingBackground extends XppBackground {
  final List<Size> targetSizes = [];

  @override
  Widget render({
    ValueChanged<bool>? onLoadingChanged,
    bool fullQuality = true,
    double? targetPixelWidth,
    double? targetPixelHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
  }) {
    targetSizes.add(Size(targetPixelWidth ?? 0, targetPixelHeight ?? 0));
    return const SizedBox.shrink();
  }

  @override
  XmlElement toXmlElement() => XmlElement(XmlName('background'));
}

class _RecordingPdfBackground extends XppBackgroundPdf {
  final List<Size> targetSizes = [];

  _RecordingPdfBackground()
    : super(
        filename: 'recording.pdf',
        page: 1,
        onUnavailable: (_, __) async => throw StateError('unused'),
      );

  @override
  Widget render({
    ValueChanged<bool>? onLoadingChanged,
    bool fullQuality = true,
    double? targetPixelWidth,
    double? targetPixelHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
  }) {
    targetSizes.add(Size(targetPixelWidth ?? 0, targetPixelHeight ?? 0));
    return const SizedBox.shrink();
  }
}
