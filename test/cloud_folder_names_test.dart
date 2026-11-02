import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/Workspace.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/src/GoogleDriveStorage.dart';
import 'package:xournalpp/src/GoogleDriveManager.dart';
import 'package:xournalpp/src/NextcloudStorage.dart';
import 'package:xournalpp/src/NextcloudConnection.dart';
import 'package:xournalpp/src/RecentProvider.dart';
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:xournalpp/widgets/CloudSaveFolderDialog.dart';

void main() {
  test('readable provider folders use only known names', () {
    final nextcloud = NextcloudStorage(
      NextcloudCredentials(
        server: NextcloudConnection.serverUri('https://example.test/cloud'),
        username: 'alice',
        password: 'secret',
      ),
      ['Documents', 'Notes'],
    );
    final drive = GoogleDriveStorage(
      accountId: 'account-id',
      folderId: 'opaque-root',
      accessToken: () async => 'token',
    );
    expect(
      recentFolderPathFor(nextcloud, ['Classes']),
      '/Documents/Notes/Classes',
    );
    expect(recentFolderPathFor(drive, ['My Courses']), '/My Courses');
    expect(recentFolderPathFor(drive, []), '/');
    expect(recentProviderLabel(nextcloud), contains('alice@example.test'));
    expect(recentProviderLabel(nextcloud), isNot(contains('secret')));
  });

  test(
    'Drive display metadata retains account and known root folder names',
    () {
      final drive = GoogleDriveStorage(
        accountId: 'opaque-account',
        folderId: 'opaque-root',
        accessToken: () async => 'token',
      );
      final names = ['University', 'Courses'];
      drive.setDisplayMetadata(
        email: 'alice@example.test',
        rootFolderNames: names,
      );
      names.add('mutation');
      expect(drive.displayRootFolderNames, ['University', 'Courses']);
      expect(
        () => drive.displayRootFolderNames!.add('unexpected'),
        throwsUnsupportedError,
      );
      expect(recentProviderLabel(drive), contains('alice@example.test'));
      expect(
        recentFolderPathFor(drive, ['Week 1']),
        '/University/Courses/Week 1',
      );
      expect(
        GoogleDriveManager.displayFolderPathFromConfig({
          'folderPath': ['University', 'Courses'],
          'folderName': 'Courses',
        }),
        ['University', 'Courses'],
      );
      expect(
        GoogleDriveManager.displayFolderPathFromConfig({
          'folderName': 'Courses',
        }),
        ['Courses'],
      );
      expect(
        GoogleDriveManager.displayFolderPathFromConfig({'folderName': '/'}),
        isEmpty,
      );
      expect(
        GoogleDriveManager.displayFolderPathFromConfig({
          'folderPath': [1],
          'folderName': 'Courses',
        }),
        ['Courses'],
      );
      expect(GoogleDriveManager.displayFolderPathFromConfig({}), isNull);
    },
  );

  testWidgets(
    'opening a browsed Drive notebook indexes the human-readable folder',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'notebookCache.enabled.v1': false,
      });
      final bytes = Uint8List.fromList(
        const GZipEncoder().encode(
          utf8.encode(
            '<xournal><page width="200" height="300"><background type="solid" style="plain" color="white"/><layer/></page></xournal>',
          ),
        ),
      );
      final client = MockClient((request) async {
        if (request.url.queryParameters['alt'] == 'media')
          return http.Response.bytes(bytes, 200);
        final nested = (request.url.queryParameters['q'] ?? '').contains(
          "'child-id'",
        );
        return http.Response(
          jsonEncode({
            'files': nested
                ? [
                    {
                      'id': 'note-id',
                      'name': 'note.xopp.xopp',
                      'mimeType': 'application/octet-stream',
                    },
                  ]
                : [
                    {
                      'id': 'child-id',
                      'name': 'Class Name',
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
      await tester.tap(find.text('Class Name'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('note.xopp'));
      for (
        var i = 0;
        i < 100 && find.byType(CanvasPage).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        tester
            .widget<CanvasPage>(find.byType(CanvasPage))
            .file!
            .recentFolderPath,
        '/Class Name',
      );
      final prefs = await tester.runAsync(
        () => SharedPreferences.getInstance(),
      );
      for (
        var i = 0;
        i < 100 && prefs!.getString(PreferencesKeys.kRecentFiles) == null;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      final entry =
          (jsonDecode(prefs!.getString(PreferencesKeys.kRecentFiles)!) as List)
                  .single
              as Map;
      expect(entry['readablePath'], '/Class Name');
      expect(entry['readableName'], 'note.xopp.xopp');
      expect(entry['path'], 'note-id');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cloud folder picker returns stable IDs and separately reports names',
    (tester) async {
      final storage = GoogleDriveStorage(
        accountId: 'a',
        folderId: 'root',
        accessToken: () async => 'token',
        client: MockClient((request) async {
          final root = request.url.queryParameters['q']!.startsWith("'root'");
          return http.Response(
            jsonEncode({
              'files': root
                  ? [
                      {
                        'id': 'opaque-id',
                        'name': 'My Courses',
                        'mimeType': 'application/vnd.google-apps.folder',
                      },
                    ]
                  : [],
            }),
            200,
          );
        }),
      );
      List<String>? chosenIds;
      List<String>? chosenNames;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  chosenIds = await showDialog<List<String>>(
                    context: context,
                    builder: (_) => CloudSaveFolderDialog(
                      storage: storage,
                      onFolderNames: (names) => chosenNames = names,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Courses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this folder'));
      await tester.pumpAndSettle();
      expect(chosenIds, ['opaque-id']);
      expect(chosenNames, ['My Courses']);
    },
  );
}
