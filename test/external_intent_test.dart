import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/pages/OpenPage.dart';

void main() {
  testWidgets(
    'opens an incoming notebook without overwriting a read-only URI',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final directory = Directory.systemTemp.createTempSync('intent_test_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final notebook = File('${directory.path}/notes.xopp');
      notebook.writeAsBytesSync(
        GZipEncoder().encode(
          utf8.encode('''
<xournal><title>Incoming notebook</title><page width="200" height="300">
<background type="solid" style="plain" color="#ffffff"/><layer/>
</page></xournal>'''),
        ),
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
          home: OpenPage(
            initialExternalIntent: {
              'uri': notebook.uri.toString(),
              'displayName': 'notes.xopp',
              'mimeType': 'application/x-xopp',
              'writable': false,
            },
          ),
        ),
      );
      await tester.runAsync(() async {
        for (
          var i = 0;
          i < 100 && find.byType(CanvasPage).evaluate().isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      final canvas = tester.widget<CanvasPage>(find.byType(CanvasPage));
      expect(canvas.file!.title, 'notes');
      expect(canvas.filePath, isNull);
    },
  );
}
