import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppFile.dart';

void main() {
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
