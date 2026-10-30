import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xournalpp/src/NextcloudConnection.dart';
import 'package:xournalpp/src/NextcloudStorage.dart';
import 'package:xournalpp/src/NotebookStorage.dart';

void main() {
  test(
    'lists folders and opens and saves nested notebooks in their folder',
    () async {
      final objects = <String, Uint8List>{};
      final requests = <String>[];
      final client = MockClient((request) async {
        final path = request.url.path;
        requests.add('${request.method} $path');
        if (request.method == 'PROPFIND') {
          return http.Response(
            '''<d:multistatus xmlns:d="DAV:"><d:response><d:href>/next/remote.php/dav/files/user/Notes/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response><d:response><d:href>/next/remote.php/dav/files/user/Notes/Class%20A/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response><d:response><d:href>/next/remote.php/dav/files/user/Notes/Class%20A/lesson.xopp</d:href><d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response></d:multistatus>''',
            207,
          );
        }
        if (request.method == 'PUT') {
          objects[path] = request.bodyBytes;
          return http.Response('', 201);
        }
        if (request.method == 'MOVE') {
          objects[Uri.parse(request.headers['Destination']!).path] = objects
              .remove(path)!;
          return http.Response('', 201);
        }
        if (request.method == 'GET')
          return objects.containsKey(path)
              ? http.Response.bytes(objects[path]!, 200)
              : http.Response('', 404);
        return http.Response('', 500);
      });
      final credentials = NextcloudCredentials(
        server: NextcloudConnection.serverUri('https://cloud.example/next'),
        username: 'user',
        password: 'secret',
      );
      final storage = NextcloudStorage(credentials, ['Notes'], client: client);
      final listing = await storage.listFolder([]);
      expect(listing.folders, ['Class A']);
      expect(listing.notebooks, isEmpty);
      final nested = StoredNotebook(
        backendId: storage.id,
        id: 'Class A/lesson.xopp',
        name: 'lesson',
      );
      final bytes = Uint8List.fromList(
        const GZipEncoder().encode(utf8.encode('<xournal/>')),
      );
      final result = (await storage.save(
        bytes: bytes,
        name: 'lesson',
        existing: nested,
        pdfs: [
          NotebookPdfResource(
            reference: 'source.pdf',
            read: () async => Uint8List.fromList([1, 2]),
          ),
        ],
      ))!;
      expect(result.id, 'Class A/lesson.xopp');
      final reopened = NextcloudStorage(credentials, ['Notes'], client: client);
      await reopened.readNotebook(result);
      expect(await reopened.readPdf(result, 'source.pdf'), [1, 2]);
      expect(
        requests.any(
          (path) => path.startsWith(
            'PUT /next/remote.php/dav/files/user/Notes/Class%20A/.xournalpp-pdf-',
          ),
        ),
        isTrue,
      );
      await expectLater(storage.listFolder(['..']), throwsFormatException);
    },
  );
  test(
    'saves and reopens a notebook with PDF companions without paths',
    () async {
      final objects = <String, Uint8List>{};
      var failMove = false;
      final client = MockClient((request) async {
        final name = request.url.pathSegments.last;
        if (request.method == 'PUT') {
          if (request.headers['If-None-Match'] == '*' &&
              objects.containsKey(name))
            return http.Response('', 412);
          objects[name] = request.bodyBytes;
          return http.Response('', 201);
        }
        if (request.method == 'MOVE') {
          if (failMove) return http.Response('', 500);
          final dest = Uri.parse(
            request.headers['Destination']!,
          ).pathSegments.last;
          if (request.headers['Overwrite'] == 'F' && objects.containsKey(dest))
            return http.Response('', 412);
          objects[dest] = objects.remove(name)!;
          return http.Response('', 201);
        }
        if (request.method == 'GET')
          return objects.containsKey(name)
              ? http.Response.bytes(objects[name]!, 200)
              : http.Response('', 404);
        throw StateError('Unexpected ${request.method}');
      });
      final creds = NextcloudCredentials(
        server: NextcloudConnection.serverUri('https://cloud.example/next'),
        username: 'user',
        password: 'secret',
      );
      final storage = NextcloudStorage(creds, ['Notes'], client: client);
      final bytes = Uint8List.fromList(
        const GZipEncoder().encode(utf8.encode('<xournal><page/></xournal>')),
      );
      final pdf = Uint8List.fromList([1, 2, 3]);
      final saved = (await storage.save(
        bytes: bytes,
        name: 'Example',
        pdfs: [
          NotebookPdfResource(
            reference: '/old/location.pdf',
            read: () async => pdf,
          ),
        ],
      ))!;
      final reopened = NextcloudStorage(creds, ['Notes'], client: client);
      final notebookBytes = await reopened.readNotebook(saved);
      expect(
        utf8.decode(const GZipDecoder().decodeBytes(notebookBytes)),
        contains('xournalpp-mobile-pdf-map'),
      );
      expect(await reopened.readPdf(saved, '/old/location.pdf'), pdf);
      await expectLater(
        storage.save(bytes: bytes, name: 'Example', pdfs: []),
        throwsA(isA<NextcloudNameConflict>()),
      );
      final previous = objects['Example.xopp'];
      failMove = true;
      await expectLater(
        storage.save(bytes: bytes, name: 'Example', existing: saved, pdfs: []),
        throwsA(isA<NextcloudException>()),
      );
      expect(objects['Example.xopp'], previous);
    },
  );
}
