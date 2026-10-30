import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:xournalpp/src/NextcloudConnection.dart';
import 'package:xournalpp/src/NotebookStorage.dart';

/// Flat WebDAV storage. Notebook references encode the server-side filename.
class NextcloudStorage implements NotebookStorage {
  NextcloudStorage(this.credentials, this.folder, {http.Client? client})
    : _client = client ?? http.Client();
  final NextcloudCredentials credentials;
  final List<String> folder;
  final http.Client _client;
  final Map<String, Map<String, String>> _manifests = {};

  @override
  String get id =>
      'nextcloud:${sha256.convert(utf8.encode('${credentials.server}|${credentials.username}|${jsonEncode(folder)}'))}';
  Uri get _directory => credentials.server.resolve(
    'remote.php/dav/files/${Uri.encodeComponent(credentials.username)}/${folder.map(Uri.encodeComponent).join('/')}${folder.isEmpty ? '' : '/'}',
  );
  Uri _url(String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\')) {
      throw const FormatException('Invalid WebDAV file name');
    }
    return _directory.resolve(Uri.encodeComponent(name));
  }

  String get _authorization =>
      'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.password}'))}';

  Future<http.Response> _request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    if (uri.scheme != 'https' ||
        uri.host != credentials.server.host ||
        uri.port != credentials.server.port)
      throw StateError('Invalid WebDAV destination');
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll({'Authorization': _authorization, ...headers});
    if (body != null) request.bodyBytes = body;
    return http.Response.fromStream(await _client.send(request));
  }

  void _check(http.Response response, String operation, List<int> allowed) {
    if (!allowed.contains(response.statusCode))
      throw NextcloudException(operation, response.statusCode);
  }

  @override
  Future<StoredNotebook?> save({
    required Uint8List bytes,
    required String name,
    StoredNotebook? existing,
    required List<NotebookPdfResource> pdfs,
  }) async {
    if (existing != null && existing.backendId != id)
      throw ArgumentError('Wrong storage backend');
    final filename =
        existing?.id ??
        (name.toLowerCase().endsWith('.xopp') ? name : '$name.xopp');
    if (filename.isEmpty ||
        filename.contains('/') ||
        filename.contains('\\') ||
        filename == '.' ||
        filename == '..')
      throw const FormatException('Invalid notebook name');
    final mappings = <String, String>{};
    for (final pdf in pdfs) {
      final content = await pdf.read();
      final resourceName = '.xournalpp-pdf-${sha256.convert(content)}.pdf';
      final upload = await _request(
        'PUT',
        _url(resourceName),
        headers: {'Content-Type': 'application/pdf', 'If-None-Match': '*'},
        body: content,
      );
      _check(upload, 'Could not save background PDF', [200, 201, 204, 412]);
      if (upload.statusCode == 412) {
        final existingPdf = await _request('GET', _url(resourceName));
        _check(existingPdf, 'Could not verify background PDF', [200]);
        if (sha256.convert(existingPdf.bodyBytes) != sha256.convert(content)) {
          throw const FormatException(
            'Existing background PDF failed verification',
          );
        }
      }
      mappings[pdf.reference] = resourceName;
    }
    // Embed only an opaque manifest name in the notebook; Xournal++ ignores the extension attribute.
    final xml = XmlDocument.parse(
      utf8.decode(const GZipDecoder().decodeBytes(bytes)),
    );
    final manifest = utf8.encode(jsonEncode(mappings));
    final manifestName = '.xournalpp-map-${sha256.convert(manifest)}.json';
    final manifestUpload = await _request(
      'PUT',
      _url(manifestName),
      headers: {'Content-Type': 'application/json', 'If-None-Match': '*'},
      body: manifest,
    );
    _check(manifestUpload, 'Could not save PDF mapping', [200, 201, 204, 412]);
    if (manifestUpload.statusCode == 412) {
      final existingManifest = await _request('GET', _url(manifestName));
      _check(existingManifest, 'Could not verify PDF mapping', [200]);
      if (sha256.convert(existingManifest.bodyBytes) !=
          sha256.convert(manifest)) {
        throw const FormatException('Existing PDF mapping failed verification');
      }
    }
    xml.rootElement.setAttribute('xournalpp-mobile-pdf-map', manifestName);
    final updated = const GZipEncoder().encode(utf8.encode(xml.toXmlString()));
    final temporary = '.xournalpp-upload-${sha256.convert(updated)}.tmp';
    final upload = await _request('PUT', _url(temporary), body: updated);
    _check(upload, 'Could not upload notebook', [200, 201, 204]);
    final move = await _request(
      'MOVE',
      _url(temporary),
      headers: {
        'Destination': _url(filename).toString(),
        'Overwrite': existing == null ? 'F' : 'T',
      },
    );
    if (move.statusCode == 412 && existing == null) {
      throw NextcloudNameConflict(filename);
    }
    _check(move, 'Could not publish notebook', [201, 204]);
    _manifests[filename] = mappings;
    return StoredNotebook(backendId: id, id: filename, name: name);
  }

  @override
  Future<Uint8List> readNotebook(StoredNotebook notebook) async {
    if (notebook.backendId != id) throw ArgumentError('Wrong storage backend');
    final response = await _request('GET', _url(notebook.id));
    _check(response, 'Could not read notebook', [200]);
    final bytes = response.bodyBytes;
    final xml = XmlDocument.parse(
      utf8.decode(const GZipDecoder().decodeBytes(bytes)),
    );
    final name = xml.rootElement.getAttribute('xournalpp-mobile-pdf-map');
    if (name != null) {
      if (!RegExp(r'^\.xournalpp-map-[0-9a-f]{64}\.json$').hasMatch(name))
        throw const FormatException('Invalid PDF mapping');
      final response = await _request('GET', _url(name));
      _check(response, 'Could not read PDF mapping', [200]);
      if (sha256.convert(response.bodyBytes).toString() !=
          name.substring(15, 79))
        throw const FormatException('PDF mapping integrity check failed');
      _manifests[notebook.id] =
          (jsonDecode(utf8.decode(response.bodyBytes)) as Map).map(
            (key, value) => MapEntry(key as String, value as String),
          );
    } else {
      _manifests[notebook.id] = {};
    }
    return bytes;
  }

  @override
  Future<Uint8List> readPdf(StoredNotebook notebook, String reference) async {
    if (notebook.backendId != id) throw ArgumentError('Wrong storage backend');
    if (!_manifests.containsKey(notebook.id)) await readNotebook(notebook);
    final name = _manifests[notebook.id]?[reference];
    if (name == null ||
        !RegExp(r'^\.xournalpp-pdf-[0-9a-f]{64}\.pdf$').hasMatch(name))
      throw StateError('Background PDF is unavailable');
    final response = await _request('GET', _url(name));
    _check(response, 'Could not read background PDF', [200]);
    if (sha256.convert(response.bodyBytes).toString() != name.substring(15, 79))
      throw const FormatException('PDF integrity check failed');
    return response.bodyBytes;
  }

  @override
  Future<List<StoredNotebook>> list() async {
    final response = await _request(
      'PROPFIND',
      _directory,
      headers: {'Depth': '1', 'Content-Type': 'application/xml'},
      body: utf8.encode(
        '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>',
      ),
    );
    _check(response, 'Could not list notebooks', [207]);
    final root = _directory.pathSegments.where((s) => s.isNotEmpty).toList();
    final results = <StoredNotebook>[];
    for (final item
        in XmlDocument.parse(response.body).descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'response')) {
      final hrefs = item.findAllElements('href', namespaceUri: 'DAV:');
      if (hrefs.isEmpty ||
          item.findAllElements('collection', namespaceUri: 'DAV:').isNotEmpty)
        continue;
      final uri = _directory.resolve(hrefs.first.innerText);
      if (uri.scheme != credentials.server.scheme ||
          uri.host != credentials.server.host ||
          uri.port != credentials.server.port)
        continue;
      final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (parts.length != root.length + 1 ||
          !root.asMap().entries.every((e) => parts[e.key] == e.value))
        continue;
      final filename = parts.last;
      if (!filename.toLowerCase().endsWith('.xopp')) continue;
      results.add(
        StoredNotebook(
          backendId: id,
          id: filename,
          name: filename.substring(0, filename.length - 5),
        ),
      );
    }
    return results;
  }

  @override
  Future<void> forget(StoredNotebook notebook) async =>
      throw UnsupportedError('Remote notebooks cannot be forgotten');
}

class NextcloudNameConflict implements Exception {
  const NextcloudNameConflict(this.filename);
  final String filename;
}
