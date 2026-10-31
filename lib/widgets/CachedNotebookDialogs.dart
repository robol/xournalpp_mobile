import 'package:flutter/material.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/src/NotebookCache.dart';
import 'package:xournalpp/src/NotebookStorage.dart';

Future<CachedNotebook?> offerCachedNotebook(
  BuildContext context,
  StoredNotebook notebook,
) async {
  CachedNotebook? cached;
  try {
    cached = await NotebookCache.instance.load(notebook);
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.of(context).cacheUnavailable)));
    return null;
  }
  if (cached == null || !context.mounted) return null;
  final snapshot = cached;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) {
      final strings = S.of(context);
      return AlertDialog(
        title: Text(strings.cacheOpenTitle),
        content: Text(
          '${strings.cacheWarning}\n\n'
          '${strings.cacheCheckpoint}: ${snapshot.checkpoint.toLocal()}\n'
          '${snapshot.dirty ? strings.cacheUnsaved : strings.cacheSaved}'
          '${snapshot.missingPdfs.isEmpty ? '' : '\n${strings.cacheIncomplete}'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.cacheOpen),
          ),
        ],
      );
    },
  );
  return accepted == true ? cached : null;
}

enum CachedSaveChoice { cancel, copy, overwrite }

Future<CachedSaveChoice> confirmCachedOverwrite(BuildContext context) async =>
    await showDialog<CachedSaveChoice>(
      context: context,
      builder: (context) {
        final strings = S.of(context);
        return AlertDialog(
          title: Text(strings.cacheOverwriteTitle),
          content: Text(strings.cacheWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, CachedSaveChoice.cancel),
              child: Text(strings.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, CachedSaveChoice.copy),
              child: Text(strings.cacheSaveCopy),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, CachedSaveChoice.overwrite),
              child: Text(strings.cacheOverwrite),
            ),
          ],
        );
      },
    ) ??
    CachedSaveChoice.cancel;
