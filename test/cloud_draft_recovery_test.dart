import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xournalpp/src/DraftRecovery.dart';
import 'package:xournalpp/src/GoogleDriveStorage.dart';
import 'package:xournalpp/src/NextcloudStorage.dart';
import 'package:xournalpp/src/NextcloudConnection.dart';
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:xournalpp/src/XppFile.dart';

void main() {
  testWidgets(
    'unverified recovered draft offers copy or cancel, never overwrite',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'notebookCache.enabled.v1': false,
      });
      final storage = GoogleDriveStorage(
        accountId: 'a',
        folderId: 'root',
        accessToken: () async => 'token',
        client: MockClient(
          (request) async => throw StateError('Save must not contact original'),
        ),
      );
      final file = XppFile.empty(title: 'Recovered')
        ..storage = storage
        ..storageNotebook = StoredNotebook(
          backendId: storage.id,
          id: 'original',
          name: 'Recovered',
        )
        ..requiresSeparateCopy = true;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: CanvasPage(file: file, filePath: 'original'),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic canvas = tester.state(find.byType(CanvasPage));
      final saving = canvas.saveFile();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Save a copy'), findsOneWidget);
      expect(find.text('Overwrite original'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await saving, false);
      expect(file.requiresSeparateCopy, true);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final drive in [false, true]) {
    for (final scenario in [
      'unchanged',
      'changed',
      'missing',
      'offline',
      'cached',
      'later change',
    ]) {
      test('${drive ? 'Drive' : 'Nextcloud'} recovery: $scenario', () async {
        Uint8List encode(String text) => Uint8List.fromList(
          const GZipEncoder().encode(
            utf8.encode('<xournal><title>$text</title></xournal>'),
          ),
        );
        final initial = encode('original');
        var remote = initial;
        var offline = false;
        var reads = 0;
        var overwrites = 0;
        NotebookStorage client() {
          final transport = MockClient((request) async {
            if (offline) throw StateError('offline');
            if (request.method == 'GET') {
              if (request.url.queryParameters['fields'] == 'id,parents')
                return http.Response('{"parents":["root"]}', 200);
              if (drive && request.url.path == '/drive/v3/files')
                return http.Response('{"files":[]}', 200);
              reads++;
              return http.Response.bytes(
                remote,
                200,
                headers: {'etag': '"revision"'},
              );
            }
            if (request.method == 'PATCH' || request.method == 'MOVE')
              overwrites++;
            return http.Response(drive ? '{"id":"manifest"}' : '', 201);
          });
          return drive
              ? GoogleDriveStorage(
                  accountId: 'a',
                  folderId: 'root',
                  accessToken: () async => 'token',
                  client: transport,
                )
              : NextcloudStorage(
                  NextcloudCredentials(
                    server: NextcloudConnection.serverUri(
                      'https://cloud.example',
                    ),
                    username: 'a',
                    password: 'p',
                  ),
                  ['Notes'],
                  client: transport,
                );
        }

        final first = client();
        final notebook = StoredNotebook(
          backendId: first.id,
          id: drive ? 'file' : 'Notes.xopp',
          name: 'Notes',
        );
        await first.readNotebook(notebook);
        // Serialize Device A's baseline independently of its edited draft bytes.
        final draft = RecoveryDraft.fromJson(
          jsonDecode(
                jsonEncode(
                  RecoveryDraft(
                    id: '1_1',
                    bytes: encode('A edits'),
                    page: 0,
                    originalPath: notebook.id,
                    backendId: notebook.backendId,
                    sourceDigest: scenario == 'missing'
                        ? null
                        : (first as NotebookVersionBaseline).sourceDigest(
                            notebook,
                          ),
                  ).toJson(),
                ),
              )
              as Map<String, dynamic>,
        );
        if (scenario == 'changed') remote = encode('Device B edits');
        offline = scenario == 'offline';
        final restarted = client(); // Empty provider digest map after restart.
        final recovered = XppFile()
          ..storage = restarted
          ..storageNotebook = notebook
          ..openedFromCache = scenario == 'cached';
        final before = reads;
        await recovered.restoreCloudSourceDigest(draft.sourceDigest);
        final safe = scenario == 'unchanged' || scenario == 'later change';
        expect(recovered.requiresSeparateCopy, !safe);
        if (scenario == 'cached' || scenario == 'missing')
          expect(reads, before);
        if (scenario == 'later change' || scenario == 'changed') {
          // A change after validation must still be caught by the normal save guard.
          remote = encode('Device B latest edits');
          await expectLater(
            restarted.save(
              bytes: draft.bytes,
              name: 'Notes',
              existing: notebook,
              pdfs: [],
            ),
            throwsA(isA<NotebookEditConflict>()),
          );
          expect(overwrites, 0);
        }
      });
    }
  }
}
