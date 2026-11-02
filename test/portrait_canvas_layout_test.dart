import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';

Widget app(XppFile file, {double textScale = 1}) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.delegate.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: CanvasPage(file: file),
);

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'notebookCache.enabled.v1': false,
    }),
  );
  for (final width in [280.0, 360.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'portrait title stays visible at width $width and text scale $scale',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final title = List.filled(10, 'Long notebook title').join(' ');
          await tester.pumpWidget(
            app(XppFile.empty(title: title), textScale: scale),
          );
          await tester.pumpAndSettle();
          final titleWidget = tester.widget<Text>(find.text(title));
          expect(titleWidget.maxLines, 1);
          expect(titleWidget.overflow, TextOverflow.ellipsis);
          expect(tester.getSize(find.text(title)).width, greaterThan(70));
          expect(
            tester.getSize(find.byType(AppBar)).height,
            kToolbarHeight + 48,
          );
          expect(tester.getSize(find.byType(BottomAppBar)).height, 48);
          final undoRect = tester.getRect(
            find.byTooltip('Undo last operation'),
          );
          expect(undoRect.top, greaterThanOrEqualTo(kToolbarHeight));
          expect(undoRect.height, greaterThanOrEqualTo(48));
          expect(find.byIcon(Icons.edit_outlined), findsNothing);
          expect(find.byIcon(Icons.fit_screen), findsNothing);
          expect(find.byTooltip('Save'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(title));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            title,
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets('portrait overflow zoom actions and pinned Undo work', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final file = XppFile.empty(title: 'Notebook');
    final old = XppText(
      text: 'Original',
      offset: const Offset(10, 10),
      size: 12,
    );
    final layer = file.pages!.first.layers!.last;
    layer.content!.add(old);
    await tester.pumpWidget(app(file));
    await tester.pumpAndSettle();
    final dynamic canvas = tester.state(find.byType(CanvasPage));
    final initialScale = canvas.pageScale as double;
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Zoom out'), findsOneWidget);
    expect(find.text('Fit width'), findsOneWidget);
    await tester.tap(find.text('Zoom in'));
    await tester.pumpAndSettle();
    expect(canvas.pageScale, greaterThan(initialScale));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fit width'));
    await tester.pumpAndSettle();
    expect(canvas.pageScale, closeTo(initialScale, 0.001));
    final replacement = XppText(
      text: 'Edited',
      offset: const Offset(10, 10),
      size: 12,
    );
    tester.widget<XppPageStack>(find.byType(XppPageStack)).onReplaceContent!(
      layer,
      old,
      replacement,
    );
    await tester.pump();
    expect(layer.content!.single, same(replacement));
    await tester.tap(find.byTooltip('Undo last operation'));
    await tester.pumpAndSettle();
    expect(layer.content!.single, same(old));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
