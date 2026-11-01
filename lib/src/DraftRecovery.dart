import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'NotebookStorage.dart';

import 'package:flutter/foundation.dart';

import 'conditional/draft_storage/draft_storage_stub.dart'
    if (dart.library.io) 'conditional/draft_storage/draft_storage_io.dart';

class RecoveryDraft {
  const RecoveryDraft({
    required this.id,
    required this.bytes,
    required this.page,
    this.title,
    this.originalPath,
    this.backendId,
    this.cachedOrigin = false,
    this.sourceDigest,
    this.safRecoveryKind,
  });

  final String id;
  final Uint8List bytes;
  final int page;
  final String? title;
  final String? originalPath;
  final String? backendId;
  final bool cachedOrigin;
  final String? sourceDigest;
  final String? safRecoveryKind;

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'bytes': base64Encode(bytes),
    'page': page,
    'title': title,
    'originalPath': originalPath,
    'backendId': backendId,
    'cachedOrigin': cachedOrigin,
    'sourceDigest': sourceDigest,
    'safRecoveryKind': safRecoveryKind,
  };

  static RecoveryDraft fromJson(Map<String, dynamic> data) {
    if (data['version'] != 1 ||
        data['id'] is! String ||
        data['bytes'] is! String) {
      throw const FormatException('Invalid recovery draft');
    }
    return RecoveryDraft(
      id: data['id'] as String,
      bytes: base64Decode(data['bytes'] as String),
      page: (data['page'] is int ? data['page'] as int : 0).clamp(
        0,
        0x7fffffff,
      ),
      title: data['title'] as String?,
      originalPath: data['originalPath'] as String?,
      backendId: data['backendId'] as String?,
      cachedOrigin: data['cachedOrigin'] == true,
      sourceDigest: data['sourceDigest'] as String?,
      safRecoveryKind: data['safRecoveryKind'] as String?,
    );
  }
}

/// Operations are serialized so an older checkpoint cannot replace a newer one.
class DraftRecovery {
  static Future<void> _pending = Future.value();
  static const _isolateThresholdBytes = 1024 * 1024;

  @visibleForTesting
  static void resetForTesting() => _pending = Future.value();

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';

  static String _encode(RecoveryDraft draft) => jsonEncode(draft.toJson());

  static Future<void> save(RecoveryDraft draft) => _enqueue(() async {
    // Large base64 and JSON conversions should not stall stylus input.
    final encoded = draft.bytes.length >= _isolateThresholdBytes
        ? await compute(_encode, draft, debugLabel: 'encode recovery draft')
        : _encode(draft);
    await writeDraft(draft.id, encoded);
  });

  /// Keep recoverable edits associated with a successfully moved original.
  /// Draft bytes and cached-origin status are preserved.
  static Future<void> relocate(
    StoredNotebook source,
    StoredNotebook destination,
  ) => _enqueue(() async {
    for (final record in await listDrafts()) {
      RecoveryDraft draft;
      try {
        draft = RecoveryDraft.fromJson(
          jsonDecode(record) as Map<String, dynamic>,
        );
      } catch (_) {
        continue;
      }
      if (draft.originalPath != source.id ||
          (draft.backendId ?? 'local') != source.backendId)
        continue;
      final moved = RecoveryDraft(
        id: draft.id,
        bytes: draft.bytes,
        page: draft.page,
        title: destination.name,
        originalPath: destination.id,
        backendId: destination.backendId,
        cachedOrigin: draft.cachedOrigin,
      );
      await writeDraft(moved.id, jsonEncode(moved.toJson()));
    }
  });

  static Future<void> remove(String id) => _enqueue(() => deleteDraft(id));

  static Future<List<RecoveryDraft>> list() async {
    final records = await listDrafts();
    final drafts = <RecoveryDraft>[];
    for (final record in records) {
      try {
        final draft = RecoveryDraft.fromJson(
          jsonDecode(record) as Map<String, dynamic>,
        );
        drafts.add(draft);
      } catch (_) {
        // Keep unrecognized or damaged files untouched for manual recovery.
      }
    }
    return drafts;
  }

  static Future<void> _enqueue(Future<void> Function() operation) {
    final result = _pending.then(
      (_) => operation(),
      onError: (_) => operation(),
    );
    _pending = result.then((_) {}, onError: (_) {});
    return result;
  }
}
