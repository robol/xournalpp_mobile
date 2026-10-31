import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'NotebookStorage.dart';
import 'conditional/notebook_cache/cache_stub.dart'
    if (dart.library.io) 'conditional/notebook_cache/cache_io.dart'
    as disk;

String _cacheDigest(Uint8List bytes) => sha256.convert(bytes).toString();
Future<String> _digest(Uint8List bytes) => bytes.length >= 1024 * 1024
    ? compute(_cacheDigest, bytes, debugLabel: 'hash notebook cache')
    : Future.value(_cacheDigest(bytes));

abstract interface class NotebookCachePersistence {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
  Future<List<String>> list();
  Future<void> delete(String key);
}

class FileNotebookCachePersistence implements NotebookCachePersistence {
  @override
  Future<Uint8List?> read(String key) => disk.readCacheFile(key);
  @override
  Future<void> write(String key, Uint8List bytes) =>
      disk.writeCacheFile(key, bytes);
  @override
  Future<List<String>> list() => disk.cacheFiles();
  @override
  Future<void> delete(String key) => disk.deleteCacheFile(key);
}

class CachedNotebook {
  const CachedNotebook({
    required this.notebook,
    required this.bytes,
    required this.pdfs,
    required this.missingPdfs,
    required this.checkpoint,
    required this.dirty,
    required this.page,
    this.confirmedAt,
    this.resourceSession,
  });
  final StoredNotebook notebook;
  final Uint8List bytes;
  final Map<String, Uint8List> pdfs;
  final List<String> missingPdfs;
  final DateTime checkpoint;
  final DateTime? confirmedAt;
  final String? resourceSession;
  final bool dirty;
  final int page;
}

/// The manifest is published only after all content-addressed blobs are durable.
/// All operations are ordered; clear invalidates pending work before it runs.
class NotebookCache {
  NotebookCache({NotebookCachePersistence? persistence})
    : persistence = persistence ?? FileNotebookCachePersistence();
  static final _instance = NotebookCache();
  @visibleForTesting
  static NotebookCache? debugInstance;
  static NotebookCache get instance => debugInstance ?? _instance;
  final NotebookCachePersistence persistence;
  final changes = ValueNotifier<int>(0);
  Future<void> _pending = Future.value();
  int _generation = 0;
  int get generation => _generation;
  static const _setting = 'notebookCache.enabled.v1';
  Future<bool> get enabled async =>
      !kIsWeb &&
      ((await SharedPreferences.getInstance()).getBool(_setting) ?? true);
  Future<void> setEnabled(bool value) async {
    if (!await (await SharedPreferences.getInstance()).setBool(
      _setting,
      value,
    )) {
      throw StateError('Could not save cache setting');
    }
    _generation++;
    changes.value++;
  }

  String _key(StoredNotebook n) =>
      '${sha256.convert(utf8.encode(jsonEncode([n.backendId, n.id])))}.json';
  Future<T> _queue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Map<String, dynamic>> _manifest(StoredNotebook n) async {
    final bytes = await persistence.read(_key(n));
    if (bytes == null) return {};
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (data['version'] != 1 ||
        data['backend'] != n.backendId ||
        data['id'] != n.id) {
      throw const FormatException('Invalid cache manifest');
    }
    return data;
  }

  Future<String> _blob(Uint8List bytes) async {
    final digest = await _digest(bytes);
    final key = '$digest.blob';
    final existing = await persistence.read(key);
    if (existing == null || await _digest(existing) != digest) {
      await persistence.write(key, bytes);
    }
    return key;
  }

  Future<Uint8List> _readBlob(String key) async {
    if (!RegExp(r'^[a-f0-9]{64}\.blob$').hasMatch(key))
      throw const FormatException('Invalid cache blob');
    final bytes = await persistence.read(key);
    if (bytes == null || '${await _digest(bytes)}.blob' != key)
      throw const FormatException('Damaged cache blob');
    return bytes;
  }

  Future<void> record({
    required StoredNotebook notebook,
    required Uint8List bytes,
    required Map<String, Uint8List> pdfs,
    required List<String> references,
    required bool dirty,
    int page = 0,
    int? expectedGeneration,
    String? resourceSession,
  }) {
    final generation = expectedGeneration ?? _generation;
    return _queue(() async {
      if (generation != _generation || !await enabled) return;
      final manifest = await _manifest(notebook);
      final previous = (manifest['working'] ?? manifest['baseline']) as Map?;
      final resources = <String, String>{};
      for (final ref in references) {
        final data = pdfs[ref];
        if (data != null) {
          resources[ref] = await _blob(data);
        } else if (dirty &&
            previous?['resourceSession'] == resourceSession &&
            previous?['pdfs']?[ref] is String) {
          resources[ref] = previous!['pdfs'][ref] as String;
        }
      }
      final snapshot = {
        'bytes': await _blob(bytes),
        'resourceSession': resourceSession,
        'pdfs': resources,
        'missing': references
            .where((ref) => !resources.containsKey(ref))
            .toList(),
        'checkpoint': DateTime.now().toUtc().toIso8601String(),
        'confirmed': dirty
            ? (previous?['confirmed'])
            : DateTime.now().toUtc().toIso8601String(),
        'dirty': dirty,
        'page': page,
        'name': notebook.name,
      };
      manifest.addAll({
        'version': 1,
        'backend': notebook.backendId,
        'id': notebook.id,
      });
      if (dirty) {
        manifest['working'] = snapshot;
      } else {
        manifest['baseline'] = snapshot;
        // A successful provider read must not destroy unsaved local work.
      }
      if (generation != _generation) return;
      await persistence.write(
        _key(notebook),
        Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
      );
      await _collect();
      changes.value++;
    });
  }

