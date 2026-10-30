import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/RecentFiles.dart';
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:xournalpp/src/TransparentImage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/Workspace.dart';

class _RecentBackend implements NotebookStorage {
  @override
  String? get iconAsset => null;
  _RecentBackend(this.bytes);
  final Uint8List bytes;
  int reads = 0;
  @override
  String get id => 'test-account';
  @override
  Future<Uint8List> readNotebook(StoredNotebook notebook) async {
    reads++;
    return bytes;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'recent entries are scoped by backend and retain independent positions',
    () async {
      SharedPreferences.setMockInitialValues({});
      await RecentFiles.remember(
        path: 'same.xopp',
        name: 'Local',
        currentPage: 1,
      );
      await RecentFiles.remember(
        path: 'same.xopp',
        name: 'Cloud',
        currentPage: 2,
        backendId: 'account-a',
      );
      await RecentFiles.remember(
        path: 'same.xopp',
        name: 'Other cloud',
        currentPage: 3,
        backendId: 'account-b',
      );
      await RecentFiles.updatePage('same.xopp', 4, backendId: 'account-a');
      final prefs = await SharedPreferences.getInstance();
      final entries =
          jsonDecode(prefs.getString(PreferencesKeys.kRecentFiles)!) as List;
      expect(entries, hasLength(3));
      expect(
        entries.singleWhere(
          (e) => e['backendId'] == 'account-a',
        )['currentPage'],
        4,
      );
      await RecentFiles.forget('same.xopp', backendId: 'account-a');
      final remaining =
          jsonDecode(prefs.getString(PreferencesKeys.kRecentFiles)!) as List;
      expect(remaining, hasLength(2));
      expect(remaining.any((e) => e['backendId'] == 'account-b'), isTrue);
    },
  );

  testWidgets('recent cloud notebook reopens with its backend', (tester) async {
    final original = XppFile.empty(title: 'Cloud notebook')
      ..previewImage = kTransparentImage;
    final backend = _RecentBackend(original.toUint8List()!);
    notebookStorageBackends.add(backend);
    addTearDown(() => notebookStorageBackends.remove(backend));
    SharedPreferences.setMockInitialValues({
      PreferencesKeys.kRecentFiles: jsonEncode([
        {
          'path': 'notes.xopp',
          'name': 'Cloud notebook',
          'backendId': backend.id,
          'currentPage': 0,
        },
      ]),
    });
    await tester.pumpWidget(XournalppMobile());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cloud notebook'));
    await tester.pump();
    for (var i = 0; i < 30 && find.byType(CanvasPage).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(backend.reads, 1);
    expect(find.byType(CanvasPage), findsOneWidget);
  });
  testWidgets('opening a cloud notebook adds it to recents', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final file = XppFile.empty(title: 'Cloud notebook')
      ..previewImage = kTransparentImage;
    final backend = _RecentBackend(file.toUint8List()!);
    file.storage = backend;
    file.storageNotebook = StoredNotebook(
      backendId: backend.id,
      id: 'cloud.xopp',
      name: 'Cloud notebook',
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
        home: CanvasPage(file: file, filePath: 'cloud.xopp'),
      ),
    );
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final entries =
        jsonDecode(prefs.getString(PreferencesKeys.kRecentFiles)!) as List;
    expect(entries.single['backendId'], backend.id);
    expect(entries.single['path'], 'cloud.xopp');
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('receive_sharing_intent/events-media'),
          (_) async => null,
        );
  });
  for (final deleteFile in [false, true]) {
    testWidgets('forget recent document with deleteFile=$deleteFile', (
      tester,
    ) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('recent_test'),
      );
      expect(directory, isNotNull);
      final tempDirectory = directory!;
      addTearDown(() => tempDirectory.delete(recursive: true));
      final file = File('${tempDirectory.path}/note.xopp');
      await tester.runAsync(() => file.writeAsString('original'));
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.kRecentFiles: jsonEncode([
          {'path': file.path, 'name': 'Notebook'},
        ]),
      });
      await tester.pumpWidget(XournalppMobile());
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(DocumentCard));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      if (deleteFile) {
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Forget'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => file.exists()), !deleteFile);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString(PreferencesKeys.kRecentFiles)!),
        isEmpty,
      );
      expect(find.byType(DocumentCard), findsNothing);
    });
  }

  testWidgets('document provider entries do not offer file deletion', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      PreferencesKeys.kRecentFiles: jsonEncode([
        {'path': 'content://notes/42', 'name': 'Notebook'},
      ]),
    });
    await tester.pumpWidget(XournalppMobile());
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(DocumentCard));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.text('Forget'));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentCard), findsNothing);
  });

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

  test(
    'position updates preserve metadata and do not resurrect forgotten files',
    () async {
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.kRecentFiles: jsonEncode([
          {
            'path': '/one.xopp',
            'name': 'One',
            'modified': '2025-01-01',
            'preview': 'existing',
            'currentPage': 0,
          },
          {'path': '/two.xopp', 'name': 'Two'},
        ]),
      });
      await Future.wait([
        RecentFiles.updatePage('/one.xopp', 2),
        RecentFiles.updatePage('/one.xopp', 4),
      ]);
      final prefs = await SharedPreferences.getInstance();
      var files =
          jsonDecode(prefs.getString(PreferencesKeys.kRecentFiles)!) as List;
      expect(files.map((entry) => entry['path']), ['/one.xopp', '/two.xopp']);
      expect(files.first['currentPage'], 4);
      expect(files.first['modified'], '2025-01-01');
      expect(files.first['preview'], 'existing');
      await Future.wait([
        RecentFiles.forget('/one.xopp'),
        RecentFiles.updatePage('/one.xopp', 5),
      ]);
      files =
          jsonDecode(prefs.getString(PreferencesKeys.kRecentFiles)!) as List;
      expect(files, hasLength(1));
      expect(files.single['path'], '/two.xopp');
    },
  );

  testWidgets(
    'scrolling saves the page without saving the notebook and restores it',
    (tester) async {
      const path = '/position-test.xopp';
      SharedPreferences.setMockInitialValues({});
      final file = XppFile(
        title: 'Position test',
        pages: List.generate(8, (_) => XppPage.empty(background: Colors.white)),
      );
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(XournalppMobile());
      await tester.pumpAndSettle();
      final navigator = Navigator.of(tester.element(find.byType(OpenPage)));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => CanvasPage(file: file, filePath: path),
        ),
      );
      await tester.pumpAndSettle();
      final vertical = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .firstWhere((state) => state.position.axis == Axis.vertical)
          .position;
      vertical.jumpTo(vertical.maxScrollExtent * .7);
      await tester.pumpAndSettle();
      final dynamic canvas = tester.state(find.byType(CanvasPage));
      final page = canvas.currentPage as int;
      expect(page, greaterThan(0));
      final prefs = await SharedPreferences.getInstance();
      final files =
          jsonDecode(prefs.getString(PreferencesKeys.kRecentFiles)!) as List;
      expect(files.single['currentPage'], page);
      expect(files.single.containsKey('modified'), isFalse);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final restoredPage = await XppFile.lastOpenedPageForPath(path);
      expect(restoredPage, page);
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              CanvasPage(file: file, filePath: path, initialPage: restoredPage),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic reopened = tester.state(find.byType(CanvasPage));
      expect(reopened.currentPage, page);
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
