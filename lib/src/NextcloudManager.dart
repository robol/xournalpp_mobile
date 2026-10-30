import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/src/NextcloudConnection.dart';
import 'package:xournalpp/src/NextcloudStorage.dart';
import 'package:xournalpp/src/NotebookStorage.dart';

class NextcloudManager {
  static const _folderKey = 'nextcloud.folder.v1';
  static final changes = ValueNotifier<int>(0);
  static NextcloudStorage? get current =>
      notebookStorageBackends.whereType<NextcloudStorage>().firstOrNull;

  static Future<void> restore() async {
    if (kIsWeb || current != null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_folderKey);
    if (raw == null) return;
    final connection = NextcloudConnection();
    try {
      final credentials = await connection.loadCredentials();
      if (credentials == null || current != null) return;
      final config = jsonDecode(raw) as Map<String, dynamic>;
      if (config['server'] != credentials.server.toString() ||
          config['username'] != credentials.username) {
        throw StateError(
          'Nextcloud credentials do not match the configured folder',
        );
      }
      final folder = (config['folder'] as List).cast<String>();
      notebookStorageBackends.add(NextcloudStorage(credentials, folder));
      changes.value++;
    } finally {
      connection.close();
    }
  }

  static Future<void> configure(
    NextcloudCredentials credentials,
    List<String> folder,
  ) async {
    final connection = NextcloudConnection();
    try {
      final previous = await connection.loadCredentials();
      await connection.saveCredentials(credentials);
      final prefs = await SharedPreferences.getInstance();
      try {
        if (!await prefs.setString(
          _folderKey,
          jsonEncode({
            'server': credentials.server.toString(),
            'username': credentials.username,
            'folder': folder,
          }),
        )) {
          throw StateError('Could not save Nextcloud folder');
        }
      } catch (_) {
        if (previous == null) {
          await connection.clearCredentials();
        } else {
          await connection.saveCredentials(previous);
        }
        rethrow;
      }
      notebookStorageBackends.removeWhere(
        (backend) => backend is NextcloudStorage,
      );
      notebookStorageBackends.add(
        NextcloudStorage(credentials, List.unmodifiable(folder)),
      );
      changes.value++;
    } finally {
      connection.close();
    }
  }

  static Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_folderKey);
    final connection = NextcloudConnection();
    try {
      await connection.clearCredentials();
    } finally {
      connection.close();
    }
    notebookStorageBackends.removeWhere(
      (backend) => backend is NextcloudStorage,
    );
    changes.value++;
  }
}
