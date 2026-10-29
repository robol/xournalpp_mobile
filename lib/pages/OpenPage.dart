import 'dart:async';
import 'dart:convert';

import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/widgets/Workspace.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/RecentFiles.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/DropFile.dart';
import 'package:xournalpp/widgets/LoadingFileDialog.dart';
import 'package:xournalpp/widgets/MainDrawer.dart';

const _androidIntentChannel = MethodChannel('it.robol.xournal.mobile/intent');

class OpenPage extends StatefulWidget {
  @override
  _OpenPageState createState() => _OpenPageState();
}

class _OpenPageState extends State<OpenPage> with TickerProviderStateMixin {
  bool _loadedRecent = false;
  Set recentFiles = Set();

  late AnimationController _animationController;
  StreamSubscription<List<SharedMediaFile>>? _mediaSubscription;

  @override
  void dispose() {
    RecentFiles.changes.removeListener(_loadRecentFiles);
    _mediaSubscription?.cancel();
    _androidIntentChannel.setMethodCallHandler(null);
    _animationController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 250),
      value: 0,
    )..addListener((() => setState(() {})));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) afterFirstLayout(context);
    });

    RecentFiles.changes.addListener(_loadRecentFiles);
    _loadRecentFiles();
    super.initState();
  }

  void _loadRecentFiles() {
    SharedPreferences.getInstance()
        .then((prefs) {
          if (!mounted) return;
          String? jsonData = prefs.getString(PreferencesKeys.kRecentFiles);
          if (jsonData != null) {
            recentFiles = (jsonDecode(jsonData) as List).reversed
                .toList()
                .toSet();
          }
          setState(() {
            _loadedRecent = true;
          });
        })
        .catchError((e) {
          if (!mounted) return;
          print('No SharedPreferences available for this platform.');
          setState(() {
            _loadedRecent = true;
          });
        });
  }

  void afterFirstLayout(BuildContext context) {
    if (![
      TargetPlatform.android,
      TargetPlatform.iOS,
    ].contains(defaultTargetPlatform)) {
      return;
    }
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        _androidIntentChannel.setMethodCallHandler((call) async {
          if (call.method == 'openIntent') {
            await receivedShareNotification(call.arguments);
          }
        });
        _androidIntentChannel
            .invokeMapMethod<String, String?>('getInitialOpenIntent')
            .then(receivedShareNotification)
            .catchError((_) {});
      }

      // For sharing images coming from outside the app while the app is in the memory
      _mediaSubscription = ReceiveSharingIntent.instance
          .getMediaStream()
          .listen(
            (List<SharedMediaFile> value) {
              if (mounted) unawaited(receivedShareNotification(value));
            },
            onError: (err) {
              print("getIntentDataStream error: $err");
            },
          );

      // For sharing images coming from outside the app while the app is closed
      ReceiveSharingIntent.instance
          .getInitialMedia()
          .then((List<SharedMediaFile> value) {
            if (mounted) return receivedShareNotification(value);
          })
          .catchError((e) {});
    } catch (e) {}
  }

  void _newNotebook() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CanvasPage(file: XppFile.empty(background: Colors.white)),
    ),
  );

  Future<void> _importPdf() async {
    final _file = await runWithLoadingFileDialog(context, () async {
      final pdf = await XppPickedFile.importFromStorage(
        type: XppFilePickType.custom,
        fileExtension: 'pdf',
      );
      return XppFile.importPdf(pdf: pdf);
    }); // TODO `.pdf`
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (c) => CanvasPage(file: _file)));
  }

  @override
  Widget build(BuildContext context) {
    final files = recentFiles.toList();
    return Scaffold(
      onDrawerChanged: (opened) =>
          _animationController.animateTo(opened ? 1 : 0),
      drawer: MainDrawer(),
      appBar: AppBar(
        title: const Text('Xournal++'),
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: S.of(context).openNavigation,
            icon: AnimatedIcon(
              icon: AnimatedIcons.menu_arrow,
              progress: _animationController,
            ),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final padding = constraints.maxWidth < 600 ? 16.0 : 32.0;
                final width = constraints.maxWidth - padding * 2;
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final columns =
                    (width / ((constraints.maxWidth < 600 ? 160 : 220) * scale))
                        .floor()
                        .clamp(1, 5);
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(padding, 20, padding, 24),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              S.of(context).workspaceTitle,
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              S.of(context).workspaceSubtitle,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 28),
                            WorkspaceActions(
                              onNew: _newNotebook,
                              onOpen: () =>
                                  XppFile.openAndEdit(context: context),
                              onImport: _importPdf,
                            ),
                            if (kIsWeb) DropFile(),
                            const SizedBox(height: 32),
                            Text(
                              S.of(context).workspaceRecents,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!_loadedRecent)
                      const SliverToBoxAdapter(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (files.isEmpty)
                      SliverToBoxAdapter(
                        child: EmptyDocumentsState(onNew: _newNotebook),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(padding, 0, padding, 32),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                                mainAxisExtent: 184 + 112 * scale,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) =>
                                _documentCard(files[index], context),
                            childCount: files.length,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> receivedShareNotification(dynamic data) async {
    if (data == null ||
        data is List && data.isEmpty ||
        lastIntentData == data ||
        data is List &&
            data.isNotEmpty &&
            lastIntentData is List &&
            lastIntentData.isNotEmpty &&
            data[0].path == lastIntentData[0].path)
      return;
    lastIntentData = data;
    if (data is String) {
      /// checking if we were redirected from the web site
      if (data.startsWith('http')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).youveBeenRedirectedToTheLocalApp),
          ),
        );
        return;
      } else {
        /// seems to be an opened file
        /// ... which is awfully encoded as a content:// URI using the path as **queryComponent** instead of as **path** (why???)
        /// unfortunately, android needs to copy the file to our own app directory
        /// TODO: don't copy files we can directly read
        print(data);
        data = [SharedMediaFile(path: data, type: SharedMediaType.file)];
      }
    }
    if (data is Map) {
      final uri = data['uri']?.toString();
      if (uri == null || uri.isEmpty) return;
      final token =
          '$uri|${data['mimeType'] ?? ''}|${data['displayName'] ?? ''}';
      if (lastIntentData == token) return;
      lastIntentData = token;
      await _openExternalFile(
        uri,
        mimeType: data['mimeType']?.toString(),
        displayName: data['displayName']?.toString(),
      );
      return;
    }
    if (data is List && data.isNotEmpty) {
      await _openExternalFile(data[0].path, mimeType: data[0].mimeType);
    } else {
      print('Unsupported runtimeType: ${data.runtimeType.toString()}');
    }
  }

  Future<void> _openExternalFile(
    String path, {
    String? mimeType,
    String? displayName,
  }) async {
    bool _aborted = false;
    bool _dialogVisible = true;
    final name = _externalFileName(path, displayName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).openingFile),
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 24),
            Expanded(child: Text('${S.of(context).opening} $name ...')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _dialogVisible = false;
              Navigator.of(context).pop();
            },
            child: Text(S.of(context).background),
          ),
          TextButton(
            onPressed: () {
              _dialogVisible = false;
              Navigator.of(context).pop();
              _aborted = true;
            },
            child: Text(S.of(context).abort),
          ),
        ],
      ),
    );

    try {
      final extension = _externalFileExtension(
        path,
        mimeType: mimeType,
        displayName: displayName,
      );
      final pickedFile = await XppPickedFile.fromExternalPath(
        path: path,
        fileName: displayName,
        fileExtension: extension,
      );
      final XppFile file;
      final String? filePath;
      if (extension == 'pdf') {
        file = await XppFile.importPdf(pdf: pickedFile);
        filePath = null;
      } else {
        file = await XppFile.fromXppPickedFile(
          pickedFile,
          (percentage) => null,
          showMissingFileDialog,
        );
        filePath = pickedFile.path;
      }
      if (_aborted || !context.mounted) {
        if (_aborted) lastIntentData = null;
        return;
      }
      if (_dialogVisible) Navigator.of(context, rootNavigator: true).pop();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => CanvasPage(file: file, filePath: filePath),
        ),
      );
    } catch (e) {
      lastIntentData = null;
      if (!context.mounted) return;
      if (_dialogVisible) Navigator.of(context, rootNavigator: true).pop();
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(S.of(context).errorOpeningFile),
          content: SelectableText(
            S.of(context).imVerySorryButICouldntReadTheFile +
                path +
                S.of(context).areYouSureIHaveThePermissionAndAreYou +
                '\n${e.toString()}',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: e.toString())),
              child: Text(S.of(context).copyErrorMessage),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).okay),
            ),
          ],
        ),
      );
    }
  }

  String _externalFileName(String path, String? displayName) {
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final decoded = _decodeFileInfoForDisplay(path);
    final lastSlash = decoded.lastIndexOf('/');
    return lastSlash < 0 ? decoded : decoded.substring(lastSlash + 1);
  }

  String _externalFileExtension(
    String path, {
    String? mimeType,
    String? displayName,
  }) {
    final name = _externalFileName(path, displayName).toLowerCase();
    if (name.endsWith('.pdf') ||
        mimeType == 'application/pdf' ||
        mimeType == 'application/x-pdf') {
      return 'pdf';
    }
    return 'xopp';
  }

  Widget _documentCard(Map fileInfo, BuildContext context) {
    return DocumentCard(
      name: _decodeFileInfoForDisplay(fileInfo['name']),
      path: _decodeFileInfoForDisplay(fileInfo['path']),
      modified: _formatModifiedForDisplay(context, fileInfo['modified']),
      preview: fileInfo['preview']?.toString(),
      onLongPress: () => showDeleteDialog(fileInfo['path']),
      onOpen: () async {
        try {
          final initialPage = _currentPageFromRecentFile(fileInfo);
          final file = await runWithLoadingFileDialog(context, () async {
            return XppFile.fromXppPickedFile(
              await XppPickedFile.fromInternalPath(path: fileInfo['path']),
              (percent) {},
              showMissingFileDialog,
            );
          });
          if (!context.mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => CanvasPage(
                file: file,
                filePath: fileInfo['path'],
                initialPage: initialPage,
              ),
            ),
          );
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context).errorOpeningFile + e.toString()),
            ),
          );
        }
      },
    );
  }

  String _decodeFileInfoForDisplay(Object? value) {
    final text = value?.toString() ?? '';
    try {
      return Uri.decodeFull(text);
    } on FormatException {
      return text;
    }
  }

  String _formatModifiedForDisplay(BuildContext context, Object? value) {
    if (value == null) return '';

    final modified = DateTime.tryParse(value.toString())?.toLocal();
    if (modified == null) return '';

    final locale = Localizations.localeOf(context).toString();
    return S
        .of(context)
        .workspaceModified(DateFormat.yMd(locale).add_Hm().format(modified));
  }

  int _currentPageFromRecentFile(Map fileInfo) {
    final page = fileInfo['currentPage'];
    if (page is int) return page < 0 ? 0 : page;
    return int.tryParse(page?.toString() ?? '') ?? 0;
  }

  showDeleteDialog(String path) {
    var deleteFile = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(S.of(context).confirmDelete),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(S.of(context).areYouSureToDeleteTheSelectedFileThisCannot),
                if (XppPickedFile.canDelete(path: path))
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(S.of(context).alsoDeleteFile),
                    value: deleteFile,
                    onChanged: (value) =>
                        setDialogState(() => deleteFile = value ?? false),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: Text(S.of(context).cancel),
            ),
            TextButton(
              onPressed: () async {
                try {
                  if (deleteFile) await XppPickedFile.delete(path: path);
                  await RecentFiles.forget(path);
                } catch (error) {
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${S.of(context).errorOpeningFile} $error'),
                    ),
                  );
                  return;
                }
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
              child: Text(S.of(context).forgetRecent),
            ),
          ],
        ),
      ),
    );
  }
}

