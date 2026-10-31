import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xournalpp/src/GoogleDriveStorage.dart';
import 'package:xournalpp/src/NotebookStorage.dart';

void main() {
  test(
    'duplicate notebook name does not overwrite and reports its Drive ID',
    () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'files': [
              {
                'id': 'existing-id',
                'name': 'Notes.xopp',
                'mimeType': 'application/octet-stream',
              },
            ],
          }),
          200,
        ),
      );
      final storage = GoogleDriveStorage(
        accountId: 'account',
        folderId: 'root-id',
        accessToken: () async => 'token',
        client: client,
      );
      await expectLater(
        storage.save(bytes: Uint8List(0), name: 'Notes', pdfs: []),
        throwsA(
          isA<GoogleDriveNameConflict>().having(
            (e) => e.fileId,
            'fileId',
            'existing-id',
          ),
        ),
      );
    },
  );

  test('checks for name conflicts in the selected folder', () async {
    final client = MockClient((request) async {
      expect(
        request.url.queryParameters['q'],
        "'subfolder-id' in parents and trashed = false",
      );
      return http.Response(
        jsonEncode({
          'files': [
            {
              'id': 'existing-id',
              'name': 'Notes.xopp',
              'mimeType': 'application/octet-stream',
            },
          ],
        }),
        200,
      );
    });
    final storage = GoogleDriveStorage(
      accountId: 'account',
      folderId: 'root-id',
      accessToken: () async => 'token',
      client: client,
    );
    await expectLater(
      storage.save(
        bytes: Uint8List(0),
        name: 'Notes',
        pdfs: [],
        destinationFolderId: 'subfolder-id',
      ),
      throwsA(isA<GoogleDriveNameConflict>()),
    );
  });

  test('failed PDF upload does not publish notebook', () async {
    var uploads = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/drive/v3/files')
        return http.Response(jsonEncode({'files': []}), 200);
      uploads++;
      return http.Response('', 503);
    });
    final storage = GoogleDriveStorage(
      accountId: 'account',
      folderId: 'root-id',
      accessToken: () async => 'token',
      client: client,
    );
    await expectLater(
      storage.save(
        bytes: Uint8List(0),
        name: 'Notes',
        pdfs: [
          NotebookPdfResource(
            reference: 'source.pdf',
            read: () async => Uint8List.fromList([1]),
          ),
        ],
      ),
      throwsA(isA<GoogleDriveException>()),
    );
    expect(uploads, 1);
  });
  test('lists paginated folders and notebooks using opaque IDs', () async {
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer access-token');
      expect(
        request.url.queryParameters['q'],
        "'folder-id' in parents and trashed = false",
      );
      if (request.url.queryParameters['pageToken'] == null) {
        return http.Response(
          jsonEncode({
            'nextPageToken': 'next',
            'files': [
              {
                'id': 'sub-id',
                'name': 'Class',
                'mimeType': 'application/vnd.google-apps.folder',
              },
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'files': [
            {
              'id': 'note-id',
              'name': 'Notes.xopp',
              'mimeType': 'application/octet-stream',
              'modifiedTime': '2026-10-30T12:34:56Z',
            },
            {
              'id': 'pdf-id',
              'name': 'source.pdf',
              'mimeType': 'application/pdf',
            },
          ],
        }),
        200,
      );
    });
    final storage = GoogleDriveStorage(
      accountId: 'account',
      folderId: 'folder-id',
      accessToken: () async => 'access-token',
      client: client,
    );
    final result = await storage.listFolder('folder-id');
    expect(result.folders.single.id, 'sub-id');
    expect(result.notebooks.single.id, 'note-id');
    expect(result.notebooks.single.name, 'Notes');
    expect(
      result.notebooks.single.modified,
      DateTime.utc(2026, 10, 30, 12, 34, 56),
    );
  });

  test('saves a PDF and manifest before publishing and reopens them', () async {
    final objects = <String, Uint8List>{};
    var nextId = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/drive/v3/files')
        return http.Response(jsonEncode({'files': []}), 200);
      if (request.url.path == '/upload/drive/v3/files' &&
          request.method == 'POST') {
        final contentType = request.headers['Content-Type']!;
        final boundary = contentType.split('boundary=').last;
        final body = latin1.decode(request.bodyBytes);
        final payloadStart =
            body.indexOf('\r\n\r\n', body.indexOf('--$boundary', 2)) + 4;
        final payloadEnd = body.lastIndexOf('\r\n--$boundary--');
        final fileId = 'id-${++nextId}';
        objects[fileId] = Uint8List.fromList(
          latin1.encode(body.substring(payloadStart, payloadEnd)),
        );
        return http.Response(jsonEncode({'id': fileId}), 200);
      }
      if (request.method == 'GET' &&
          request.url.queryParameters['alt'] == 'media')
        return http.Response.bytes(
          objects[request.url.pathSegments.last]!,
          200,
        );
      throw StateError('Unexpected request ${request.method} ${request.url}');
    });
    final storage = GoogleDriveStorage(
      accountId: 'account',
      folderId: 'root-id',
      accessToken: () async => 'token',
      client: client,
    );
    final xopp = Uint8List.fromList(
      const GZipEncoder().encode(utf8.encode('<xournal><page/></xournal>')),
    );
    final pdf = Uint8List.fromList([1, 2, 3, 255]);
    final saved = (await storage.save(
      bytes: xopp,
      name: 'Notes',
      pdfs: [
        NotebookPdfResource(reference: 'source.pdf', read: () async => pdf),
      ],
    ))!;
    expect(saved.id, 'id-3');
    final reopened = GoogleDriveStorage(
      accountId: 'account',
      folderId: 'root-id',
      accessToken: () async => 'token',
      client: client,
    );
    await reopened.readNotebook(saved);
    expect(await reopened.readPdf(saved, 'source.pdf'), pdf);
  });
}
