import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Nextcloud Login Flow v2 and WebDAV access for one native client.
class NextcloudConnection {
  NextcloudConnection({
    http.Client? client,
    FlutterSecureStorage? secureStorage,
  }) : _client = client ?? http.Client(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _secureStorage;
  static const _credentialKey = 'nextcloud.credentials.v1';

  static Uri serverUri(String input) {
    final uri = Uri.parse(input.trim());
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Enter an HTTPS Nextcloud address.');
    }
    return uri.replace(path: '${uri.path.replaceAll(RegExp(r"/+$"), "")}/');
  }

  static Uri _under(Uri server, String path) => server.resolve(path);

  Future<NextcloudLogin> startLogin(Uri server) async {
    final request = http.Request('POST', _under(server, 'index.php/login/v2'))
      ..followRedirects = false;
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    if (response.statusCode != 200)
      throw NextcloudException(
        'Login could not be started',
        response.statusCode,
      );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final poll = json['poll'] as Map<String, dynamic>;
    final login = Uri.parse(json['login'] as String);
    final endpoint = Uri.parse(poll['endpoint'] as String);
    _requireSameOrigin(server, login);
    _requireSameOrigin(server, endpoint);
    return NextcloudLogin(
      login: login,
      pollEndpoint: endpoint,
      token: poll['token'] as String,
    );
  }

  Future<NextcloudCredentials?> pollLogin(
    Uri server,
    NextcloudLogin login,
  ) async {
    _requireSameOrigin(server, login.pollEndpoint);
    final request = http.Request('POST', login.pollEndpoint)
      ..followRedirects = false
      ..bodyFields = {'token': login.token};
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200)
      throw NextcloudException('Login failed', response.statusCode);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final returnedServer = serverUri(json['server'] as String);
    _requireSameOrigin(server, returnedServer);
    return NextcloudCredentials(
      server: returnedServer,
      username: json['loginName'] as String,
      password: json['appPassword'] as String,
    );
  }

  Future<void> saveCredentials(NextcloudCredentials credentials) =>
      _secureStorage.write(
        key: _credentialKey,
        value: jsonEncode({
          'server': credentials.server.toString(),
          'username': credentials.username,
          'password': credentials.password,
        }),
      );

  Future<NextcloudCredentials?> loadCredentials() async {
    final value = await _secureStorage.read(key: _credentialKey);
    if (value == null) return null;
    final json = jsonDecode(value) as Map<String, dynamic>;
    return NextcloudCredentials(
      server: serverUri(json['server'] as String),
      username: json['username'] as String,
      password: json['password'] as String,
    );
  }

  Future<void> clearCredentials() => _secureStorage.delete(key: _credentialKey);

  /// Lists direct child folders; the path consists of decoded WebDAV path segments.
  Future<List<NextcloudFolder>> folders(
    NextcloudCredentials credentials,
    List<String> path,
  ) async {
    final root = _under(
      credentials.server,
      'remote.php/dav/files/${Uri.encodeComponent(credentials.username)}/',
    );
    final target = Uri.parse(
      '${root.toString()}${path.map(Uri.encodeComponent).join('/')}${path.isEmpty ? '' : '/'}',
    );
    final request = http.Request('PROPFIND', target)
      ..followRedirects = false
      ..headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.password}'))}'
      ..headers['Depth'] = '1'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body =
          '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:displayname/></d:prop></d:propfind>';
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    if (response.statusCode != 207)
      throw NextcloudException('Could not list folders', response.statusCode);
    final document = XmlDocument.parse(response.body);
    final results = <NextcloudFolder>[];
    for (final item in document.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'response',
    )) {
      final hrefs = item.findAllElements('href', namespaceUri: 'DAV:');
      if (hrefs.isEmpty ||
          item.findAllElements('collection', namespaceUri: 'DAV:').isEmpty)
        continue;
      final href = target.resolve(hrefs.first.innerText);
      _requireSameOrigin(credentials.server, href);
      final rootSegments = root.pathSegments
          .where((s) => s.isNotEmpty)
          .toList();
      final parts = href.pathSegments.where((s) => s.isNotEmpty).toList();
      if (parts.length != rootSegments.length + path.length + 1 ||
          !_startsWith(parts, [...rootSegments, ...path]))
        continue;
      results.add(
        NextcloudFolder(
          name: parts.last,
          path: parts.skip(rootSegments.length).toList(),
        ),
      );
    }
    results.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return results;
  }

  static bool _startsWith(List<String> values, List<String> prefix) =>
      prefix.asMap().entries.every((e) => values[e.key] == e.value);
  static void _requireSameOrigin(Uri expected, Uri actual) {
    if (actual.scheme != 'https' ||
        actual.host != expected.host ||
        actual.port != expected.port)
      throw const FormatException('Unexpected Nextcloud endpoint');
  }

  void close() => _client.close();
}

class NextcloudLogin {
  const NextcloudLogin({
    required this.login,
    required this.pollEndpoint,
    required this.token,
  });
  final Uri login;
  final Uri pollEndpoint;
  final String token;
}

class NextcloudCredentials {
  const NextcloudCredentials({
    required this.server,
    required this.username,
    required this.password,
  });
  final Uri server;
  final String username;
  final String password;
}

class NextcloudFolder {
  const NextcloudFolder({required this.name, required this.path});
  final String name;
  final List<String> path;
}

class NextcloudException implements Exception {
  const NextcloudException(this.message, this.statusCode);
  final String message;
  final int statusCode;
  @override
  String toString() => '$message (HTTP $statusCode)';
}
