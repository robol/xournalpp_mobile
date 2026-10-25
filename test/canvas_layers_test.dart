import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';

void main() {
  testWidgets('new marks go to the last layer', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final size = XppPageSize(width: 200, height: 200);
    final bottom = XppLayer.empty();
    final top = XppLayer.empty();
    final page = XppPage(
      pageSize: size,
      background: XppBackgroundSolidPlain(size: size),
      layers: [bottom, top],
    );
    await tester.pumpWidget(_app(page));
    await tester.pump();

    final pageRect = tester.getRect(find.byType(XppPageStack));
    final start = pageRect.topLeft + const Offset(200, 200);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveTo(start + const Offset(40, 40));
    await gesture.up();
    await tester.pump();

    expect(bottom.content, isEmpty);
    expect(top.content, hasLength(1));
  });

  testWidgets('eraser reaches marks on both layers', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    XppStrokePen stroke() => XppStrokePen(
      color: Colors.black,
      points: [
        XppStrokePoint(x: 60, y: 60, width: 2),
        XppStrokePoint(x: 61, y: 61, width: 2),
      ],
    );
    final bottom = XppLayer(content: [stroke()]);
    final top = XppLayer(content: [stroke()]);
    final size = XppPageSize(width: 200, height: 200);
    final page = XppPage(
      pageSize: size,
      background: XppBackgroundSolidPlain(size: size),
      layers: [bottom, top],
    );
    await tester.pumpWidget(_app(page));
    await tester.pump();
    final pageRect = tester.getRect(find.byType(XppPageStack));
    final point =
        pageRect.topLeft +
        Offset(
          60 * pageRect.width / size.width!,
          60 * pageRect.height / size.height!,
        );
    final gesture = await tester.startGesture(
      point,
      kind: PointerDeviceKind.invertedStylus,
    );
    await gesture.moveTo(point + const Offset(2, 2));
    await gesture.up();
    await tester.pump();

    expect(bottom.content, isEmpty);
    expect(top.content, isEmpty);
  });
}

Widget _app(XppPage page) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.delegate.supportedLocales,
  home: CanvasPage(
    file: XppFile(title: 'Layers', pages: [page]),
  ),
);
