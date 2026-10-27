import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/RecentFiles.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/Workspace.dart';

void main() {
  test(
    'opening promotes a recent entry without changing modification metadata',
    () async {
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.kRecentFiles: jsonEncode([
          {
            'path': 'content://notes/1',
            'name': 'Old',
            'modified': '2025-01-01',
            'preview': 'existing',
          },
          {'path': '/other.xopp', 'name': 'Other'},
        ]),
      });
      await RecentFiles.remember(
        path: 'content://notes/1',
        name: 'Notebook',
        currentPage: 2,
      );
      final prefs = await SharedPreferences.getInstance();
      final files =
          jsonDecode(prefs.getString(PreferencesKeys.kRecentFiles)!) as List;
      expect(files, hasLength(2));
      expect(files.last, containsPair('path', 'content://notes/1'));
      expect(files.last, containsPair('modified', '2025-01-01'));
      expect(files.last, containsPair('preview', 'existing'));
      expect(files.last, containsPair('currentPage', 2));
    },
  );

  test(
    'overlapping open and save keep saved metadata and other documents',
    () async {
      SharedPreferences.setMockInitialValues({});
      final modified = DateTime.utc(2026, 1, 1);
      await Future.wait([
        RecentFiles.remember(path: '/one.xopp', name: 'One', currentPage: 0),
        RecentFiles.remember(
          path: '/one.xopp',
          name: 'One',
          currentPage: 1,
          modified: modified,
          preview: Uint8List.fromList([1, 2]),
        ),
        RecentFiles.remember(path: '/two.xopp', name: 'Two', currentPage: 0),
      ]);
      final prefs = await SharedPreferences.getInstance();
      final files =
          jsonDecode(prefs.getString(PreferencesKeys.kRecentFiles)!) as List;
      expect(files, hasLength(2));
      expect(files.first['modified'], modified.toIso8601String());
      expect(files.first['preview'], base64Encode([1, 2]));
      expect(files.last.containsKey('modified'), isFalse);
    },
  );

  for (final path in <String?>['content://notes/42', null]) {
    testWidgets('opening $path updates the mounted home without saving', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(XournalppMobile());
      await tester.pumpAndSettle();
      final navigator = Navigator.of(tester.element(find.byType(OpenPage)));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => CanvasPage(
            file: XppFile.empty(title: 'Opened notebook'),
            filePath: path,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      final files =
          jsonDecode(prefs.getString(PreferencesKeys.kRecentFiles) ?? '[]')
              as List;
      expect(files, hasLength(path == null ? 0 : 1));
      if (path != null) {
        expect(files.single['path'], path);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Save changes?'), findsNothing);
        expect(find.byType(DocumentCard), findsOneWidget);
        expect(find.text('Opened notebook'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
