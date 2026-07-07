import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppFile.dart';

void main() {
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
