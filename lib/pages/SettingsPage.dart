import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/MainDrawer.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _drawWithStylusOnly = false;

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
            title: const Text('Draw with stylus only', 
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text(
              'Finger touches pan the page instead of drawing.', 
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 14),
            ),
            value: _drawWithStylusOnly,
            onChanged: _setDrawWithStylusOnly,
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
    });
  }

  Future<void> _setDrawWithStylusOnly(bool value) async {
    setState(() => _drawWithStylusOnly = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PreferencesKeys.kDrawWithStylusOnly, value);
  }
}
