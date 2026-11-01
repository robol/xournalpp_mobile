import 'package:xournalpp/widgets/XppPageStack.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/TransparentImage.dart';
import 'package:xournalpp/src/XppPickedFile.dart';
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
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:xournalpp/src/conditional/draft_storage/draft_storage_io.dart'
    as draft_storage;
import 'package:xournalpp/widgets/XppPagesBrowser.dart';

class _BlockingRecentStore extends InMemorySharedPreferencesStore {
  _BlockingRecentStore() : super.empty();

  bool blockWrites = false;

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (blockWrites && key == 'flutter.recentFiles') {
      if (!started.isCompleted) started.complete();
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

class _BlockingNotebookStorage implements NotebookStorage {
  final started = Completer<void>();
  final release = Completer<void>();
  int writes = 0;
  Uint8List? savedBytes;

  @override
  String get id => 'blocked-test';
  @override
  String? get iconAsset => null;
  @override
  Future<StoredNotebook?> save({
    required Uint8List bytes,
    required String name,
    StoredNotebook? existing,
    required List<NotebookPdfResource> pdfs,
  }) async {
    writes++;
    savedBytes = bytes;
    if (!started.isCompleted) started.complete();
    await release.future;
    return existing;
  }

  @override
  Future<List<StoredNotebook>> list() async => [];
  @override
  Future<Uint8List> readNotebook(StoredNotebook notebook) async => Uint8List(0);
  @override
  Future<Uint8List> readPdf(StoredNotebook notebook, String reference) async =>
      Uint8List(0);
  @override
  Future<void> forget(StoredNotebook notebook) async {}
}

void main() {
  for (final previousPreview in [false, true]) {
    testWidgets(
      'Save tolerates blocked dense raster, previous preview=$previousPreview',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'notebookCache.enabled.v1': false,
        });
        final releaseRaster = Completer<void>();
        var rasterStarted = false;
        XppPageStack.debugPenCommandsPerPass = 1;
        XppPageStack.debugRasterizePicture = (picture, width, height) async {
          rasterStarted = true;
          await releaseRaster.future;
          return picture.toImage(width, height);
        };
        addTearDown(() {
          XppPageStack.debugRasterizePicture = null;
          XppPageStack.debugPenCommandsPerPass = null;
          if (!releaseRaster.isCompleted) releaseRaster.complete();
        });
        final storage = _BlockingNotebookStorage()..release.complete();
        final notebook = StoredNotebook(
          backendId: storage.id,
          id: 'existing',
          name: 'Dense',
        );
        final oldPreview = Uint8List.fromList(kTransparentImage);
        final file = XppFile.empty(title: 'Dense')
          ..storage = storage
          ..storageNotebook = notebook;
        file.previewImage = previousPreview ? oldPreview : null;
        file.pages!.first.layers!.last.content!.add(
          XppStrokePen(
            color: Colors.black,
            points: List.generate(
              40,
              (i) => XppStrokePoint(
                x: i.toDouble() + (previousPreview ? 0.5 : 0),
                y: i.toDouble(),
                width: 1,
              ),
            ),
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
            home: CanvasPage(file: file, filePath: notebook.id),
          ),
        );
        for (var i = 0; i < 100 && !rasterStarted; i++) {
          await tester.pump(const Duration(milliseconds: 150));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(rasterStarted, true);
        final dynamic canvas = tester.state(find.byType(CanvasPage));
        bool? result;
        canvas.saveFile().then((bool value) => result = value);
        for (var i = 0; i < 100 && result == null; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(result, true);
        expect(releaseRaster.isCompleted, false);
        expect(storage.writes, 1);
        expect(
          file.previewImage,
          previousPreview ? same(oldPreview) : orderedEquals(kTransparentImage),
        );
        final reopened = await tester.runAsync(
          () => XppFile.fromXppPickedFile(
            XppPickedFile(storage.savedBytes!, fileName: 'Dense.xopp'),
            null,
            (_, _) => throw StateError('No PDF'),
          ),
        );
        expect(
          (reopened!.pages!.first.layers!.last.content!.single as XppStrokePen)
              .points,
          hasLength(40),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text(
            'The notebook was saved, but its thumbnail could not be updated.',
          ),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        releaseRaster.complete();
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      },
    );
  }

  testWidgets('new notebook suggests a date and time Notes title', (
    tester,
  ) async {
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
        '${date.day.toString().padLeft(2, '0')}_'
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}_Notes';
    final title = tester
        .widget<TextField>(find.byType(TextField))
        .controller!
        .text;
    expect(title, anyOf(nameFor(before), nameFor(after)));
    expect(find.text('Storage location'), findsOneWidget);
    expect(find.text('Internal'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<NotebookStorage>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Local storage'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/storage/local.png',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Local storage').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picker.name, isNull);
  });

  testWidgets('R1: a slow overwrite remains exclusive after the warning', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'notebookCache.enabled.v1': false});
    final storage = _BlockingNotebookStorage();
    addTearDown(() {
      if (!storage.release.isCompleted) storage.release.complete();
    });
    final notebook = StoredNotebook(
      backendId: storage.id,
      id: 'existing',
      name: 'notes',
    );
    final file = XppFile.empty(title: 'notes')
      ..storage = storage
      ..storageNotebook = notebook;
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
          file: file,
          filePath: notebook.id,
          slowSaveWarningDelay: const Duration(milliseconds: 20),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dynamic canvas = tester.state(find.byType(CanvasPage));
    late Future<bool> first;
    await tester.runAsync(() async {
      first = canvas.saveFile() as Future<bool>;
    });
    for (var i = 0; i < 100 && !storage.started.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(storage.started.isCompleted, isTrue);
    // Serialization can finish in the real-async zone while widget animations
    // use fake time. Advance both without a thirty-second wall-clock delay.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.text(
        'Still saving. Keep this notebook open until the operation finishes.',
      ),
      findsOneWidget,
    );
    expect(storage.writes, 1);
    expect(
      await tester.runAsync(() => canvas.saveFile() as Future<bool>),
      isFalse,
    );
    expect(storage.writes, 1);
    bool? result;
    await tester.runAsync(() async {
      first.then((value) => result = value);
      storage.release.complete();
    });
    for (var i = 0; i < 100 && result == null; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(result, isTrue);
    await tester.pump();
    expect(canvas.savingFile, isFalse);
    expect(storage.writes, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('edits made during save remain unsaved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = (await tester.runAsync(() async => _BlockingRecentStore()))!;
    SharedPreferencesStorePlatform.instance = store;
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('xpp-save-test-'),
    ))!;
    draft_storage.debugDraftDirectory = directory.path;
    addTearDown(() => draft_storage.debugDraftDirectory = null);
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
    for (var i = 0; i < 300 && !store.started.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
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
