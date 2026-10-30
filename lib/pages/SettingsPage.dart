import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:xournalpp/src/NextcloudManager.dart';
import 'package:xournalpp/src/GoogleDriveManager.dart';
import 'package:xournalpp/pages/GoogleDriveSettingsPage.dart';
import 'package:xournalpp/pages/NextcloudSettingsPage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/MainDrawer.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _drawWithStylusOnly = false;
  bool _simplifyStrokes = true;
  bool _stylusPressureSensitivity = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: MainDrawer(),
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (GoogleDriveManager.supported)
            ValueListenableBuilder<int>(
              valueListenable: GoogleDriveManager.changes,
              builder: (context, _, __) => ListTile(
                leading: const Icon(Icons.add_to_drive),
                title: const Text('Google Drive'),
                subtitle: Text(
                  GoogleDriveManager.current == null
                      ? S.of(context).nextcloudNotConnected
                      : S.of(context).googleDriveConnected,
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const GoogleDriveSettingsPage(),
                  ),
                ),
                trailing: GoogleDriveManager.current == null
                    ? null
                    : IconButton(
                        tooltip: S.of(context).nextcloudDisconnect,
                        icon: const Icon(Icons.link_off),
                        onPressed: () async {
                          try {
                            await GoogleDriveManager.disconnect();
                          } catch (error) {
                            if (context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                          }
                        },
                      ),
              ),
            ),
          if (!kIsWeb)
            ValueListenableBuilder<int>(
              valueListenable: NextcloudManager.changes,
              builder: (context, _, __) => ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('Nextcloud'),
                subtitle: Text(
                  NextcloudManager.current == null
                      ? S.of(context).nextcloudNotConnected
                      : '${NextcloudManager.current!.credentials.server} /${NextcloudManager.current!.folder.join('/')}',
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NextcloudSettingsPage(),
                  ),
                ),
                trailing: NextcloudManager.current == null
                    ? null
                    : IconButton(
                        tooltip: S.of(context).nextcloudDisconnect,
                        icon: const Icon(Icons.link_off),
                        onPressed: () async {
                          try {
                            await NextcloudManager.disconnect();
                          } catch (error) {
                            if (context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                          }
                        },
                      ),
              ),
            ),
          SwitchListTile(
            title: const Text(
              'Draw with stylus only',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Finger touches pan the page instead of drawing.',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 14),
            ),
            value: _drawWithStylusOnly,
            onChanged: _setDrawWithStylusOnly,
          ),
          SwitchListTile(
            title: Text(
              S.of(context).stylusPressureSensitivity,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              S.of(context).stylusPressureSensitivityDescription,
              style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 14),
            ),
            value: _stylusPressureSensitivity,
            onChanged: _setStylusPressureSensitivity,
          ),
          SwitchListTile(
            title: Text(
              S.of(context).simplifyStrokes,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              S.of(context).simplifyStrokesDescription,
              style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 14),
            ),
            value: _simplifyStrokes,
            onChanged: _setSimplifyStrokes,
          ),
        ],
      ),
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _drawWithStylusOnly =
          prefs.getBool(PreferencesKeys.kDrawWithStylusOnly) ?? false;
      _simplifyStrokes =
          prefs.getBool(PreferencesKeys.kSimplifyStrokes) ?? true;
      _stylusPressureSensitivity =
          prefs.getBool(PreferencesKeys.kStylusPressureSensitivity) ?? true;
    });
  }

  Future<void> _setDrawWithStylusOnly(bool value) async {
    setState(() => _drawWithStylusOnly = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PreferencesKeys.kDrawWithStylusOnly, value);
  }

  Future<void> _setSimplifyStrokes(bool value) async {
    setState(() => _simplifyStrokes = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PreferencesKeys.kSimplifyStrokes, value);
  }

  Future<void> _setStylusPressureSensitivity(bool value) async {
    setState(() => _stylusPressureSensitivity = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PreferencesKeys.kStylusPressureSensitivity, value);
  }
}
