import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/pages/SettingsPage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:xournalpp/widgets/LoadingFileDialog.dart';
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:xournalpp/src/NextcloudManager.dart';
import 'package:xournalpp/src/GoogleDriveManager.dart';
import 'package:xournalpp/src/RecentProvider.dart';

class MainDrawer extends StatefulWidget {
  final Future<bool> Function()? onLeaveRequested;
  final bool persistent;
  final bool home;
  final void Function(NotebookStorage)? onStorage;
  final VoidCallback? onRecent;

  const MainDrawer({
    Key? key,
    this.onLeaveRequested,
    this.persistent = false,
    this.home = false,
    this.onStorage,
    this.onRecent,
  }) : super(key: key);

  @override
  _MainDrawerState createState() => _MainDrawerState();
}

class _MainDrawerState extends State<MainDrawer> {
  PackageInfo? info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((value) {
      if (mounted) setState(() => info = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Image.asset('assets/xournalpp.png', width: 52, height: 52),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Xournal++',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'mobile',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _newFile,
            icon: const Icon(Icons.add),
            label: Text(S.of(context).newNotebook),
          ),
          const SizedBox(height: 16),
          _heading(S.of(context).sidebarLibrary),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(S.of(context).sidebarRecent),
            selected: widget.home,
            onTap: widget.onRecent ?? _openHome,
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: Text(S.of(context).open),
            onTap: _openFile,
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: Text(S.of(context).importPdf),
            onTap: _importPdf,
          ),
          const Divider(),
          _heading(S.of(context).sidebarStorage),
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: Text(S.of(context).sidebarLocalDevice),
            onTap: () => _openStorage(defaultNotebookStorage),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([
              NextcloudManager.changes,
              GoogleDriveManager.changes,
            ]),
            builder: (context, _) => Column(
              children: [
                for (final backend in notebookStorageBackends.where(
                  (b) =>
                      b != internalNotebookStorage && b != localNotebookStorage,
                ))
                  _providerTile(backend),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(S.of(context).settingsTitle),
            onTap: _openSettings,
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(S.of(context).about),
            onTap: _about,
          ),
        ],
      ),
    );
    return widget.persistent
        ? Material(child: content)
        : Drawer(child: content);
  }

  Widget _providerTile(NotebookStorage backend) {
    final label = recentProviderLabel(backend) ?? backend.id;
    final separator = label.indexOf(' · ');
    final name = separator < 0 ? label : label.substring(0, separator);
    final details = separator < 0 ? null : label.substring(separator + 3);
    return ListTile(
      leading: backend.iconAsset == null
          ? const Icon(Icons.cloud_outlined)
          : Image.asset(backend.iconAsset!, width: 24, height: 24),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: details == null
          ? null
          : Text(
              details,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
      onTap: () => _openStorage(backend),
    );
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Text(title, style: Theme.of(context).textTheme.labelLarge),
  );

  Future<void> _openStorage(NotebookStorage storage) async {
    if (widget.onStorage != null) {
      widget.onStorage!(storage);
      return;
    }
    if (!await _canLeave() || !context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => OpenPage(initialStorage: storage)),
      (route) => false,
    );
  }

  void _about() => showAboutDialog(
    context: context,
    applicationName: S.of(context).aboutXournalMobileEdition,
    applicationVersion: 'Version ${info?.version} build ${info?.buildNumber}',
    applicationIcon: Image.asset('assets/xournalpp.png', scale: 8),
    applicationLegalese:
        'Xournal++ Mobile © its original authors and contributors. \nLicensed under the EUPL-1.2.',
    children: [
      OutlinedButton(
        onPressed: () =>
            launchUrl(Uri.parse('https://github.com/xournalpp/xournalpp')),
        child: Text(S.of(context).aboutXournal),
      ),
      OutlinedButton(
        onPressed: () =>
            launchUrl(Uri.parse('https://github.com/robol/xournalpp_mobile')),
        child: Text(S.of(context).sourceCode),
      ),
      Text(S.of(context).forkedBy),
    ],
  );

  Future<bool> _canLeave() async {
    return await (widget.onLeaveRequested?.call() ?? Future.value(true));
  }

  Future<void> _openHome() async {
    if (!await _canLeave() || !context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => OpenPage()),
      (route) => false,
    );
  }

  Future<void> _openFile() async {
    if (!await _canLeave() || !context.mounted) return;
    XppFile.openAndEdit(context: context);
  }

  Future<void> _newFile() async {
    if (!await _canLeave() || !context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) =>
            CanvasPage(file: XppFile.empty(background: Colors.white)),
      ),
    );
  }

  Future<void> _openSettings() async {
    if (!await _canLeave() || !context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
  }

  Future<void> _importPdf() async {
    if (!await _canLeave() || !context.mounted) return;
    try {
      final file = await runWithLoadingFileDialog(context, () async {
        final pdf = await XppPickedFile.importFromStorage(
          type: XppFilePickType.custom,
          fileExtension: 'pdf',
        );
        return XppFile.importPdf(pdf: pdf);
      });
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => CanvasPage(file: file)),
      );
    } on XppFilePickerCancelled {
      // User cancelled the picker.
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.of(context).errorOpeningFile}$error')),
      );
    }
  }
}
