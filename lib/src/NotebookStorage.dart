import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/src/XppPickedFile.dart';

/// An opaque identifier is meaningful only to its originating backend.
class StoredNotebook {
  const StoredNotebook({
    required this.backendId,
    required this.id,
    required this.name,
    this.modified,
  });
  final String backendId;
  final String id;
  final String name;
  final DateTime? modified;
}

/// A PDF reference in the notebook and a way to obtain its original bytes.
class NotebookPdfResource {
  const NotebookPdfResource({required this.reference, required this.read});
  final String reference;
  final Future<Uint8List> Function() read;
}

/// Implementations must finish saving required resources before returning success.
/// A non-local backend stores each PDF under its original [NotebookPdfResource.reference],
/// and must resolve that reference through [readPdf] after reopening the notebook.
/// The local backend retains the original PDF references instead of copying them.
/// Null means the user cancelled destination selection; errors must be thrown.
abstract interface class NotebookStorage {
  String get id;
  Future<StoredNotebook?> save({
    required Uint8List bytes,
    required String name,
    StoredNotebook? existing,
    required List<NotebookPdfResource> pdfs,
  });
  Future<List<StoredNotebook>> list();
  Future<Uint8List> readNotebook(StoredNotebook notebook);
  Future<Uint8List> readPdf(StoredNotebook notebook, String reference);
  Future<void> forget(StoredNotebook notebook);
}

class LocalNotebookStorage implements NotebookStorage {
  static const _key = 'localSavedNotebooks';
  static final changes = ValueNotifier<int>(0);
  static Future<void>? _pending;
  @override
  String get id => 'local';

  @override
  Future<StoredNotebook?> save({
    required Uint8List bytes,
    required String name,
    StoredNotebook? existing,
    required List<NotebookPdfResource> pdfs,
  }) async {
    if (existing != null && existing.backendId != id)
      throw ArgumentError('Wrong storage backend');
    final file = XppPickedFile(
      bytes,
      fileName: '$name.xopp',
      fileExtension: 'xopp',
    );
    final path = existing == null
        ? await file.exportToStorage()
        : await file.saveToPath(path: existing.id);
    if (path == null) return null;
    final result = StoredNotebook(backendId: id, id: path, name: name);
    await _update((entries) {
      entries.removeWhere((e) => e.id == path);
      entries.add(result);
    });
    return result;
  }

  @override
  Future<List<StoredNotebook>> list() async {
    await _pending;
    final prefs = await SharedPreferences.getInstance();
    final entries = jsonDecode(prefs.getString(_key) ?? '[]') as List;
    return entries
        .map(
          (e) => StoredNotebook(
            backendId: id,
            id: e['id'] as String,
            name: e['name'] as String,
          ),
        )
        .toList();
  }

  Future<void> _update(void Function(List<StoredNotebook>) change) {
    Future<void> write() async {
      final prefs = await SharedPreferences.getInstance();
      final entries = (jsonDecode(prefs.getString(_key) ?? '[]') as List)
          .map(
            (e) => StoredNotebook(
              backendId: id,
              id: e['id'] as String,
              name: e['name'] as String,
            ),
          )
          .toList();
      change(entries);
      if (!await prefs.setString(
        _key,
        jsonEncode(entries.map((e) => {'id': e.id, 'name': e.name}).toList()),
      ))
        throw StateError('Could not update saved notebooks');
      changes.value++;
    }

    final operation =
        _pending?.then((_) => write(), onError: (Object _) => write()) ??
        write();
    _pending = operation;
    operation.then(
      (_) {
        if (identical(_pending, operation)) _pending = null;
      },
      onError: (Object _) {
        if (identical(_pending, operation)) _pending = null;
      },
    );
    return operation;
  }

  @override
  Future<void> forget(StoredNotebook notebook) =>
      _update((entries) => entries.removeWhere((e) => e.id == notebook.id));
  @override
  Future<Uint8List> readNotebook(StoredNotebook notebook) async =>
      (await XppPickedFile.fromInternalPath(path: notebook.id)).bytes;
  @override
  Future<Uint8List> readPdf(StoredNotebook notebook, String reference) async =>
      (await XppPickedFile.fromInternalPath(path: reference)).bytes;
}

final localNotebookStorage = LocalNotebookStorage();

/// Providers offered when choosing where to save a notebook.
final List<NotebookStorage> notebookStorageBackends = [localNotebookStorage];
