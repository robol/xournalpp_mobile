import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xournalpp/src/NextcloudConnection.dart';

void main() {
  test(
    'login flow uses the server subpath and polls until authorized',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          expect(
            request.url.toString(),
            'https://cloud.example/next/index.php/login/v2',
          );
          return http.Response(
            jsonEncode({
              'login': 'https://cloud.example/next/login',
              'poll': {
                'endpoint': 'https://cloud.example/next/poll',
                'token': 'temporary',
              },
            }),
            200,
          );
        }
        expect(request.body, 'token=temporary');
        if (calls == 2) return http.Response('', 404);
        return http.Response(
          jsonEncode({
            'server': 'https://cloud.example/next',
            'loginName': 'user',
            'appPassword': 'secret',
          }),
          200,
        );
      });
      final connection = NextcloudConnection(client: client);
      final server = NextcloudConnection.serverUri(
        'https://cloud.example/next',
      );
      final login = await connection.startLogin(server);
      expect(await connection.pollLogin(server, login), isNull);
      final credentials = await connection.pollLogin(server, login);
      expect(credentials!.username, 'user');
      expect(credentials.server.toString(), 'https://cloud.example/next/');
      connection.close();
    },
  );

  test('rejects insecure and cross-origin login endpoints', () async {
    expect(
      () => NextcloudConnection.serverUri('http://cloud.example'),
      throwsFormatException,
    );
    final connection = NextcloudConnection(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'login': 'https://other.example/login',
            'poll': {'endpoint': 'https://cloud.example/poll', 'token': 'x'},
          }),
          200,
        ),
      ),
    );
    await expectLater(
      connection.startLogin(
        NextcloudConnection.serverUri('https://cloud.example'),
      ),
      throwsFormatException,
    );
    connection.close();
  });

  test('WebDAV folder listing returns only immediate child folders', () async {
    final connection = NextcloudConnection(
      client: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        expect(request.headers['Depth'], '1');
        return http.Response(
          '''<d:multistatus xmlns:d="DAV:"><d:response><d:href>/next/remote.php/dav/files/user/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response><d:response><d:href>/next/remote.php/dav/files/user/My%20Notes/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response></d:multistatus>''',
          207,
        );
      }),
    );
    final folders = await connection.folders(
      NextcloudCredentials(
        server: NextcloudConnection.serverUri('https://cloud.example/next'),
        username: 'user',
        password: 'secret',
      ),
      [],
    );
    expect(folders.single.path, ['My Notes']);
    connection.close();
  });
}
