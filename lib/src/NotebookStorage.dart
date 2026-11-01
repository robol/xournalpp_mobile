import 'dart:convert';
import 'dart:math';
import 'conditional/file_storage/file_storage_stub.dart'
    if (dart.library.io) 'conditional/file_storage/file_storage_io.dart'
    as disk;
import 'package:crypto/crypto.dart';
import 'conditional/internal_storage/internal_storage_stub.dart'
    if (dart.library.io) 'conditional/internal_storage/internal_storage_io.dart'
    as internal_disk;

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
/// A digest of the exact remote notebook bytes read or successfully saved.
abstract interface class NotebookVersionBaseline {
  String? sourceDigest(StoredNotebook notebook);
  Future<bool> restoreSourceDigest(StoredNotebook notebook, String expected);
}

abstract interface class NotebookStorage {
  String get id;

  /// Optional bundled asset identifying this provider.
  String? get iconAsset;
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

/// Optional capabilities: providers without these remain readable/saveable.
abstract interface class NotebookDeletion {
  bool canDelete(StoredNotebook notebook);
  Future<void> delete(StoredNotebook notebook);
}

/// Folder IDs are opaque and owned by the provider that returned them.
class NotebookFolder {
  const NotebookFolder(this.backendId, this.id);
  final String backendId;
  final String id;
}

abstract interface class NotebookTransfer {
  Future<NotebookFolder?> parentOf(StoredNotebook notebook);
  Future<bool> containsNotebook(NotebookFolder folder, StoredNotebook notebook);