final Map<(BuildContext, String?), Future<XppPickedFile>>
_missingFileSelections = {};

Future<XppPickedFile> showMissingFileDialog(
  BuildContext context,
  String? path,
) async {
  if (!context.mounted) throw StateError('PDF recovery owner was disposed.');
  final cacheKey = (context, path);
  final existingSelection = _missingFileSelections[cacheKey];
  if (existingSelection != null) return existingSelection;

  late Future<XppPickedFile> selection;
  selection = _resolveMissingPdfFile(context, path).whenComplete(() {
    if (identical(_missingFileSelections[cacheKey], selection)) {
      _missingFileSelections.remove(cacheKey);
    }
  });
  _missingFileSelections[cacheKey] = selection;
  return selection;
}

Future<XppPickedFile> _resolveMissingPdfFile(
  BuildContext context,
  String? path,
) async {
  final mappedPath = await _mappedMissingPdfPath(path);
  if (!context.mounted) throw StateError('PDF recovery owner was disposed.');
  if (mappedPath != null) {
    try {
      return await XppPickedFile.fromInternalPath(path: mappedPath);
    } catch (_) {
      await _forgetMissingPdfMapping(path);
    }
  }

  final file = await _pickMissingPdfFile(context, path);
  if (!context.mounted) throw StateError('PDF recovery owner was disposed.');
  await _rememberMissingPdfMapping(path, file.path);
  return file;
}

