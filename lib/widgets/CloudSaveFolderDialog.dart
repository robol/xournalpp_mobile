import 'package:flutter/material.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/src/GoogleDriveStorage.dart';
import 'package:xournalpp/src/NextcloudStorage.dart';
import 'package:xournalpp/src/NotebookStorage.dart';

class CloudSaveFolderDialog extends StatefulWidget {
  const CloudSaveFolderDialog({super.key, required this.storage});
  final NotebookStorage storage;
  @override
  State<CloudSaveFolderDialog> createState() => _CloudSaveFolderDialogState();
}

class _CloudSaveFolderDialogState extends State<CloudSaveFolderDialog> {
  final List<({String id, String name})> path = [];
  late Future<List<({String id, String name})>> listing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final storage = widget.storage;
    if (storage is NextcloudStorage) {
      listing = storage
          .listFolder(path.map((item) => item.id).toList())
          .then(
            (result) =>
                result.folders.map((name) => (id: name, name: name)).toList(),
          );
    } else {
      final drive = storage as GoogleDriveStorage;
      listing = drive
          .listFolder(path.isEmpty ? drive.folderId : path.last.id)
          .then(
            (result) => result.folders
                .map((item) => (id: item.id, name: item.name))
                .toList(),
          );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(S.of(context).nextcloudChooseFolder),
    content: SizedBox(
      width: 450,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('/${path.map((item) => item.name).join('/')}'),
          Flexible(
            child: FutureBuilder<List<({String id, String name})>>(
              future: listing,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return Text(
                    '${S.of(context).errorOpeningFile}${snapshot.error}',
                  );
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                return ListView(
                  shrinkWrap: true,
                  children: [
                    if (path.isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.arrow_upward),
                        title: Text(S.of(context).nextcloudParentFolder),
                        onTap: () => setState(() {
                          path.removeLast();
                          _load();
                        }),
                      ),
                    for (final folder in snapshot.data!)
                      ListTile(
                        leading: const Icon(Icons.folder),
                        title: Text(folder.name),
                        onTap: () => setState(() {
                          path.add(folder);
                          _load();
                        }),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(S.of(context).cancel),
      ),
      TextButton(
        onPressed: () =>
            Navigator.pop(context, path.map((item) => item.id).toList()),
        child: Text(S.of(context).nextcloudUseFolder),
      ),
    ],
  );
}
