import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:xournalpp/src/NotebookStorage.dart';

/// Drive storage uses opaque Drive file IDs and a caller-supplied OAuth token.
class GoogleDriveStorage implements NotebookStorage {
  GoogleDriveStorage({
    required this.accountId,
    required this.folderId,
    required this.accessToken,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final String accountId;
  final String folderId;
  final Future<String> Function() accessToken;
  final http.Client _client;
  final Map<String, Map<String, String>> _manifests = {};
  static const _folderMime = 'application/vnd.google-apps.folder';
  static const _manifestAttribute = 'xournalpp-mobile-drive-map';

  @override
  String get id =>
      'gdrive:${sha256.convert(utf8.encode('$accountId|$folderId'))}';

  Future<http.Response> _request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    if (uri.scheme != 'https' || uri.host != 'www.googleapis.com')
      throw StateError('Invalid Google Drive endpoint');
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll({
      'Authorization': 'Bearer ${await accessToken()}',
      ...headers,
    });
    if (body != null) request.bodyBytes = body;
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw GoogleDriveException(response.statusCode);
    return response;
  }

  static String _queryLiteral(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
  Future<List<Map<String, dynamic>>> _children(String parent) async {
    final files = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "'${_queryLiteral(parent)}' in parents and trashed = false",
        'fields': 'nextPageToken,files(id,name,mimeType,parents)',
        'pageSize': '1000',
        if (pageToken != null) 'pageToken': pageToken,
      });
      final response = await _request('GET', uri);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      files.addAll(
        (data['files'] as List).map(
          (entry) => Map<String, dynamic>.from(entry as Map),
        ),
      );
      pageToken = data['nextPageToken'] as String?;
    } while (pageToken != null);
    return files;
  }

  Future<GoogleDriveFolderListing> listFolder(String parentId) async {
    final children = await _children(parentId);
    final folders = <GoogleDriveFolder>[];
    final notebooks = <StoredNotebook>[];
    for (final file in children) {
      final name = file['name'] as String;
      final fileId = file['id'] as String;
      if (file['mimeType'] == _folderMime) {
        folders.add(GoogleDriveFolder(id: fileId, name: name));
      } else if (name.toLowerCase().endsWith('.xopp')) {
        notebooks.add(
          StoredNotebook(
            backendId: id,
            id: fileId,
            name: name.substring(0, name.length - 5),
          ),
        );
      }
    }
    folders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    notebooks.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return GoogleDriveFolderListing(folders: folders, notebooks: notebooks);
  }

  @override
  Future<List<StoredNotebook>> list() async =>
      (await listFolder(folderId)).notebooks;

  Future<String> _parentOf(String fileId) async {
    final response = await _request(
      'GET',
      Uri.https(
        'www.googleapis.com',
        '/drive/v3/files/${Uri.encodeComponent(fileId)}',
        {'fields': 'id,parents'},
      ),
    );
    final parents =
        (jsonDecode(response.body) as Map<String, dynamic>)['parents'] as List;
    if (parents.isEmpty) throw StateError('Notebook has no Drive folder');
    return parents.first as String;
  }

  Future<Uint8List> _download(String fileId) async => (await _request(
    'GET',
    Uri.https(
      'www.googleapis.com',
      '/drive/v3/files/${Uri.encodeComponent(fileId)}',
      {'alt': 'media'},
    ),
  )).bodyBytes;

  Future<String> _upload(
    String name,
    String parent,
    Uint8List bytes, {
    String? existingId,
    String mime = 'application/octet-stream',
  }) async {
    if (existingId != null) {
      final response = await _request(
        'PATCH',
        Uri.https(
          'www.googleapis.com',
          '/upload/drive/v3/files/${Uri.encodeComponent(existingId)}',
          {'uploadType': 'media', 'fields': 'id'},
        ),
        headers: {'Content-Type': mime},
        body: bytes,
      );
      return (jsonDecode(response.body) as Map<String, dynamic>)['id']
          as String;
    }
    final boundary = 'xpp-${sha256.convert(bytes)}';
    final builder = BytesBuilder(copy: false);
    builder.add(
      utf8.encode(
        '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${jsonEncode({
          'name': name,
          'parents': [parent],
        })}\r\n--$boundary\r\nContent-Type: $mime\r\n\r\n',
      ),
    );
    builder.add(bytes);
    builder.add(utf8.encode('\r\n--$boundary--\r\n'));
    final response = await _request(
      'POST',
      Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
        'uploadType': 'multipart',
        'fields': 'id',
      }),
      headers: {'Content-Type': 'multipart/related; boundary=$boundary'},
      body: builder.takeBytes(),
    );
    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
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
    final parent = existing == null ? folderId : await _parentOf(existing.id);
    final filename = name.toLowerCase().endsWith('.xopp') ? name : '$name.xopp';
    final children = await _children(parent);
    final collisions = children
        .where((child) => child['name'] == filename)
        .toList();
    if (existing == null && collisions.isNotEmpty) {
      if (collisions.length != 1 ||
          collisions.single['mimeType'] == _folderMime) {
        throw StateError(
          'Multiple Drive items use this name; choose a different name.',
        );
      }
      throw GoogleDriveNameConflict(
        filename,
        collisions.single['id'] as String,
      );
    }
    final mapping = <String, String>{};
    for (final pdf in pdfs) {
      final data = await pdf.read();
      final resourceName = '.xournalpp-pdf-${sha256.convert(data)}.pdf';
      final matches = children
          .where((child) => child['name'] == resourceName)
          .toList();
      String resourceId;
      if (matches.isEmpty) {
        resourceId = await _upload(
          resourceName,
          parent,
          data,
          mime: 'application/pdf',
        );
      } else {
        resourceId = matches.first['id'] as String;
        if (sha256.convert(await _download(resourceId)) != sha256.convert(data))
          throw const FormatException('Existing PDF failed verification');
      }
      mapping[pdf.reference] = resourceId;
    }
    final encodedMapping = Uint8List.fromList(utf8.encode(jsonEncode(mapping)));
    final manifestName =
        '.xournalpp-map-${sha256.convert(encodedMapping)}.json';
    final matches = children
        .where((child) => child['name'] == manifestName)
        .toList();
    final manifestId = matches.isEmpty
        ? await _upload(
            manifestName,
            parent,
            encodedMapping,
            mime: 'application/json',
          )
        : matches.first['id'] as String;
    if (matches.isNotEmpty &&
        sha256.convert(await _download(manifestId)) !=
            sha256.convert(encodedMapping))
      throw const FormatException('Existing PDF mapping failed verification');
    final xml = XmlDocument.parse(
      utf8.decode(const GZipDecoder().decodeBytes(bytes)),
    );
    xml.rootElement.setAttribute(_manifestAttribute, manifestId);
    final updated = Uint8List.fromList(
      const GZipEncoder().encode(utf8.encode(xml.toXmlString())),
    );
    final fileId = await _upload(
      filename,
      parent,
      updated,
      existingId: existing?.id,
    );
    _manifests[fileId] = mapping;
    return StoredNotebook(backendId: id, id: fileId, name: name);
  }

  @override
  Future<Uint8List> readNotebook(StoredNotebook notebook) async {
    if (notebook.backendId != id) throw ArgumentError('Wrong storage backend');
    final bytes = await _download(notebook.id);
    final xml = XmlDocument.parse(
      utf8.decode(const GZipDecoder().decodeBytes(bytes)),
    );
    final manifestId = xml.rootElement.getAttribute(_manifestAttribute);
    _manifests[notebook.id] = manifestId == null
        ? {}
        : (jsonDecode(utf8.decode(await _download(manifestId))) as Map).map(
            (key, value) => MapEntry(key as String, value as String),
          );
    return bytes;
  }

  @override
  Future<Uint8List> readPdf(StoredNotebook notebook, String reference) async {
    if (notebook.backendId != id) throw ArgumentError('Wrong storage backend');
    if (!_manifests.containsKey(notebook.id)) await readNotebook(notebook);
    final fileId = _manifests[notebook.id]?[reference];
    if (fileId == null) throw StateError('Background PDF is unavailable');
    return _download(fileId);
  }

  @override
  Future<void> forget(StoredNotebook notebook) async =>
      throw UnsupportedError('Remote notebooks cannot be forgotten');
}

class GoogleDriveFolder {
  const GoogleDriveFolder({required this.id, required this.name});
  final String id;
  final String name;
}

class GoogleDriveFolderListing {
  const GoogleDriveFolderListing({
    required this.folders,
    required this.notebooks,
  });
  final List<GoogleDriveFolder> folders;
  final List<StoredNotebook> notebooks;
}

class GoogleDriveException implements Exception {
  const GoogleDriveException(this.statusCode);
  final int statusCode;
  @override
  String toString() => 'Google Drive request failed (HTTP $statusCode)';
}

class GoogleDriveNameConflict implements Exception {
  const GoogleDriveNameConflict(this.filename, this.fileId);
  final String filename;
  final String fileId;
}
