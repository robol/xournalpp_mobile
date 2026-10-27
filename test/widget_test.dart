import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/EditingToolbar.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:xournalpp/widgets/XppPagesBrowser.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';

void main() {
  testWidgets('empty share lists do not poison the next intent', (
    tester,
  ) async {
    lastIntentData = null;
    await tester.pumpWidget(XournalppMobile());
    await tester.pump();

    final dynamic state = tester.state(find.byType(OpenPage));
    await state.receivedShareNotification(<Object>[]);

    expect(lastIntentData, isNull);
  });

  testWidgets('toolbar paste places a copy in the visible page region', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final page = XppPage.empty()
      ..pageSize = XppPageSize(width: 200, height: 600);
    page.layers!.last.content!.add(
      XppText(text: 'Copy me', offset: const Offset(20, 20), size: 12),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: CanvasPage(
          file: XppFile(title: 'Document', pages: [page]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is FloatingActionButton &&
            widget.heroTag == EditingTool.SELECT,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Copy me'));
    await tester.pump();
    await tester.tap(find.byTooltip('Duplicate selection'));
    await tester.pump();
    expect(page.layers!.last.content, hasLength(2));

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(400, 350),
        scrollDelta: Offset(0, 700),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Paste copied selection'));
    await tester.pump();

    expect(page.layers!.last.content, hasLength(3));
    final pasted = page.layers!.last.content!.last! as XppText;
    final pageRect = tester.getRect(find.byType(XppPageStack));
    final viewportRect = tester.getRect(find.byType(SingleChildScrollView));
    final visibleRect = pageRect.intersect(viewportRect);
    final visibleTop =
        (visibleRect.top - pageRect.top) *
        page.pageSize!.height! /
        pageRect.height;
    final visibleBottom =
        (visibleRect.bottom - pageRect.top) *
        page.pageSize!.height! /
        pageRect.height;
    expect(
      pasted.selectionBounds!.center.dy,
      inInclusiveRange(visibleTop, visibleBottom),
    );
  });

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
    final pasteButton = find.descendant(
      of: toolbar,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is FloatingActionButton &&
            widget.heroTag == 'PasteSelection',
      ),
    );
    expect(pasteButton, findsOneWidget);
    expect(tester.widget<FloatingActionButton>(pasteButton).onPressed, isNull);
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
    final compactPasteButton = find.descendant(
      of: toolbar,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is IconButton && widget.tooltip == 'Paste copied selection',
      ),
    );
    expect(compactPasteButton, findsOneWidget);
    final compactPasteWidget = tester.widget<IconButton>(compactPasteButton);
    expect(compactPasteWidget.onPressed, isNull);
    expect(
      tester.getCenter(compactPasteButton).dx,
      greaterThan(tester.getCenter(find.byIcon(Icons.tab_unselected)).dx),
    );
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

  Widget canvasNavigationTestApp({required CanvasPage page}) {
    return MaterialApp(
      localizationsDelegates: [
        S.delegate,
        DefaultMaterialLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => page)),
              child: const Text('Open canvas'),
            ),
          ),
        ),
      ),
    );
  }

  test('PDF export adds annotated suffix to the suggested file name', () {
    expect(annotatedPdfFileName('Document'), 'Document_annotated.pdf');
    expect(annotatedPdfFileName('Document.xopp'), 'Document_annotated.pdf');
    expect(annotatedPdfFileName('Document.pdf'), 'Document_annotated.pdf');
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

  testWidgets('leaving a new unsaved document asks to save', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      canvasNavigationTestApp(
        page: CanvasPage(file: XppFile.empty(title: 'New document')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open canvas'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Save changes?'), findsOneWidget);
    expect(find.text('New document'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('New document'), findsOneWidget);
  });

  testWidgets('discarding changes leaves the canvas', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      canvasNavigationTestApp(
        page: CanvasPage(file: XppFile.empty(title: 'New document')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open canvas'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Open canvas'), findsOneWidget);
    expect(find.text('New document'), findsNothing);
  });
}
