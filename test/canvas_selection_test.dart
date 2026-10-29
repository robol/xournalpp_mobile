import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/widgets/EditingToolbar.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/ShapeTool.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';

void main() {
  testWidgets('shape is undone', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final page = XppPage.empty();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: CanvasPage(
          file: XppFile(title: 'Shapes', pages: [page]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final strokes = shapeStrokes(
      const Offset(20, 20),
      const Offset(80, 80),
      const ShapeSettings(kind: ShapeKind.square),
    );
    tester.widget<PointerListener>(find.byType(PointerListener)).onNewShape!(
      strokes,
    );
    await tester.pump();
    expect(page.layers!.last.content, hasLength(1));
    await tester.tap(find.byTooltip('Undo last operation'));
    await tester.pump();
    expect(page.layers!.last.content, isEmpty);
  });
  testWidgets(
    'large eraser publishes atomically and undo restores all layers',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final strokes = List.generate(
        2,
        (_) => XppStrokePen(
          color: Colors.black,
          points: List.generate(
            5000,
            (i) => XppStrokePoint(x: i / 25, y: 50, width: 2),
          ),
        ),
      );
      final layers = strokes.map((s) => XppLayer(content: [s])).toList();
      final page = XppPage(
        pageSize: XppPageSize(width: 200, height: 300),
        layers: layers,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: CanvasPage(
            file: XppFile(title: 'Eraser', pages: [page]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<PointerListener>(find.byType(PointerListener))
          .filterEraserPath!(
        coordinates: [const Offset(100, 50)],
        radius: 20.0,
      );
      expect(layers[0].content!.single, same(strokes[0]));
      expect(layers[1].content!.single, same(strokes[1]));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(layers[0].content, hasLength(2));
      expect(layers[1].content, hasLength(2));
      await tester.tap(find.byTooltip('Undo last operation'));
      await tester.pump();
      expect(layers[0].content!.single, same(strokes[0]));
      expect(layers[1].content!.single, same(strokes[1]));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selection drag is transient, cancellable and one undo operation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final stroke = XppStrokePen(
        color: Colors.black,
        points: [XppStrokePoint(x: 50, y: 50, width: 2)],
      );
      final layer = XppLayer(content: [stroke]);
      final page = XppPage(
        pageSize: XppPageSize(width: 200, height: 300),
        layers: [layer],
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: CanvasPage(
            file: XppFile(title: 'Selection', pages: [page]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<EditingToolBar>(find.byType(EditingToolBar))
          .onNewDeviceMap!({
        PointerDeviceKind.touch: EditingTool.SELECT,
        PointerDeviceKind.mouse: EditingTool.SELECT,
        PointerDeviceKind.stylus: EditingTool.SELECT,
      });
      await tester.pump();
      tester.widget<XppPageStack>(find.byType(XppPageStack)).onSelectContent!(
        layer,
        stroke,
      );
      await tester.pump();
      var pointer = tester.widget<PointerListener>(
        find.byType(PointerListener),
      );
      pointer.onSelectionMove!(const Offset(10, 20), done: false);
      await tester.pump();
      expect(layer.content!.single, same(stroke));
      expect(
        tester
            .widget<XppPageStack>(find.byType(XppPageStack))
            .selectionTranslation!
            .value,
        const Offset(10, 20),
      );
      pointer.onSelectionMoveCancel!();
      await tester.pump();
      expect(layer.content!.single, same(stroke));
      expect(
        tester
            .widget<XppPageStack>(find.byType(XppPageStack))
            .selectionTranslation!
            .value,
        Offset.zero,
      );
      pointer = tester.widget<PointerListener>(find.byType(PointerListener));
      pointer.onSelectionMove!(const Offset(3, 4), done: false);
      pointer.onSelectionMove!(const Offset(7, 6), done: false);
      expect(layer.content!.single, same(stroke));
      pointer.onSelectionMove!(Offset.zero, done: true);
      await tester.pump();
      expect(
        (layer.content!.single as XppStroke).points!.single.offset,
        const Offset(60, 60),
      );
      await tester.tap(find.byTooltip('Undo last operation'));
      await tester.pump();
      expect(layer.content!.single, same(stroke));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  test('PDF replacement preserves the size of annotated pages', () {
    final originalSize = XppPageSize(width: 200, height: 300);
    final pdfSize = XppPageSize(width: 400, height: 600);
    final annotated = XppPage(
      pageSize: originalSize,
      layers: [
        XppLayer(
          content: [XppText(text: 'note', offset: Offset.zero)],
        ),
      ],
    );
    final empty = XppPage(pageSize: originalSize, layers: [XppLayer.empty()]);

    resizePageForPdfIfEmpty(annotated, pdfSize);
    resizePageForPdfIfEmpty(empty, pdfSize);

    expect(annotated.pageSize, same(originalSize));
    expect(empty.pageSize, same(pdfSize));
  });

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
