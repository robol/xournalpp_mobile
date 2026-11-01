import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:xournalpp/src/NotebookTransfer.dart';
import 'package:xournalpp/src/NextcloudStorage.dart';
import 'package:xournalpp/src/GoogleDriveStorage.dart';
import 'package:xournalpp/src/RecentFiles.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/conditional/file_storage/file_storage_stub.dart'
    if (dart.library.io) 'package:xournalpp/src/conditional/file_storage/file_storage_io.dart'
    as disk;
import 'CloudSaveFolderDialog.dart';
import 'LoadingFileDialog.dart';

bool canTransferNotebook(NotebookStorage? storage, StoredNotebook? notebook) =>
    !kIsWeb &&
    storage is NotebookTransfer &&
    storage is NotebookDeletion &&
    notebook != null &&
    (storage as NotebookDeletion).canDelete(notebook);

Future<bool> deleteNotebook(
  BuildContext context,
  NotebookStorage storage,
  StoredNotebook notebook,
) async {
  if (storage is! NotebookDeletion ||
      !(storage as NotebookDeletion).canDelete(notebook) ||
      kIsWeb)
    return false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(S.of(context).internalDelete),
      content: Text('${S.of(context).deleteNotebookConfirm}\n${notebook.name}'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(S.of(context).cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(S.of(context).internalDelete),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  await runWithLoadingFileDialog(
    context,
    () => NotebookTransferCoordinator().delete(storage, notebook),
  );
  return true;
}

Future<NotebookTransferResult?> transferNotebook(
  BuildContext context,
  XppFile file, {
  bool rename = false,
}) async {
  final source = file.storage;
  final original = file.storageNotebook;
  if (!canTransferNotebook(source, original) ||
      (file.openedFromCache || file.requiresSeparateCopy))
    return null;
  var destination = source!;
  if (!rename) {
    final selected = await showDialog<NotebookStorage>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(S.of(context).moveTo),
        children: notebookStorageBackends.whereType<NotebookTransfer>().map((
          backend,
        ) {
          final storage = backend as NotebookStorage;
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, storage),
            child: Text(
              storage is InternalNotebookStorage
                  ? S.of(context).internalStorage
                  : storage is LocalNotebookStorage
                  ? S.of(context).localStorage
                  : storage is NextcloudStorage
                  ? 'Nextcloud'
                  : storage is GoogleDriveStorage
                  ? 'Google Drive'
                  : storage.id,
            ),
          );
        }).toList(),
      ),
    );
    if (selected == null || !context.mounted) return null;
    destination = selected;
  }
  final backgrounds = <String, XppBackgroundPdf>{};
  for (final page in file.pages!) {
    final bg = page.background;
    if (bg is XppBackgroundPdf && bg.filename != null)
      backgrounds[bg.filename!] = bg;
  }
  if (destination is LocalNotebookStorage &&
      source is! LocalNotebookStorage &&
      backgrounds.isNotEmpty) {
    if (context.mounted)
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(S.of(context).moveTo),
          content: Text(S.of(context).movePdfUnsafe),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(S.of(context).cancel),
            ),
          ],
        ),
      );
    return null;
  }
  if (!context.mounted) return null;
  final controller = TextEditingController(text: original!.name);
  String? name;
  final form = GlobalKey<FormState>();
  try {
    name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          rename ? S.of(context).renameNotebook : S.of(context).moveTo,
        ),
        content: Form(
          key: form,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) {
              try {
                validateNotebookName(value?.trim() ?? '');
                return null;
              } catch (_) {
                return S.of(context).invalidNotebookName;
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.of(context).cancel),
          ),
          TextButton(
            onPressed: () {
              if (form.currentState!.validate())
                Navigator.pop(context, controller.text.trim());
            },
            child: Text(S.of(context).save),
          ),
        ],
      ),
    );
  } finally {
    // Dialog exit transitions may still use the controller this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }
  if (name == null || !context.mounted || (rename && name == original.name))
    return null;
  NotebookFolder? folder;
  if (rename) {
    if (source is LocalNotebookStorage &&
        original.id.startsWith('content://')) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(S.of(context).renameFolderAccess),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(S.of(context).save),
            ),
          ],
        ),
      );
    }
    folder = await (source as NotebookTransfer).parentOf(original);
  } else if (destination is InternalNotebookStorage) {
    folder = NotebookFolder(destination.id, '');
  } else if (destination is LocalNotebookStorage) {
    final path = defaultTargetPlatform == TargetPlatform.android
        ? await disk.chooseNotebookFolder()
        : await FilePicker.getDirectoryPath();
    if (path != null) folder = NotebookFolder(destination.id, path);
  } else {
    final path = await showDialog<List<String>>(
      context: context,
      builder: (_) => CloudSaveFolderDialog(storage: destination),
    );
    if (path != null)
      folder = NotebookFolder(
        destination.id,
        destination is NextcloudStorage
            ? jsonEncode(path)
            : path.isEmpty
            ? (destination as GoogleDriveStorage).folderId
            : path.last,
      );
  }
  if (folder == null || !context.mounted) return null;
  final bytes = await file.toUint8ListAsync();
  final result = await runWithLoadingFileDialog(
    context,
    () => NotebookTransferCoordinator().move(
      source: source,
      original: original,
      destination: destination,
      folder: folder!,
      name: name!,
      bytes: bytes,
      cachedOrigin: file.openedFromCache,
      pdfs: backgrounds.entries
          .map(
            (entry) => NotebookPdfResource(
              reference: entry.key,
              read: () async =>
                  (await file.readBackgroundPdf(context, entry.value)).bytes,
            ),
          )
          .toList(),
    ),
  );
  if (result.notebook != null) {
    file.storage = destination;
    file.storageNotebook = result.notebook;
    file.captureCloudSourceDigest();
    file.title = result.notebook!.name;
    file.openedFromCache = false;
  }
  return result;
}

