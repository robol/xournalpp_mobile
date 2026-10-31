import 'package:flutter/material.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/src/NotebookCache.dart';
import 'package:xournalpp/src/NotebookStorage.dart';

class CachedNotebookList extends StatefulWidget {
  const CachedNotebookList({
    super.key,
    this.backendId,
    this.error,
    required this.onOpen,
  });
  final String? backendId;
  final Object? error;
  final ValueChanged<StoredNotebook> onOpen;
  @override
  State<CachedNotebookList> createState() => _CachedNotebookListState();
}

class _CachedNotebookListState extends State<CachedNotebookList> {
  final cache = NotebookCache.instance;
  late Future<List<StoredNotebook>> entries;
  @override
  void initState() {
    super.initState();
    entries = cache.list(backendId: widget.backendId);
    cache.changes.addListener(_reload);
  }

  void _reload() {
    if (mounted)
      setState(() {
        entries = cache.list(backendId: widget.backendId);
      });
  }

  @override
  void didUpdateWidget(CachedNotebookList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backendId != widget.backendId) _reload();
  }

  @override
  void dispose() {
    cache.changes.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<StoredNotebook>>(
    future: entries,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done)
        return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Text(S.of(context).cacheUnavailable);
      if (snapshot.data!.isEmpty)
        return Text(
          '${widget.error == null ? '' : '${S.of(context).errorOpeningFile}${widget.error}\n'}${S.of(context).cacheEmpty}',
        );
      return ListView(
        shrinkWrap: true,
        children: [
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${S.of(context).errorOpeningFile}${widget.error}'),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(S.of(context).cacheWarning),
          ),
          for (final notebook in snapshot.data!)
            ListTile(
              leading: const Icon(Icons.offline_pin_outlined),
              title: Text(notebook.name),
              subtitle: Text(
                '${S.of(context).cacheCheckpoint}: ${notebook.modified!.toLocal()}',
              ),
              onTap: () => widget.onOpen(notebook),
            ),
        ],
      );
    },
  );
}
