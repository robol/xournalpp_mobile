import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/src/globals.dart';

/// Uses the existing recent-file schema, ordered oldest to newest.
class RecentFiles {
  static final changes = ValueNotifier<int>(0);
  static Future<void>? _pending;

  static Future<void> forget(String path) => _enqueue(() async {
    final prefs = await SharedPreferences.getInstance();
    final files =
        jsonDecode(prefs.getString(PreferencesKeys.kRecentFiles) ?? '[]')
            as List;
    files.removeWhere((entry) => entry['path'] == path);
    if (!await prefs.setString(
      PreferencesKeys.kRecentFiles,
      jsonEncode(files),
    )) {
      throw StateError('Could not update recent documents.');
    }
    changes.value++;
  });

  static Future<void> remember({
    required String path,
    required String name,
    Uint8List? preview,
    required int currentPage,
    DateTime? modified,
  }) {
    // Opening and saving can overlap. Serialize their read/modify/write cycles.
    Future<void> write() async {
      final prefs = await SharedPreferences.getInstance();
      final files =
          (jsonDecode(prefs.getString(PreferencesKeys.kRecentFiles) ?? '[]')
                  as List)
              .map((entry) => Map<String, dynamic>.from(entry as Map))
              .toList();
      final previous = files.where((entry) => entry['path'] == path).lastOrNull;
      files.removeWhere((entry) => entry['path'] == path);
      files.add({
        ...?previous,
        'name': name,
        'path': path,
        if (preview != null) 'preview': base64Encode(preview),
        if (modified != null) 'modified': modified.toIso8601String(),
        'currentPage': currentPage,
      });
      if (!await prefs.setString(
        PreferencesKeys.kRecentFiles,
        jsonEncode(files),
      )) {
        throw StateError('Could not update recent documents.');
      }
      changes.value++;
    }

    return _enqueue(write);
  }

  static Future<void> _enqueue(Future<void> Function() write) {
    final update =
        _pending?.then((_) => write(), onError: (Object _) => write()) ??
        write();
    _pending = update;
    void clearPending() {
      if (identical(_pending, update)) _pending = null;
    }

    update.then((_) => clearPending(), onError: (Object _) => clearPending());
    return update;
  }
}
