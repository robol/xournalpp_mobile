import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/widgets/EditingToolbar.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:xournalpp/widgets/XppPagesBrowser.dart';

void main() {
  testWidgets('toolbar embeds at 1000px and preserves state across resizing', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(999, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final title = List.filled(20, 'Long document title').join(' ');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: CanvasPage(file: XppFile.empty(title: title)),
      ),
    );
    await tester.pumpAndSettle();

    final toolbar = find.byType(EditingToolBar);
    final state = tester.state<EditingToolBarState>(toolbar);
    expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNotNull);
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight + 64);
    final pageBrowser = find.byType(XppPagesBrowser);
    expect(
      tester.widget<XppPagesBrowser>(pageBrowser).direction,
      Axis.horizontal,
    );
    expect(find.byType(BottomAppBar), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is FloatingActionButton &&
            widget.heroTag == EditingTool.SELECT,
      ),
    );
    await tester.pump();
    expect(state.getTool(), EditingTool.SELECT);

    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
    expect(tester.widget<EditingToolBar>(toolbar).compact, isTrue);
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
    expect(
      tester.widget<XppPagesBrowser>(pageBrowser).direction,
      Axis.vertical,
    );
    expect(find.byType(BottomAppBar), findsNothing);
    expect(tester.getRect(pageBrowser).left, greaterThan(900));
    final previousPage = find.descendant(
      of: pageBrowser,
      matching: find.byIcon(Icons.keyboard_arrow_up),
    );
    final nextPage = find.descendant(
      of: pageBrowser,
      matching: find.byIcon(Icons.keyboard_arrow_down),
    );
    expect(
      tester.getCenter(previousPage).dy,
      lessThan(tester.getCenter(find.text('1 / 1')).dy),
    );
    expect(
      tester.getCenter(nextPage).dy,
      greaterThan(tester.getCenter(find.text('1 / 1')).dy),
    );
    await tester.tap(
      find.descendant(of: pageBrowser, matching: find.byIcon(Icons.add)),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(previousPage);
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(nextPage);
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(tester.state(toolbar), same(state));
    expect(state.getTool(), EditingTool.SELECT);
    expect(tester.takeException(), isNull);
    final titleWidget = tester.widget<Text>(find.text(title));
    expect(titleWidget.overflow, TextOverflow.ellipsis);
    final selectButton = find.descendant(
      of: toolbar,
      matching: find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.isSelected == true,
      ),
    );
    expect(selectButton, findsOneWidget);
    expect(
      tester.getRect(toolbar).contains(tester.getCenter(selectButton)),
      isTrue,
    );
    await tester.tap(
      find.descendant(of: toolbar, matching: find.byIcon(Icons.pan_tool)),
    );
    await tester.pump();
    expect(state.getTool(), EditingTool.MOVE);

    tester.view.physicalSize = const Size(999, 800);
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNotNull);
    expect(
      tester.widget<XppPagesBrowser>(pageBrowser).direction,
      Axis.horizontal,
    );
    expect(find.byType(BottomAppBar), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(tester.state(toolbar), same(state));
    expect(state.getTool(), EditingTool.MOVE);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app opens to the document launcher', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(XournalppMobile());
    await tester.pump();

    expect(find.text('Xournal++'), findsOneWidget);
  });

  testWidgets('canvas menu includes PDF export and share actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: [
          S.delegate,
          DefaultMaterialLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: CanvasPage(file: XppFile.empty(title: 'Test document')),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Export PDF...'), findsOneWidget);
    expect(find.text('Share PDF...'), findsOneWidget);
  });

  testWidgets('canvas menu hides PDF sharing on Linux', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: [
            S.delegate,
            DefaultMaterialLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: CanvasPage(file: XppFile.empty(title: 'Test document')),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Export PDF...'), findsOneWidget);
      expect(find.text('Share PDF...'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
