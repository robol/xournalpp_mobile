import 'dart:async';
import 'dart:convert';
import 'dart:math';

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
  });

  final String id;
  final Uint8List bytes;
  final int page;
  final String? title;
  final String? originalPath;

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'bytes': base64Encode(bytes),
    'page': page,
    'title': title,
    'originalPath': originalPath,
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
    );
  }
}

/// Operations are serialized so an older checkpoint cannot replace a newer one.
class DraftRecovery {
  static Future<void> _pending = Future.value();

  @visibleForTesting
  static void resetForTesting() => _pending = Future.value();

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';

  static Future<void> save(RecoveryDraft draft) =>
      _enqueue(() => writeDraft(draft.id, jsonEncode(draft.toJson())));

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