/// The caller adopts a completed copy before doing fallible metadata/UI work.
Future<void> rememberTransferredNotebook(XppFile file, {int page = 0}) async {
  final notebook = file.storageNotebook!;
  await RecentFiles.remember(
    path: notebook.id,
    name: notebook.name,
    currentPage: page,
    backendId: notebook.backendId,
    preview: file.previewImage,
    modified: DateTime.now(),
  );
  await file.cacheSnapshot(
    await file.toUint8ListAsync(),
    dirty: false,
    saved: true,
    page: page,
  );
}

void showTransferResult(
  BuildContext context,
  NotebookTransferResult result,
  NotebookStorage source,
  StoredNotebook original,
) {
  if (!context.mounted || result.status == NotebookTransferStatus.cancelled)
    return;
  final partial = result.status == NotebookTransferStatus.copiedSourceRetained;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        partial
            ? S.of(context).moveCopyRetained
            : result.status == NotebookTransferStatus.moved
            ? S.of(context).notebookMoved
            : '${S.of(context).moveFailed} ${result.error}',
      ),
      duration: partial
          ? const Duration(seconds: 20)
          : const Duration(seconds: 6),
      action: !partial
          ? null
          : SnackBarAction(
              label: S.of(context).retrySourceDelete,
              onPressed: () async {
                try {
                  await NotebookTransferCoordinator().retrySourceDeletion(
                    source,
                    original,
                    result.notebook!,
                    sourceDigest: result.sourceDigest!,
                  );
                  if (context.mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(S.of(context).notebookMoved)),
                    );
                } catch (error) {
                  if (context.mounted)
                    showTransferResult(
                      context,
                      NotebookTransferResult(
                        NotebookTransferStatus.copiedSourceRetained,
                        notebook: result.notebook,
                        error: error,
                        sourceDigest: result.sourceDigest,
                      ),
                      source,
                      original,
                    );
                }
              },
            ),
    ),
  );
}
