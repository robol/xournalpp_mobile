import 'GoogleDriveStorage.dart';
import 'NextcloudStorage.dart';
import 'NotebookStorage.dart';

/// Non-secret labels saved with recents so disconnected connections remain distinct.
String? recentProviderLabel(NotebookStorage? storage) {
  if (storage is NextcloudStorage) {
    final root = storage.folder.isEmpty ? '/' : '/${storage.folder.join('/')}';
    return 'Nextcloud · ${storage.credentials.username}@${storage.credentials.server.host} · $root';
  }
  if (storage is GoogleDriveStorage) {
    String suffix(String value) =>
        value.length > 8 ? '…${value.substring(value.length - 8)}' : value;
    final account = storage.displayEmail ?? suffix(storage.accountId);
    final names = storage.displayRootFolderNames;
    final root = names == null
        ? suffix(storage.folderId)
        : '/${names.join('/')}';
    return 'Google Drive · $account · $root';
  }
  return null;
}

/// Returns a display-only path. Drive folder IDs are intentionally never
/// substituted for unknown names.
String recentFolderPathFor(NotebookStorage storage, List<String> names) {
  final root = storage is NextcloudStorage
      ? storage.folder
      : storage is GoogleDriveStorage
      ? storage.displayRootFolderNames ?? const <String>[]
      : const <String>[];
  return '/${[...root, ...names].join('/')}';
}

/// Nextcloud notebook IDs contain actual path segments under the configured
/// root. Drive IDs are opaque and must not be guessed into folder names.
String? recentKnownFolderPath(
  NotebookStorage? storage,
  StoredNotebook? notebook,
) {
  if (storage is! NextcloudStorage ||
      notebook == null ||
      notebook.backendId != storage.id)
    return null;
  final parts = notebook.id.split('/');
  if (parts.isEmpty ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..'))
    return null;
  return recentFolderPathFor(storage, parts.sublist(0, parts.length - 1));
}

String recentNotebookFileName(String name) =>
    name.toLowerCase().endsWith('.xopp') ? name : '$name.xopp';

String? recentKnownFileName(
  NotebookStorage? storage,
  StoredNotebook? notebook,
) {
  if (storage is! NextcloudStorage ||
      notebook == null ||
      notebook.backendId != storage.id)
    return null;
  final parts = notebook.id.split('/');
  if (parts.isEmpty ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..'))
    return null;
  return parts.last;
}
