import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:xournalpp/src/NextcloudConnection.dart';
import 'package:xournalpp/src/NextcloudStorage.dart';
import 'package:xournalpp/src/GoogleDriveStorage.dart';
import 'package:xournalpp/widgets/Workspace.dart';

class _OtherStorage implements NotebookStorage {
  @override
  String get id => 'test storage';
  @override
  Future<List<StoredNotebook>> list() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LoadingStorage implements NotebookStorage {
  final Completer<Uint8List> download = Completer<Uint8List>();
  @override
  String get id => 'loading storage';
  @override
  Future<List<StoredNotebook>> list() async => [
    StoredNotebook(
      backendId: id,
      id: 'file',
      name: 'Downloading',
      modified: DateTime.utc(2026, 10, 30),
    ),
  ];
  @override
  Future<Uint8List> readNotebook(StoredNotebook notebook) => download.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('remote file browser uses multiple columns on a wide screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final backend = _LoadingStorage();
    notebookStorageBackends.add(backend);
    addTearDown(() => notebookStorageBackends.remove(backend));
    await tester.pumpWidget(XournalppMobile());
    await tester.pumpAndSettle();
    tester.widget<WorkspaceActions>(find.byType(WorkspaceActions)).onOpen();
    await tester.pumpAndSettle();
    await tester.tap(find.text('loading storage'));
    await tester.pumpAndSettle();
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      greaterThan(1),
    );
  });
  testWidgets(
    'remote open closes the mobile grid and shows loading until an error',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final backend = _LoadingStorage();
      notebookStorageBackends.add(backend);
      addTearDown(() => notebookStorageBackends.remove(backend));
      await tester.pumpWidget(XournalppMobile());
      await tester.pumpAndSettle();
      tester.widget<WorkspaceActions>(find.byType(WorkspaceActions)).onOpen();
      await tester.pumpAndSettle();
      await tester.tap(find.text('loading storage'));
      await tester.pumpAndSettle();
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        1,
      );
      expect(find.textContaining('Last modified:'), findsOneWidget);
      await tester.tap(find.text('Downloading'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Downloading'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      backend.download.completeError(StateError('download failed'));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('download failed'), findsOneWidget);
    },
  );
  testWidgets('Google Drive browser navigates folders by Drive ID', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      final query = request.url.queryParameters['q'] ?? '';
      final nested = query.contains("'child-id'");
      return http.Response(
        jsonEncode({
          'files': nested
              ? [
                  {
                    'id': 'note-id',
                    'name': 'note.xopp',
                    'mimeType': 'application/octet-stream',
                  },
                ]
              : [
                  {
                    'id': 'child-id',
                    'name': 'Class',
                    'mimeType': 'application/vnd.google-apps.folder',
                  },
                ],
        }),
        200,
      );
    });
    final backend = GoogleDriveStorage(
      accountId: 'test-account',
      folderId: 'root-id',
      accessToken: () async => 'token',
      client: client,
    );
    notebookStorageBackends.add(backend);
    addTearDown(() {
      notebookStorageBackends.remove(backend);
      client.close();
    });
    await tester.pumpWidget(XournalppMobile());
    await tester.pumpAndSettle();
    tester.widget<WorkspaceActions>(find.byType(WorkspaceActions)).onOpen();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Drive'));
    await tester.pumpAndSettle();
    expect(find.text('Class'), findsOneWidget);
    await tester.tap(find.text('Class'));
    await tester.pumpAndSettle();
    expect(find.text('note'), findsOneWidget);
    await tester.tap(find.text('Parent folder'));
    await tester.pumpAndSettle();
    expect(find.text('Class'), findsOneWidget);
  });
  testWidgets('Nextcloud browser navigates into and out of folders', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      final nested = request.url.path.contains('/Class/');
      final href = nested
          ? '<d:response><d:href>/remote.php/dav/files/user/Notes/Class/note.xopp</d:href><d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response>'
          : '<d:response><d:href>/remote.php/dav/files/user/Notes/Class/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>';
      return http.Response(
        '<d:multistatus xmlns:d="DAV:">$href</d:multistatus>',
        207,
      );
    });
    final backend = NextcloudStorage(
      NextcloudCredentials(
        server: NextcloudConnection.serverUri('https://cloud.example'),
        username: 'user',
        password: 'secret',
      ),
      ['Notes'],
      client: client,
    );
    notebookStorageBackends.add(backend);
    addTearDown(() {
      notebookStorageBackends.remove(backend);
      client.close();
    });
    await tester.pumpWidget(XournalppMobile());
    await tester.pumpAndSettle();
    tester.widget<WorkspaceActions>(find.byType(WorkspaceActions)).onOpen();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nextcloud'));
    await tester.pumpAndSettle();
    expect(find.text('Class'), findsOneWidget);
    await tester.tap(find.text('Class'));
    await tester.pumpAndSettle();
    expect(find.text('note'), findsOneWidget);
    await tester.tap(find.text('Parent folder'));
    await tester.pumpAndSettle();
    expect(find.text('Class'), findsOneWidget);
  });
  testWidgets('open chooses a backend when more than one is available', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _OtherStorage();
    notebookStorageBackends.add(backend);
    addTearDown(() => notebookStorageBackends.remove(backend));
    await tester.pumpWidget(XournalppMobile());
    await tester.pumpAndSettle();
    tester.widget<WorkspaceActions>(find.byType(WorkspaceActions)).onOpen();
    await tester.pumpAndSettle();
    expect(find.text('Storage location'), findsOneWidget);
    expect(find.text('Local storage'), findsOneWidget);
    expect(find.text('test storage'), findsOneWidget);
    await tester.tap(find.text('test storage'));
    await tester.pumpAndSettle();
    expect(find.text('No saved notebooks yet.'), findsOneWidget);
    expect(find.byType(CanvasPage), findsNothing);
  });
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
      expect(find.text('Forget recent document'), findsOneWidget);
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
