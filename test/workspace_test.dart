import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/Workspace.dart';

void main() {
  for (final width in [280.0, 390.0, 800.0, 1200.0]) {
    testWidgets('workspace gallery fits $width with large text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.kRecentFiles: jsonEncode(
          List.generate(
            50,
            (index) => {
              'name':
                  'Notebook $index with a very long descriptive filename.xopp',
              'path': '/notes/notebook%20$index.xopp',
              'modified': '2026-10-25T12:00:00Z',
              'preview': index.isEven ? 'invalid preview' : '',
            },
          ),
        ),
      });
      await tester.pumpWidget(XournalppMobile());
      await tester.pumpAndSettle();
      expect(find.text('Your Workspace'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentCard), findsWidgets);
      expect(find.byType(DocumentCard).evaluate().length, lessThan(50));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(DocumentCard).first);
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(DocumentCard).first);
      await tester.pumpAndSettle();
      expect(find.text('Confirm delete'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty workspace creates a real notebook', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(XournalppMobile());
    await tester.pumpAndSettle();
    expect(find.text('Your workspace is ready'), findsOneWidget);
    expect(find.byType(DocumentCard), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Notebook'));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasPage), findsOneWidget);
    expect(
      tester.widget<CanvasPage>(find.byType(CanvasPage)).file!.pages,
      isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}
