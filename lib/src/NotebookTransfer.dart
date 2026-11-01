import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'NotebookStorage.dart';
import 'NotebookCache.dart';
import 'RecentFiles.dart';
import 'DraftRecovery.dart';

/// A successful copy is never rolled back when source deletion fails.
enum NotebookTransferStatus {
  moved,
  copiedSourceRetained,
  cancelled,
  failedBeforeCopy,
}

class NotebookTransferResult {
  const NotebookTransferResult(
    this.status, {
    this.notebook,
    this.error,
    this.sourceDigest,
  });
  final NotebookTransferStatus status;
  final StoredNotebook? notebook;
  final Object? error;

  /// Version copied from the source; retrying deletion must verify it again.
  final String? sourceDigest;
}

class UnsafeNotebookTransfer implements Exception {}

class NotebookTransferCoordinator {
  Future<void> delete(NotebookStorage storage, StoredNotebook notebook) async {
    if (kIsWeb ||
        storage is! NotebookDeletion ||
        !(storage as NotebookDeletion).canDelete(notebook)) {
      throw UnsupportedError('Deletion unavailable');
    }
    await (storage as NotebookDeletion).delete(notebook);
    await forgetDeleted(notebook);
  }

  Future<void> forgetDeleted(StoredNotebook notebook) async {
    try {
      await NotebookCache.instance.remove(notebook);
    } catch (error) {
      debugPrint('Could not remove disposable notebook cache: $error');
    }
    await RecentFiles.forget(notebook.id, backendId: notebook.backendId);
  }

  Future<NotebookTransferResult> move({
    required NotebookStorage source,
    required StoredNotebook original,
    required NotebookStorage destination,
    required NotebookFolder folder,
    required String name,
    required Uint8List bytes,
    required List<NotebookPdfResource> pdfs,
    bool cachedOrigin = false,
  }) async {
    StoredNotebook? copy;
    String? sourceDigest;
    try {
      if (kIsWeb ||
          cachedOrigin ||
          source is! NotebookDeletion ||
          !(source as NotebookDeletion).canDelete(original) ||
          destination is! NotebookTransfer ||
          source.id != original.backendId ||
          destination.id != folder.backendId) {
        throw UnsupportedError('Transfer unavailable');
      }
      validateNotebookName(name);
      if (destination is LocalNotebookStorage &&
          source is! LocalNotebookStorage &&
          pdfs.isNotEmpty) {
        throw UnsafeNotebookTransfer();
      }
      String filename(String value) =>
          value.toLowerCase().endsWith('.xopp') ? value : '$value.xopp';
      if (source.id == destination.id &&
          source is NotebookTransfer &&
          filename(name) == filename(original.name) &&
          await (source as NotebookTransfer).containsNotebook(
            folder,
            original,
          )) {
        return const NotebookTransferResult(NotebookTransferStatus.cancelled);
      }
      // Resolve every resource before creating anything or deleting the source.
      // This also ensures the source is accessible, even for an editor snapshot.
      sourceDigest = sha256
          .convert(await source.readNotebook(original))
          .toString();
      final resources = <NotebookPdfResource>[];
      for (final pdf in pdfs) {
        final data = await pdf.read();
        resources.add(
          NotebookPdfResource(reference: pdf.reference, read: () async => data),
        );
      }
      copy = await (destination as NotebookTransfer).createInFolder(
        folder: folder,
        name: name,
        bytes: bytes,
        pdfs: resources,
      );
      if (copy == null)
        return const NotebookTransferResult(NotebookTransferStatus.cancelled);
      if (copy.backendId != destination.id ||
          (copy.backendId == original.backendId && copy.id == original.id)) {
        throw StateError('Destination must have a distinct identity');
      }
    } catch (error) {
      return NotebookTransferResult(
        NotebookTransferStatus.failedBeforeCopy,
        error: error,
      );
    }
    try {
      // A second client may have edited the source while resources and the
      // destination copy were being written. Never delete that newer version.
      await _verifySourceUnchanged(source, original, sourceDigest);
      await (source as NotebookDeletion).delete(original);
    } catch (error) {
      return NotebookTransferResult(
        NotebookTransferStatus.copiedSourceRetained,
        notebook: copy,
        error: error,
        sourceDigest: sourceDigest,
      );
    }
    await _afterMove(original, copy);
    return NotebookTransferResult(NotebookTransferStatus.moved, notebook: copy);
  }

  /// Retry only deletion after a completed copy, without creating another copy.
  Future<void> retrySourceDeletion(
    NotebookStorage source,
    StoredNotebook original,
    StoredNotebook destination, {
    required String sourceDigest,
  }) async {
    if (kIsWeb ||
        source is! NotebookDeletion ||
        !(source as NotebookDeletion).canDelete(original)) {
      throw UnsupportedError('Deletion unavailable');
    }
    await _verifySourceUnchanged(source, original, sourceDigest);
    await (source as NotebookDeletion).delete(original);
    await _afterMove(original, destination);
  }

  Future<void> _verifySourceUnchanged(
    NotebookStorage source,
    StoredNotebook original,
    String expectedDigest,
  ) async {
    final current = await source.readNotebook(original);
    if (sha256.convert(current).toString() != expectedDigest) {
      throw NotebookEditConflict(original.id);
    }
  }

  Future<void> _afterMove(
    StoredNotebook original,
    StoredNotebook destination,
  ) async {
    try {
      await DraftRecovery.relocate(original, destination);
    } catch (error) {
      debugPrint('Could not relocate recovery drafts: $error');
    }
    // Metadata cleanup is separate from physical deletion. Never retry a copy
    // because local metadata cleanup failed after a completed move.
    try {
      await forgetDeleted(original);
    } catch (error) {
      debugPrint('Could not remove old notebook metadata: $error');
    }
  }
}
