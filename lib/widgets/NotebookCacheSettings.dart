import 'package:flutter/material.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/src/NotebookCache.dart';

class NotebookCacheSettings extends StatefulWidget {
  const NotebookCacheSettings({super.key});
  @override
  State<NotebookCacheSettings> createState() => _NotebookCacheSettingsState();
}

class _NotebookCacheSettingsState extends State<NotebookCacheSettings> {
  bool? enabled;
  int? size;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final value = await NotebookCache.instance.enabled;
      if (mounted) setState(() => enabled = value);
      final bytes = await NotebookCache.instance.size();
      if (mounted)
        setState(() {
          enabled = value;
          size = bytes;
        });
    } catch (_) {
      _error();
    }
  }

  void _error() {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.of(context).cacheUnavailable)));
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SwitchListTile(
        title: Text(S.of(context).cacheSetting),
        subtitle: Text(S.of(context).cacheSettingDescription),
        value: enabled ?? true,
        onChanged: enabled == null || busy
            ? null
            : (value) async {
                setState(() => busy = true);
                try {
                  await NotebookCache.instance.setEnabled(value);
                  await _refresh();
                } catch (_) {
                  _error();
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
      ),
      ListTile(
        title: Text(S.of(context).cacheClear),
        subtitle: Text(
          '${size == null ? '…' : (size! / (1024 * 1024)).toStringAsFixed(1)} MB',
        ),
        trailing: const Icon(Icons.delete_outline),
        onTap: busy
            ? null
            : () async {
                final clear = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(S.of(context).cacheClear),
                    content: Text(S.of(context).cacheClearConfirm),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(S.of(context).cancel),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(S.of(context).cacheClear),
                      ),
                    ],
                  ),
                );
                if (clear != true || !mounted) return;
                setState(() => busy = true);
                try {
                  await NotebookCache.instance.clear();
                  await _refresh();
                } catch (_) {
                  _error();
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
      ),
    ],
  );
}
