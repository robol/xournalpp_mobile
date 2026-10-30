import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class DesktopGoogleAccount {
  DesktopGoogleAccount(this.id, this.email);
  final String id;
  final String email;
}

/// OAuth installed-app flow. Credentials remain in the platform keyring.
class GoogleDesktopAuth {
  GoogleDesktopAuth({
    http.Client? client,
    FlutterSecureStorage? storage,
    this.clientId = const String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID'),
    this.clientSecret = const String.fromEnvironment(
      'GOOGLE_DESKTOP_CLIENT_SECRET',
    ),
    Future<bool> Function(Uri)? launch,
  }) : _client = client ?? http.Client(),
       _storage = storage ?? const FlutterSecureStorage(),
       _launch =
           launch ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  final http.Client _client;
  final FlutterSecureStorage _storage;
  final Future<bool> Function(Uri) _launch;
  final String clientId;
  final String clientSecret;
  String? _token;
  DateTime? _expires;
  String? _tokenAccount;
  Future<String>? _refreshing;
  static const _scope = 'https://www.googleapis.com/auth/drive';
  static const _tokenUrl = 'https://oauth2.googleapis.com/token';
  String _key(String id) => 'googleDrive.desktop.refresh.$id';

  String _random() {
    final random = Random.secure();
    return base64UrlEncode(
      List.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
  }

  Future<DesktopGoogleAccount> connect() async {
    if (clientId.isEmpty || clientSecret.isEmpty) {
      throw StateError(
        'Google desktop OAuth configuration is missing from this build.',
      );
    }
    final verifier = _random();
    final state = _random();
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}/oauth2callback';
    try {
      final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': _scope,
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
      });
      if (!await _launch(url))
        throw StateError('Could not open the browser for Google sign-in.');
      final completer = Completer<String>();
      server.listen((request) async {
        if (request.uri.path != '/oauth2callback') {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        final params = request.uri.queryParameters;
        if (params['state'] != state) {
          request.response.statusCode = 400;
          request.response.write('Invalid sign-in response.');
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.text;
        request.response.write('You can return to Xournal++ Mobile.');
        await request.response.close();
        if (!completer.isCompleted) {
          if (params['error'] != null || params['code'] == null) {
            completer.completeError(
              StateError('Google sign-in was cancelled or denied.'),
            );
          } else {
            completer.complete(params['code']);
          }
        }
      });
      final code = await completer.future.timeout(const Duration(minutes: 5));
      final result = await _exchange({
        'code': code,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      });
      final refresh = result['refresh_token'];
      if (refresh is! String || refresh.isEmpty)
        throw StateError('Google did not provide a refresh token.');
      _tokenAccount = null;
      _setToken(result);
      final response = await _client.get(
        Uri.https('www.googleapis.com', '/drive/v3/about', {
          'fields': 'user(permissionId,emailAddress)',
        }),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (response.statusCode != 200)
        throw StateError(
          'Could not identify the Google Drive account (${response.statusCode}).',
        );
      final user =
          (jsonDecode(response.body) as Map<String, dynamic>)['user']
              as Map<String, dynamic>;
      final account = DesktopGoogleAccount(
        user['permissionId'] as String,
        user['emailAddress'] as String,
      );
      await _storage.write(key: _key(account.id), value: refresh);
      _tokenAccount = account.id;
      return account;
    } finally {
      await server.close(force: true);
    }
  }

  Future<DesktopGoogleAccount?> restore(String id) async {
    if (await _storage.read(key: _key(id)) == null) return null;
    _token = null;
    _tokenAccount = null;
    _expires = null;
    return DesktopGoogleAccount(id, '');
  }

  Future<String> accessToken(DesktopGoogleAccount account) async {
    if (_tokenAccount == account.id &&
        _token != null &&
        _expires != null &&
        DateTime.now().isBefore(_expires!))
      return _token!;
    return _refreshing ??= _refresh(
      account,
    ).whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh(DesktopGoogleAccount account) async {
    final refresh = await _storage.read(key: _key(account.id));
    if (refresh == null)
      throw StateError(
        'Google Drive authorization expired. Reconnect in settings.',
      );
    final result = await _exchange({
      'refresh_token': refresh,
      'grant_type': 'refresh_token',
    });
    _setToken(result);
    _tokenAccount = account.id;
    final replacement = result['refresh_token'];
    if (replacement is String && replacement.isNotEmpty)
      await _storage.write(key: _key(account.id), value: replacement);
    return _token!;
  }

  Future<Map<String, dynamic>> _exchange(Map<String, String> fields) async {
    final response = await _client.post(
      Uri.parse(_tokenUrl),
      body: {...fields, 'client_id': clientId, 'client_secret': clientSecret},
    );
    if (response.statusCode != 200)
      throw StateError(
        'Google authorization failed (${response.statusCode}). Reconnect in settings.',
      );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void _setToken(Map<String, dynamic> result) {
    final token = result['access_token'];
    final seconds = result['expires_in'];
    if (token is! String || token.isEmpty || seconds is! num)
      throw StateError('Invalid Google authorization response.');
    _token = token;
    _expires = DateTime.now().add(
      Duration(seconds: max(0, seconds.toInt() - 60)),
    );
  }

  Future<void> disconnect(String id) async {
    await _storage.delete(key: _key(id));
    _token = null;
    _tokenAccount = null;
    _expires = null;
  }
}
