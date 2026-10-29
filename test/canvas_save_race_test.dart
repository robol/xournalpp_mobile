import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
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

  bool blockWrites = false;

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (blockWrites && key == 'flutter.recentFiles') {
      started.complete();
      await release.future;
    }
    return super.setValue(valueType, key, value);
  }
}

class _SavePicker extends FilePickerPlatform {
  String? name;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    name = fileName;
    return null;
  }
}

void main() {
  testWidgets('new notebook suggests a dated title', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = FilePickerPlatform.instance;
    final picker = _SavePicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = original);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: CanvasPage(file: XppFile.empty()),
      ),
    );
    await tester.pumpAndSettle();
    final before = DateTime.now();
    final dynamic canvas = tester.state(find.byType(CanvasPage));
    canvas.saveFile();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final after = DateTime.now();
    String nameFor(DateTime date) =>
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final title = tester
        .widget<TextField>(find.byType(TextField))
        .controller!
        .text;
    expect(title, anyOf(nameFor(before), nameFor(after)));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picker.name, isNull);
  });

  testWidgets('edits made during save remain unsaved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = (await tester.runAsync(() async => _BlockingRecentStore()))!;
    SharedPreferencesStorePlatform.instance = store;
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('xpp-save-test-'),
    ))!;
    addTearDown(() => tester.runAsync(() => directory.delete(recursive: true)));
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
    store.blockWrites = true;
    late Future<bool> saving;
    await tester.runAsync(() async {
      saving = canvas.saveFile();
    });
    await tester.pump();
    await tester.runAsync(
      () => store.started.future.timeout(const Duration(seconds: 10)),
    );
    expect(store.started.isCompleted, isTrue);

    await tester.tap(
      find.descendant(
        of: find.byType(XppPagesBrowser),
        matching: find.byIcon(Icons.add),
      ),
    );
    await tester.pump();
    final result = await tester.runAsync(() async {
      store.release.complete();
      return saving;
    });
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.text('2 / 2'), findsOneWidget);
  });
}