  /// Must create a distinct notebook without replacing an existing item.
  Future<StoredNotebook?> createInFolder({
    required NotebookFolder folder,
    required String name,
    required Uint8List bytes,
    required List<NotebookPdfResource> pdfs,
  });
}

void validateNotebookName(String name) {
  if (name.trim().isEmpty ||
      name == '.' ||
      name == '..' ||
      name.contains(RegExp(r'[/\\\x00-\x1f]'))) {
    throw ArgumentError('Invalid notebook name');
  }
}

class LocalNotebookStorage
    implements NotebookStorage, NotebookDeletion, NotebookTransfer {
  @override
  bool canDelete(StoredNotebook notebook) =>
      !kIsWeb && notebook.backendId == id && disk.canDeleteFile(notebook.id);
  @override
  Future<void> delete(StoredNotebook notebook) async {
    if (!canDelete(notebook)) throw UnsupportedError("Deletion unavailable");
    await disk.deleteFile(notebook.id);
    try {
      await forget(notebook);
    } catch (error) {
      debugPrint('Could not remove deleted notebook from saved list: $error');
    }
  }

  @override
  Future<NotebookFolder?> parentOf(StoredNotebook notebook) async {
    if (notebook.backendId != id) throw ArgumentError("Wrong storage backend");
    final folder = await disk.parentFolder(notebook.id);
    return folder == null ? null : NotebookFolder(id, folder);
  }

  @override
  Future<StoredNotebook?> createInFolder({
    required NotebookFolder folder,
    required String name,
    required Uint8List bytes,
    required List<NotebookPdfResource> pdfs,
  }) async {
    if (folder.backendId != id || kIsWeb)
      throw ArgumentError("Wrong storage backend");
    validateNotebookName(name);
    final path = await disk.createNotebook(
      folder.id,
      name.toLowerCase().endsWith(".xopp") ? name : "$name.xopp",
      bytes,
    );
    final result = StoredNotebook(backendId: id, id: path, name: name);
    await _update((entries) => entries.add(result));
    return result;
  }

  @override
  Future<bool> containsNotebook(
    NotebookFolder folder,
    StoredNotebook notebook,
  ) async {
    if (folder.backendId != id || notebook.backendId != id) return false;
    return disk.notebookInFolder(folder.id, notebook.id);
  }

  static const _key = 'localSavedNotebooks';
  static final changes = ValueNotifier<int>(0);
  static Future<void>? _pending;
  @override
  String get id => 'local';
  @override
  String? get iconAsset => 'assets/storage/local.png';

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

class InternalNameConflict implements Exception {
  InternalNameConflict(this.notebook);
  final StoredNotebook notebook;
}

/// The provider's remote version changed after the notebook was opened.
class NotebookEditConflict implements Exception {
  const NotebookEditConflict(this.notebookId);
  final String notebookId;
  @override
  String toString() =>
      'The notebook changed in storage. Save a separate copy to protect both versions.';
}

/// App-private notebooks. A small manifest atomically publishes immutable blobs.
class InternalNotebookStorage
    implements NotebookStorage, NotebookDeletion, NotebookTransfer {
  @override
  bool canDelete(StoredNotebook notebook) =>
      !kIsWeb && notebook.backendId == id;
  @override
  Future<NotebookFolder?> parentOf(StoredNotebook notebook) async {
    if (notebook.backendId != id) throw ArgumentError('Wrong storage backend');
    return NotebookFolder(id, '');
  }

  @override
  Future<StoredNotebook?> createInFolder({
    required NotebookFolder folder,
    required String name,
    required Uint8List bytes,
    required List<NotebookPdfResource> pdfs,
  }) {
    if (folder.backendId != id || folder.id != '')
      throw ArgumentError('Wrong folder');
    validateNotebookName(name);
    return save(bytes: bytes, name: name, pdfs: pdfs);
  }

  @override
  Future<bool> containsNotebook(
    NotebookFolder folder,
    StoredNotebook notebook,
  ) async =>
      folder.backendId == id && folder.id == '' && notebook.backendId == id;

  static final changes = ValueNotifier<int>(0);
  static Future<void> _pending = Future.value();
  @visibleForTesting
  static void resetForTesting() => _pending = Future.value();
  @override
  String get id => 'internal';
  @override
  String? get iconAsset => null;

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final operation = _pending.then(
      (_) => internal_disk.withInternalLock(action),
    );
    _pending = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  String _newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String _digest(Uint8List bytes) => sha256.convert(bytes).toString();
  Future<String> _hash(Uint8List bytes) => bytes.length < 1024 * 1024
      ? Future.value(_digest(bytes))
      : compute(_digest, bytes, debugLabel: 'hash internal notebook');
  Future<String> _writeBlob(Uint8List bytes) async {
    final key = '${await _hash(bytes)}.blob';
    try {
      final existing = await internal_disk.readInternalFile(key);
      if ('${await _hash(existing)}.blob' == key) return key;
    } catch (_) {
      /* Missing or unreadable blobs must be written afresh. */
    }
    await internal_disk.writeInternalFile(key, bytes);
    return key;
  }

  Future<Uint8List> _readBlob(Object? value) async {
    if (value is! String || !RegExp(r'^[a-f0-9]{64}\.blob$').hasMatch(value)) {
      throw const FormatException('Invalid internal resource');
    }
    final data = await internal_disk.readInternalFile(value);
    if ('${await _hash(data)}.blob' != value)
      throw const FormatException('Damaged internal resource');
    return data;
  }

  Future<Map<String, dynamic>> _metadata(String notebookId) async {
    final data =
        jsonDecode(
              utf8.decode(
                await internal_disk.readInternalFile('$notebookId.json'),
              ),
            )
            as Map<String, dynamic>;
    final hashPattern = RegExp(r'^[a-f0-9]{64}\.blob$');
    bool validBlob(Object? value) =>
        value is String && hashPattern.hasMatch(value);
    if (data['version'] != 1 ||
        data['name'] is! String ||
        !validBlob(data['notebook']) ||
        data['pdfs'] is! Map ||
        !(data['pdfs'] as Map).entries.every(
          (entry) => entry.key is String && validBlob(entry.value),
        )) {
      throw const FormatException('Invalid internal notebook manifest');
    }
    return data;
  }

  Future<List<StoredNotebook>> _list() async {
    final result = <StoredNotebook>[];
    for (final notebookId in await internal_disk.listInternalFiles()) {
      try {
        final metadata = await _metadata(notebookId);
        result.add(
          StoredNotebook(
            backendId: id,
            id: notebookId,
            name: metadata['name'] as String,
            modified: DateTime.tryParse(metadata['modified'] as String? ?? ''),
          ),
        );
      } catch (_) {
        /* Keep unreadable files intact. */
      }
    }
    result.sort(
      (a, b) =>
          (a.modified ?? DateTime(0)).compareTo(b.modified ?? DateTime(0)),
    );
    return result;
  }

  Future<void> _collect() async {
    final used = <String>{};
    for (final notebookId in await internal_disk.listInternalFiles()) {
      try {
        final metadata = await _metadata(notebookId);
        used.add(metadata['notebook'] as String);
        used.addAll((metadata['pdfs'] as Map).values.cast<String>());
      } catch (_) {
        return;
      } // Never discard data referenced by an unreadable manifest.
    }
    for (final blob in await internal_disk.listInternalBlobs()) {
      if (!used.contains(blob)) await internal_disk.deleteInternalFile(blob);
    }
  }

  Future<void> _collectBestEffort() async {
    try {
      await _collect();
    } catch (error) {
      debugPrint('Could not clean internal storage: $error');
    }
  }

  @override
  Future<List<StoredNotebook>> list() => _enqueue(_list);
  Future<void> _checkDestination(String name, StoredNotebook? existing) async {
    if (existing != null && existing.backendId != id)
      throw ArgumentError('Wrong storage backend');
    final notebooks = await _list();
    final conflict = notebooks
        .where((item) => item.name == name && item.id != existing?.id)
        .firstOrNull;
    if (conflict != null) throw InternalNameConflict(conflict);
    if (existing != null && !notebooks.any((item) => item.id == existing.id)) {
      throw StateError('Internal notebook is unavailable');
    }
  }

  @override
  Future<StoredNotebook?> save({
    required Uint8List bytes,
    required String name,
    StoredNotebook? existing,
    required List<NotebookPdfResource> pdfs,
  }) async {
    // PDF callbacks may read this provider; do not invoke them while holding its lock.
    await _enqueue(() => _checkDestination(name, existing));
    final pdfBytes = <String, Uint8List>{};
    for (final pdf in pdfs) {
      if (!pdfBytes.containsKey(pdf.reference))
        pdfBytes[pdf.reference] = await pdf.read();
    }
    return _enqueue(() async {
      // Another save can change the destination while PDF reads are in flight.
      await _checkDestination(name, existing);
      var notebookId = existing?.id;
      if (notebookId == null) {
        final existingIds = await internal_disk.listInternalFiles();
        do {
          notebookId = _newId();
        } while (existingIds.contains(notebookId));
      }
      try {
        final notebookBlob = await _writeBlob(bytes);
        final resources = <String, String>{};
        for (final pdf in pdfBytes.entries) {
          resources[pdf.key] = await _writeBlob(pdf.value);
        }
        final modified = DateTime.now().toUtc();
        final metadata = utf8.encode(
          jsonEncode({
            'version': 1,
            'name': name,
            'modified': modified.toIso8601String(),
            'notebook': notebookBlob,
            'pdfs': resources,
          }),
        );
        await internal_disk.writeInternalFile(
          '$notebookId.json',
          Uint8List.fromList(metadata),
        );
        changes.value++;
        await _collectBestEffort();
        return StoredNotebook(
          backendId: id,
          id: notebookId,
          name: name,
          modified: modified,
        );
      } catch (_) {
        await _collectBestEffort();
        rethrow;
      }
    });
  }

  @override
  Future<Uint8List> readNotebook(StoredNotebook notebook) => _enqueue(() async {
    if (notebook.backendId != id) throw ArgumentError('Wrong storage backend');
    return _readBlob((await _metadata(notebook.id))['notebook']);
  });
  @override
  Future<Uint8List> readPdf(
    StoredNotebook notebook,
    String reference,
  ) => _enqueue(() async {
    if (notebook.backendId != id) throw ArgumentError('Wrong storage backend');
    final resource = ((await _metadata(notebook.id))['pdfs'] as Map)[reference];
    if (resource == null) throw StateError('Background PDF is unavailable');
    return _readBlob(resource);
  });

  /// Forget only removes a recent entry; deleting Internal content is explicit.
  @override
  Future<void> forget(StoredNotebook notebook) async {}
  @override
  Future<void> delete(StoredNotebook notebook) => _enqueue(() async {
    if (notebook.backendId != id) throw ArgumentError('Wrong storage backend');
    await internal_disk.deleteInternalFile('${notebook.id}.json');
    changes.value++;
    await _collectBestEffort();
  });
}

final internalNotebookStorage = InternalNotebookStorage();
final localNotebookStorage = LocalNotebookStorage();

/// Providers offered when choosing where to save a notebook.
final List<NotebookStorage> notebookStorageBackends = [
  if (!kIsWeb) internalNotebookStorage,
  localNotebookStorage,
];

NotebookStorage get defaultNotebookStorage =>
    kIsWeb ? localNotebookStorage : internalNotebookStorage;

/// Keeps icons for known providers visible even when their account is offline.
String? storageIconForBackendId(String? id) {
  if (id == null || id == 'local') return localNotebookStorage.iconAsset;
  if (id.startsWith('nextcloud:')) return 'assets/storage/nextcloud.png';
  if (id.startsWith('gdrive:')) return 'assets/storage/google-drive.png';
  return notebookStorageBackends
      .where((backend) => backend.id == id)
      .firstOrNull
      ?.iconAsset;
}
