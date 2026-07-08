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
}

class _RecordingBackground extends XppBackground {
  final List<Size> targetSizes = [];

  @override
  Widget render({
    ValueChanged<bool>? onLoadingChanged,
    bool fullQuality = true,
    double? targetPixelWidth,
    double? targetPixelHeight,
  }) {
    targetSizes.add(Size(targetPixelWidth ?? 0, targetPixelHeight ?? 0));
    return const SizedBox.shrink();
  }

  @override
  XmlElement toXmlElement() => XmlElement(XmlName('background'));
}
