import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xournalpp/src/GoogleDesktopAuthIO.dart';

class RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'browser authorization uses PKCE and persists a refresh token',
    () async {
      Uri? authorization;
      final calls = <http.Request>[];
      final auth = GoogleDesktopAuth(
        clientId: 'desktop-id',
        clientSecret: 'desktop-secret',
        client: MockClient((request) async {
          calls.add(request);
          if (request.url.path == '/token') {
            return http.Response(
              jsonEncode({
                'access_token': 'access',
                'refresh_token': 'refresh',
                'expires_in': 3600,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'user': {
                'permissionId': 'account',
                'emailAddress': 'user@example.com',
              },
            }),
            200,
          );
        }),
        launch: (uri) async {
          authorization = uri;
          final params = uri.queryParameters;
          final callback = Uri.parse(params['redirect_uri']!).replace(
            queryParameters: {'code': 'code', 'state': params['state']!},
          );
          unawaited(
            HttpOverrides.runWithHttpOverrides(
              () => http.get(callback),
              RealHttpOverrides(),
            ),
          );
          return true;
        },
      );
      final account = await auth.connect();
      expect(account.id, 'account');
      expect(authorization!.queryParameters['code_challenge_method'], 'S256');
      expect(calls.first.bodyFields['code_verifier'], isNotEmpty);
      expect(await auth.accessToken(account), 'access');
      expect(
        await const FlutterSecureStorage().read(
          key: 'googleDrive.desktop.refresh.account',
        ),
        'refresh',
      );
      await auth.disconnect(account.id);
      expect(await auth.restore(account.id), isNull);
    },
  );

  test('restored credentials refresh and reuse the access token', () async {
    FlutterSecureStorage.setMockInitialValues({
      'googleDrive.desktop.refresh.account': 'refresh',
    });
    var count = 0;
    final auth = GoogleDesktopAuth(
      clientId: 'id',
      clientSecret: 'secret',
      client: MockClient((request) async {
        count++;
        expect(request.bodyFields['refresh_token'], 'refresh');
        return http.Response(
          jsonEncode({'access_token': 'renewed', 'expires_in': 3600}),
          200,
        );
      }),
    );
    final account = (await auth.restore('account'))!;
    expect(
      await Future.wait([auth.accessToken(account), auth.accessToken(account)]),
      ['renewed', 'renewed'],
    );
    expect(count, 1);
  });

  test('failed refresh does not remove the saved credential', () async {
    FlutterSecureStorage.setMockInitialValues({
      'googleDrive.desktop.refresh.account': 'refresh',
    });
    final auth = GoogleDesktopAuth(
      clientId: 'id',
      clientSecret: 'secret',
      client: MockClient((_) async => http.Response('{}', 400)),
    );
    final account = (await auth.restore('account'))!;
    await expectLater(auth.accessToken(account), throwsStateError);
    expect(
      await const FlutterSecureStorage().read(
        key: 'googleDrive.desktop.refresh.account',
      ),
      'refresh',
    );
  });
}
