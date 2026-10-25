import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';

void main() {
  test('paste offset centers copied content in the visible page region', () {
    expect(
      pasteOffsetForVisiblePage(
        const Rect.fromLTWH(10, 20, 20, 30),
        const Rect.fromLTWH(100, 300, 100, 200),
        const Rect.fromLTWH(0, 0, 300, 600),
      ),
      const Offset(130, 365),
    );
  });

  test('paste offset keeps content within the page near an edge', () {
    expect(
      pasteOffsetForVisiblePage(
        const Rect.fromLTWH(30, 40, 50, 20),
        const Rect.fromLTWH(170, 180, 30, 20),
        const Rect.fromLTWH(0, 0, 200, 200),
      ),
      const Offset(120, 140),
    );
  });

  test(
    'duplicateSelectedContents copies every selected entity in its layer',
    () {
      final firstText = XppText(text: 'First', offset: const Offset(10, 20));
      final unselectedText = XppText(
        text: 'Unselected',
        offset: const Offset(30, 40),
      );
      final stroke = XppStrokePen(
        color: Colors.black,
        points: [
          XppStrokePoint(x: 50, y: 60, width: 2),
          XppStrokePoint(x: 70, y: 80, width: 2),
        ],
      );
      final firstLayer = XppLayer(content: [firstText, unselectedText]);
      final secondLayer = XppLayer(content: [stroke]);
      final page = XppPage(layers: [firstLayer, secondLayer]);

      final duplicates = duplicateSelectedContents(page, {firstText, stroke});

      expect(duplicates, hasLength(2));
      expect(firstLayer.content, hasLength(3));
      expect(firstLayer.content, [
        firstText,
        duplicates[0].content,
        unselectedText,
      ]);
      expect(secondLayer.content, [stroke, duplicates[1].content]);
      expect(duplicates[0].layer, same(firstLayer));
      expect(duplicates[0].index, 1);
      expect(duplicates[1].layer, same(secondLayer));
      expect(duplicates[1].index, 1);

      final duplicatedText = duplicates[0].content as XppText;
      final duplicatedStroke = duplicates[1].content as XppStrokePen;
      expect(duplicatedText, isNot(same(firstText)));
      expect(duplicatedText.offset, const Offset(22, 32));
      expect(duplicatedStroke, isNot(same(stroke)));
      expect(duplicatedStroke.points![0].offset, const Offset(62, 72));
      expect(duplicatedStroke.points![0], isNot(same(stroke.points![0])));

      final pasted = pasteCopiedContents(
        page,
        duplicates
            .map(
              (duplicate) =>
                  (layer: duplicate.layer, content: duplicate.content),
            )
            .toList(),
      );

      expect(pasted, hasLength(2));
      expect(firstLayer.content, [
        firstText,
        duplicatedText,
        unselectedText,
        pasted[0].content,
      ]);
      expect(secondLayer.content, [
        stroke,
        duplicatedStroke,
        pasted[1].content,
      ]);
      expect((pasted[0].content as XppText).offset, const Offset(34, 44));
      expect(
        (pasted[1].content as XppStrokePen).points![0].offset,
        const Offset(74, 84),
      );
    },
  );
}
