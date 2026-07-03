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
import 'package:xournalpp/widgets/QuotaTile.dart';

class MainDrawer extends StatefulWidget {
  final Future<bool> Function()? onLeaveRequested;

  const MainDrawer({Key? key, this.onLeaveRequested}) : super(key: key);

  @override
  _MainDrawerState createState() => _MainDrawerState();
}

class _MainDrawerState extends State<MainDrawer> {
  PackageInfo? info;

  @override
  void initState() {
    PackageInfo.fromPlatform().then((value) => info = value);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: MainDrawer,
      child: Drawer(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/xournalpp_horizontal_icon.png',
                  fit: BoxFit.cover,
                ),
                ListTile(
                  leading: Icon(Icons.home),
                  title: Text(S.of(context).home),
                  onTap: _openHome,
                ),
                ListTile(
                  leading: Icon(Icons.folder),
                  title: Text(S.of(context).open),
                  onTap: _openFile,
                ),
                ListTile(
                  leading: Icon(Icons.picture_as_pdf),
                  title: Text(S.of(context).importPdf),
                  onTap: _importPdf,
                ),
                ListTile(
                  leading: Icon(Icons.insert_drive_file),
                  title: Text(S.of(context).newFile),
                  onTap: _newFile,
                ),
                Divider(),
              ],
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QuotaTile(),
                Divider(),
                ListTile(
                  leading: Icon(Icons.settings),
                  title: const Text('Settings'),
                  onTap: _openSettings,
                ),
                ListTile(
                  leading: Icon(Icons.info),
                  title: Text(S.of(context).about),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: S.of(context).aboutXournalMobileEdition,
                    applicationVersion:
                        'Version ${info?.version} build ${info?.buildNumber}',
                    applicationIcon: Image.asset(
                      'assets/xournalpp.png',
                      scale: 8,
                    ),
                    applicationLegalese:
                        'Xournal++ Mobile © its original authors and contributors. \n'
                        'Licensed under the EUPL-1.2.',
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 8),
                        child: Image.asset(
                          'assets/feature-banner.png',
                          scale: 2,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton(
                          onPressed: () => launchUrl(
                            Uri.parse('https://github.com/xournalpp/xournalpp'),
                          ),
                          child: Text(S.of(context).aboutXournal),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton(
                          onPressed: () => launchUrl(
                            Uri.parse(
                              'https://gitlab.com/robol/xournalpp_mobile',
                            ),
                          ),
                          child: Text(S.of(context).sourceCode),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(S.of(context).forkedBy),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _canLeave() async {
    return await (widget.onLeaveRequested?.call() ?? Future.value(true));
  }

  Future<void> _openHome() async {
    if (!await _canLeave() || !context.mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (context) => OpenPage()));
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
    final file = await runWithLoadingFileDialog(context, () async {
      final pdf = await XppPickedFile.importFromStorage(
        type: XppFilePickType.custom,
        fileExtension: 'pdf',
      );
      final file = await XppFile.importPdf(pdf: pdf);
      if (context.mounted) await file.prepareForOpening(context);
      return file;
    });

    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => CanvasPage(file: file)),
    );
  }
}
