import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xournalpp/src/NextcloudConnection.dart';
import 'package:xournalpp/src/NextcloudManager.dart';

class NextcloudSettingsPage extends StatefulWidget {
  const NextcloudSettingsPage({super.key});
  @override
  State<NextcloudSettingsPage> createState() => _NextcloudSettingsPageState();
}

class _NextcloudSettingsPageState extends State<NextcloudSettingsPage> {
  final address = TextEditingController();
  final connection = NextcloudConnection();
  NextcloudCredentials? credentials;
  List<String> folder = [];
  List<NextcloudFolder> folders = [];
  bool busy = false;
  int generation = 0;
  String? error;

  @override
  void dispose() {
    generation++;
    address.dispose();
    connection.close();
    super.dispose();
  }

  Future<void> login() async {
    final current = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final server = NextcloudConnection.serverUri(address.text);
      final login = await connection.startLogin(server);
      if (!await launchUrl(login.login, mode: LaunchMode.externalApplication))
        throw StateError('Could not open browser');
      NextcloudCredentials? result;
      for (var i = 0; i < 150 && mounted && generation == current; i++) {
        result = await connection.pollLogin(server, login);
        if (result != null) break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (!mounted || generation != current) return;
      if (result == null) throw StateError('Login timed out');
      credentials = result;
      await loadFolder([]);
    } catch (e) {
      if (mounted && generation == current)
        setState(() => error = e.toString());
    } finally {
      if (mounted && generation == current) setState(() => busy = false);
    }
  }

  Future<void> loadFolder(List<String> path) async {
    final result = await connection.folders(credentials!, path);
    if (!mounted) return;
    setState(() {
      folder = List.of(path);
      folders = result;
      error = null;
    });
  }

  Future<void> chooseFolder(List<String> path) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await loadFolder(path);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nextcloud')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (credentials == null) ...[
          Text(S.of(context).storageFolderOnboarding),
          const SizedBox(height: 12),
          TextField(
            controller: address,
            decoration: InputDecoration(
              labelText: S.of(context).nextcloudAddress,
              hintText: 'https://cloud.example.com',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : login,
            child: Text(S.of(context).nextcloudConnect),
          ),
          if (busy)
            TextButton(
              onPressed: () => setState(() {
                generation++;
                busy = false;
              }),
              child: Text(S.of(context).nextcloudCancelLogin),
            ),
        ] else ...[
          Text('${S.of(context).nextcloudChooseFolder}: /${folder.join('/')}'),
          if (folder.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: Text(S.of(context).nextcloudParentFolder),
              onTap: busy
                  ? null
                  : () => chooseFolder(folder.sublist(0, folder.length - 1)),
            ),
          for (final item in folders)
            ListTile(
              leading: const Icon(Icons.folder),
              title: Text(item.name),
              onTap: busy ? null : () => chooseFolder(item.path),
            ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      await NextcloudManager.configure(credentials!, folder);
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
