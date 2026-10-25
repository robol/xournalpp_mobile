import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/widgets/XppPagesBrowser.dart';

class _BlockingRecentStore extends InMemorySharedPreferencesStore {
  _BlockingRecentStore() : super.empty();

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.recentFiles') {
      started.complete();
      await release.future;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  testWidgets('edits made during save remain unsaved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = _BlockingRecentStore();
    SharedPreferencesStorePlatform.instance = store;
    final directory = await Directory.systemTemp.createTemp('xpp-save-test-');
    addTearDown(() async => directory.delete(recursive: true));
    final path = '${directory.path}/notes.xopp';
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: CanvasPage(
          file: XppFile.empty(title: 'notes'),
          filePath: path,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dynamic canvas = tester.state(find.byType(CanvasPage));
    final Future<bool> saving = canvas.saveFile();
    for (var i = 0; i < 20 && !store.started.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(store.started.isCompleted, isTrue);

    await tester.tap(
      find.descendant(
        of: find.byType(XppPagesBrowser),
        matching: find.byIcon(Icons.add),
      ),
    );
    await tester.pump();
    store.release.complete();
    await tester.pumpAndSettle();

    expect(await saving, isFalse);
    expect(find.text('2 / 2'), findsOneWidget);
  });
}
