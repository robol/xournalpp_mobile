import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/widgets/QuotaTile.dart';

class MainDrawer extends StatefulWidget {
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
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => OpenPage()),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.folder),
                  title: Text(S.of(context).open),
                  onTap: () => XppFile.openAndEdit(context: context),
                ),
                ListTile(
                  leading: Icon(Icons.insert_drive_file),
                  title: Text(S.of(context).newFile),
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => CanvasPage(
                        file: XppFile.empty(background: Colors.white),
                      ),
                    ),
                  ),
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
                    applicationLegalese: 'Powered by TestApp.schule',
                    children: [
                      Image.asset('assets/feature-banner.png', scale: 2),
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 8),
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
}