  /// Enrich only snapshots belonging to the opening session that fetched the PDF.
  /// Never replace notebook bytes or attach an older session's PDF to a new open.
  Future<void> addPdfs(
    StoredNotebook notebook,
    Map<String, Uint8List> pdfs, {
    required int expectedGeneration,
    required String resourceSession,
  }) => _queue(() async {
    if (expectedGeneration != _generation || !await enabled) return;
    final manifest = await _manifest(notebook);
    var changed = false;
    for (final name in ['baseline', 'working']) {
      final snapshot = manifest[name] as Map?;
      if (snapshot == null || snapshot['resourceSession'] != resourceSession)
        continue;
      final missing = List<String>.from(snapshot['missing'] as List);
      for (final ref in missing.toList()) {
        final bytes = pdfs[ref];
        if (bytes == null) continue;
        (snapshot['pdfs'] as Map)[ref] = await _blob(bytes);
        missing.remove(ref);
        changed = true;
      }
      snapshot['missing'] = missing;
    }
    if (!changed || expectedGeneration != _generation) return;
    await persistence.write(
      _key(notebook),
      Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
    );
    await _collect();
    changes.value++;
  });

  Future<void> discardWorking(StoredNotebook notebook) => _queue(() async {
    if (!await enabled) return;
    final manifest = await _manifest(notebook);
    if (manifest.isEmpty) return;
    manifest.remove('working');
    await persistence.write(
      _key(notebook),
      Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
    );
    await _collect();
    changes.value++;
  });
  Future<CachedNotebook?> load(StoredNotebook notebook) => _queue(() async {
    if (!await enabled) return null;
    final manifest = await _manifest(notebook);
    final data = (manifest['working'] ?? manifest['baseline']) as Map?;
    if (data == null) return null;
    final pdfs = <String, Uint8List>{};
    final missing = List<String>.from(data['missing'] as List);
    for (final entry in (data['pdfs'] as Map).entries) {
      try {
        pdfs[entry.key as String] = await _readBlob(entry.value as String);
      } catch (_) {
        missing.add(entry.key as String);
      }
    }
    return CachedNotebook(
      notebook: StoredNotebook(
        backendId: notebook.backendId,
        id: notebook.id,
        name: data['name'] as String,
      ),
      bytes: await _readBlob(data['bytes'] as String),
      pdfs: pdfs,
      missingPdfs: missing,
      checkpoint: DateTime.parse(data['checkpoint'] as String),
      confirmedAt: DateTime.tryParse(data['confirmed'] as String? ?? ''),
      resourceSession: data['resourceSession'] as String?,
      dirty: data['dirty'] as bool,
      page: data['page'] as int,
    );
  });
  Future<List<StoredNotebook>> list({String? backendId}) => _queue(() async {
    if (!await enabled) return [];
    final result = <StoredNotebook>[];
    for (final key in await persistence.list()) {
      if (!key.endsWith('.json')) continue;
      try {
        final data =
            jsonDecode(utf8.decode((await persistence.read(key))!)) as Map;
        if (data['version'] != 1 ||
            (backendId != null && data['backend'] != backendId))
          continue;
        final snapshot = data['working'] ?? data['baseline'];
        if (snapshot == null) continue;
        result.add(
          StoredNotebook(
            backendId: data['backend'] as String,
            id: data['id'] as String,
            name: snapshot['name'] as String,
            modified: DateTime.parse(snapshot['checkpoint'] as String),
          ),
        );
      } catch (_) {
        /* A damaged entry must not hide the other entries. */
      }
    }
    result.sort((a, b) => b.modified!.compareTo(a.modified!));
    return result;
  });
  Future<int> size() => _queue(() async {
    var size = 0;
    for (final key in await persistence.list()) {
      size += (await persistence.read(key))?.length ?? 0;
    }
    return size;
  });
  Future<void> clear() {
    _generation++;
    return _queue(() async {
      for (final key in await persistence.list()) {
        await persistence.delete(key);
      }
      changes.value++;
    });
  }

  Future<void> _collect() async {
    final used = <String>{};
    for (final key in await persistence.list()) {
      if (!key.endsWith('.json')) continue;
      try {
        final manifest =
            jsonDecode(utf8.decode((await persistence.read(key))!)) as Map;
        if (manifest['version'] != 1) return;
        for (final name in ['baseline', 'working']) {
          final snapshot = manifest[name] as Map?;
          if (snapshot != null) {
            used.add(snapshot['bytes'] as String);
            used.addAll((snapshot['pdfs'] as Map).values.cast<String>());
          }
        }
      } catch (_) {
        return;
      } // Preserve data when a manifest cannot be understood.
    }
    for (final key in await persistence.list()) {
      if (key.endsWith('.blob') && !used.contains(key))
        await persistence.delete(key);
    }
  }
}