Future<XppPickedFile> _pickMissingPdfFile(
  BuildContext context,
  String? path,
) async {
  if (!context.mounted) throw StateError('PDF recovery owner was disposed.');
  final shouldPick = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(S.of(context).errorLoadingFile),
      content: Text(
        path == null
            ? S.of(context).couldNotFindBackgroundPdfSelectNewOne
            : '${S.of(context).couldNotFindBackgroundPdfSelectNewOne}\n$path',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(S.of(context).cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(S.of(context).open),
        ),
      ],
    ),
  );

  if (shouldPick != true) {
    throw UnsupportedError('Missing PDF file was not selected.');
  }

  if (!context.mounted) throw StateError('PDF recovery owner was disposed.');

  return XppPickedFile.importFromStorage(
    type: XppFilePickType.custom,
    fileExtension: 'pdf',
  );
}

Future<String?> _mappedMissingPdfPath(String? path) async {
  if (path == null || path.isEmpty) return null;
  final prefs = await SharedPreferences.getInstance();
  final mappings = _missingPdfMappingsFromPrefs(prefs);
  return mappings[path];
}

Future<void> _rememberMissingPdfMapping(
  String? originalPath,
  String? replacementPath,
) async {
  if (originalPath == null ||
      originalPath.isEmpty ||
      replacementPath == null ||
      replacementPath.isEmpty) {
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final mappings = _missingPdfMappingsFromPrefs(prefs);
  mappings[originalPath] = replacementPath;
  await prefs.setString(
    PreferencesKeys.kMissingPdfFileMappings,
    jsonEncode(mappings),
  );
}

Future<void> _forgetMissingPdfMapping(String? originalPath) async {
  if (originalPath == null || originalPath.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  final mappings = _missingPdfMappingsFromPrefs(prefs);
  if (mappings.remove(originalPath) == null) return;
  await prefs.setString(
    PreferencesKeys.kMissingPdfFileMappings,
    jsonEncode(mappings),
  );
}

Map<String, String> _missingPdfMappingsFromPrefs(SharedPreferences prefs) {
  final jsonData = prefs.getString(PreferencesKeys.kMissingPdfFileMappings);
  if (jsonData == null || jsonData.isEmpty) return {};

  try {
    final decoded = jsonDecode(jsonData);
    if (decoded is! Map) return {};
    return decoded.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  } catch (_) {
    return {};
  }
}
