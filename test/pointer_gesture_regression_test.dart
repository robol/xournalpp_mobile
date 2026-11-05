import 'package:xournalpp/src/XppPageContentWidget.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

void main() {
  final saved = <XppContent>[];
  final erased = <List<Offset>>[];
  Future<void> mount(
    WidgetTester tester, {
    EditingTool tool = EditingTool.STYLUS,
    Widget? content,
    VoidCallback? clearSelection,
  }) async {
    saved.clear();
    erased.clear();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: PointerListener(
          toolData: {
            PointerDeviceKind.stylus: tool,
            PointerDeviceKind.touch: tool,
          },
          color: Colors.black,
          strokeWidth: 4,
          eraserWidth: 10,
          onSelectionClear: clearSelection,
          onNewContent: (c) {
            if (c != null) saved.add(c);
          },
          filterEraser: ({coordinates, radius}) {},
          filterEraserPath: ({coordinates, radius}) =>
              erased.add(List.of(coordinates ?? [])),
          child: content ?? const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> down(
    WidgetTester t,
    int id,
    double x, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    int buttons = kPrimaryButton,
  }) => t.sendEventToBinding(
    PointerDownEvent(
      pointer: id,
      kind: kind,
      position: Offset(x, 100),
      pressure: .5,
      pressureMin: 0,
      pressureMax: 1,
      buttons: buttons,
    ),
  );
  Future<void> move(
    WidgetTester t,
    int id,
    double x, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    int buttons = kPrimaryButton,
  }) => t.sendEventToBinding(
    PointerMoveEvent(
      pointer: id,
      kind: kind,
      position: Offset(x, 100),
      pressure: .5,
      pressureMin: 0,
      pressureMax: 1,
      buttons: buttons,
    ),
  );
  Future<void> up(
    WidgetTester t,
    int id,
    double x, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) => t.sendEventToBinding(
    PointerUpEvent(
      pointer: id,
      kind: kind,
      position: Offset(x, 100),
      pressure: 0,
    ),
  );

  testWidgets('existing text tap opens exactly one editor', (t) async {
    final text = XppText(text: 'Existing text', offset: Offset.zero, size: 20);
    await mount(
      t,
      tool: EditingTool.TEXT,
      content: Align(
        alignment: Alignment.topLeft,
        child: text.render(onReplace: (_) {}),
      ),
    );
    final gesture = await t.startGesture(
      t.getCenter(find.text('Existing text')),
      kind: PointerDeviceKind.stylus,
      buttons: kPrimaryButton,
    );
    await gesture.up();
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(saved, isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  for (final milliseconds in [50, 300]) {
    testWidgets(
      'content selection is independent of tap duration: $milliseconds ms',
      (t) async {
        var selected = 0;
        var cleared = 0;
        await mount(
          t,
          tool: EditingTool.SELECT,
          clearSelection: () => cleared++,
          content: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 200,
              child: XppPageContentWidget(
                selectionMode: true,
                onSelect: () => selected++,
                child: const ColoredBox(color: Colors.white),
              ),
            ),
          ),
        );
        await down(t, 1, 50);
        await t.pump(Duration(milliseconds: milliseconds));
        await up(t, 1, 50);
        await t.pumpAndSettle();
        expect(selected, 1);
        expect(cleared, 0);
        await down(t, 2, 300);
        await up(t, 2, 300);
        await t.pumpAndSettle();
        expect(cleared, 1);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'release supplies exact endpoint and keeps previous pressure width',
    (t) async {
      await mount(t);
      await down(t, 1, 20);
      await up(t, 1, 50);
      final stroke = saved.single as XppStroke;
      expect(stroke.points!.first.offset, const Offset(20, 100));
      expect(stroke.points!.last.offset, const Offset(50, 100));
      expect(stroke.points!.last.width, 2);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'button changes take effect on next contact only; eraser retains release endpoint',
    (t) async {
      await mount(t);
      await down(t, 1, 20);
      await move(t, 1, 40, buttons: kSecondaryStylusButton);
      await up(t, 1, 50);
      expect(saved, hasLength(1));
      expect(erased, isEmpty);
      await down(t, 2, 60, buttons: kSecondaryStylusButton);
      await up(t, 2, 90);
      expect(saved, hasLength(1));
      expect(erased.single, [const Offset(60, 100), const Offset(90, 100)]);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('cancel then up never commits and releases owner', (t) async {
    await mount(t);
    await down(t, 1, 20);
    await move(t, 1, 40);
    await t.sendEventToBinding(
      const PointerCancelEvent(pointer: 1, kind: PointerDeviceKind.stylus),
    );
    await up(t, 1, 60);
    expect(saved, isEmpty);
    await down(t, 2, 80);
    await up(t, 2, 80);
    expect(saved, hasLength(1));
    expect((saved.single as XppStroke).points, hasLength(1));
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('brief second contact preserves first touch ink', (t) async {
    await mount(t);
    await down(t, 1, 20, kind: PointerDeviceKind.touch);
    await move(t, 1, 40, kind: PointerDeviceKind.touch);
    await down(t, 2, 150, kind: PointerDeviceKind.touch);
    await up(t, 2, 150, kind: PointerDeviceKind.touch);
    await up(t, 1, 60, kind: PointerDeviceKind.touch);
    expect(saved, hasLength(1));
    expect(
      (saved.single as XppStroke).points!.last.offset,
      const Offset(60, 100),
    );
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'text cancellation and a pinch candidate do not open editing dialogs',
    (t) async {
      await mount(t, tool: EditingTool.TEXT);
      await down(t, 1, 20);
      await t.pump();
      expect(find.byType(TextField), findsNothing);
      await t.sendEventToBinding(
        const PointerCancelEvent(pointer: 1, kind: PointerDeviceKind.stylus),
      );
      await up(t, 1, 20);
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await t.pump(const Duration(milliseconds: 501));
      await down(t, 2, 20, kind: PointerDeviceKind.touch);
      await down(t, 3, 150, kind: PointerDeviceKind.touch);
      await move(t, 3, 190, kind: PointerDeviceKind.touch);
      await up(t, 3, 190, kind: PointerDeviceKind.touch);
      await up(t, 2, 20, kind: PointerDeviceKind.touch);
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(saved, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
}
