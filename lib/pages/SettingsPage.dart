import 'package:flutter/material.dart';
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
}
