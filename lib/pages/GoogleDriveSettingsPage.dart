import 'package:flutter/material.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/src/GoogleDriveManager.dart';
import 'package:xournalpp/src/GoogleDriveStorage.dart';

class GoogleDriveSettingsPage extends StatefulWidget {
  const GoogleDriveSettingsPage({super.key});
  @override
  State<GoogleDriveSettingsPage> createState() =>
      _GoogleDriveSettingsPageState();
}

class _GoogleDriveSettingsPageState extends State<GoogleDriveSettingsPage> {
  GoogleDriveStorage? storage;
  final folders = <GoogleDriveFolder>[];
  final path = <GoogleDriveFolder>[];
  bool busy = false;
  String? error;

  Future<void> connect() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final backend = await GoogleDriveManager.connect();
      final listing = await backend.listFolder(backend.folderId);
      if (!mounted) return;
      setState(() {
        storage = backend;
        folders
          ..clear()
          ..addAll(listing.folders);
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> browse(List<GoogleDriveFolder> next) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final folderId = next.isEmpty ? 'root' : next.last.id;
      final listing = await storage!.listFolder(folderId);
      if (!mounted) return;
      setState(() {
        path
          ..clear()
          ..addAll(next);
        folders
          ..clear()
          ..addAll(listing.folders);
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Google Drive')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (storage == null) ...[
          Text(S.of(context).storageFolderOnboarding),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : connect,
            child: Text(S.of(context).googleDriveConnect),
          ),
        ] else ...[
          Text(
            '${S.of(context).nextcloudChooseFolder}: /${path.map((folder) => folder.name).join('/')}',
          ),
          if (path.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: Text(S.of(context).nextcloudParentFolder),
              onTap: busy
                  ? null
                  : () => browse(path.sublist(0, path.length - 1)),
            ),
          for (final folder in folders)
            ListTile(
              leading: const Icon(Icons.folder),
              title: Text(folder.name),
              onTap: busy ? null : () => browse([...path, folder]),
            ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      final target = GoogleDriveManager.forFolder(
                        path.isEmpty ? 'root' : path.last.id,
                      );
                      await GoogleDriveManager.configure(
                        target,
                        path.isEmpty ? '/' : path.last.name,
                      );
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) setState(() => error = e.toString());
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(S.of(context).nextcloudUseFolder),
          ),
        ],
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}
