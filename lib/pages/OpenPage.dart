import 'dart:convert';

import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppFile.dart';
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

  @override
  void dispose() {
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

    SharedPreferences.getInstance()
        .then((prefs) {
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
          print('No SharedPreferences available for this platform.');
          setState(() {
            _loadedRecent = true;
          });
        });
    super.initState();
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
      ReceiveSharingIntent.instance.getMediaStream().listen(
        (List<SharedMediaFile> value) {
          setState(() {
            receivedShareNotification(value);
          });
        },
        onError: (err) {
          print("getIntentDataStream error: $err");
        },
      );

      // For sharing images coming from outside the app while the app is closed
      ReceiveSharingIntent.instance
          .getInitialMedia()
          .then((List<SharedMediaFile> value) {
            setState(() {
              receivedShareNotification(value);
            });
          })
          .catchError((e) {});
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      onDrawerChanged: (opened) {
        _animationController.animateTo(opened ? 1 : 0);
      },
      drawer: MainDrawer(),
      appBar: AppBar(
        title: Text('Xournal++'),
        leading: Builder(
          builder: (context) => IconButton(
            onPressed: () {
              if (!Scaffold.of(context).isDrawerOpen) {
                Scaffold.of(context).openDrawer();
                _animationController.animateTo(1);
              }
            },
            tooltip: S.of(context).openNavigation,
            icon: AnimatedIcon(
              icon: AnimatedIcons.menu_arrow,
              progress: _animationController,
            ),
          ),
        ),
      ),
      body: ListView(
        children:
            [
              if (kIsWeb) DropFile(),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Builder(
                  builder: (context) => GestureDetector(
                    onTap: () => XppFile.openAndEdit(context: context),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Card(
                        color: Theme.of(context).colorScheme.secondary,
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.folder,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSecondary,
                                ),
                                Text(S.of(context).open),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.picture_as_pdf),
                onTap: () async {
                  final _file = await runWithLoadingFileDialog(
                    context,
                    () async {
                      final pdf = await XppPickedFile.importFromStorage(
                        type: XppFilePickType.custom,
                        fileExtension: 'pdf',
                      );
                      final file = await XppFile.importPdf(pdf: pdf);
                      if (context.mounted)
                        await file.prepareForOpening(context);
                      return file;
                    },
                  ); // TODO `.pdf`
                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (c) => CanvasPage(file: _file)),
                  );
                },
                title: Text(S.of(context).importPdf),
              ),
              ListTile(
                title: Text(
                  S.of(context).recentFiles,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ]..addAll(
              _loadedRecent
                  ? generateRecentFileList(recentFiles, context)
                  : [Center(child: CircularProgressIndicator())],
            ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                CanvasPage(file: XppFile.empty(background: Colors.white)),
          ),
        ),
        label: Text(S.of(context).newNotebook),
        icon: Icon(Icons.note_add),
      ),
    );
  }

  Future<void> receivedShareNotification(dynamic data) async {
    if (data == null ||
        lastIntentData == data ||
        data is List &&
            data.isNotEmpty &&
            lastIntentData is List &&
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
      if (context.mounted) await file.prepareForOpening(context);
      if (_aborted || !context.mounted) return;
      if (_dialogVisible) Navigator.of(context, rootNavigator: true).pop();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => CanvasPage(file: file, filePath: filePath),
        ),
      );
    } catch (e) {
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

  Iterable<Widget> generateRecentFileList(Set files, BuildContext context) {
    return List.generate(files.length > 0 ? files.length : 1, (index) {
      if (files.length > 0) {
        Map fileInfo = files.toList()[index];
        final displayName = _decodeFileInfoForDisplay(fileInfo['name']);
        final displayPath = _decodeFileInfoForDisplay(fileInfo['path']);
        final displayModified = _formatModifiedForDisplay(
          context,
          fileInfo['modified'],
        );
        return ListTile(
          isThreeLine: true,
          title: Text(
            displayName,
            style: Theme.of(context).textTheme.bodyLarge!.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: kLargeFontSize,
            ),
          ),
          leading: AspectRatio(
            aspectRatio: 1,
            child: Container(
              alignment: Alignment.center,
              constraints: BoxConstraints(maxHeight: 256, minHeight: 128),
              child: Image.memory(base64Decode(fileInfo['preview'])),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          subtitle: Text(
            displayModified,
            style: Theme.of(context).textTheme.bodySmall!,
          ),
          trailing: Tooltip(
            child: Icon(Icons.info_outline),
            message: displayPath,
          ),
          onLongPress: () => showDeleteDialog(fileInfo['path']),
          onTap: () async {
            try {
              final initialPage = _currentPageFromRecentFile(fileInfo);
              final file = await runWithLoadingFileDialog(context, () async {
                final file = await XppFile.fromXppPickedFile(
                  await XppPickedFile.fromInternalPath(path: fileInfo['path']),
                  (percent) {},
                  showMissingFileDialog,
                );
                if (context.mounted) {
                  await file.prepareForOpening(
                    context,
                    currentPage: initialPage,
                  );
                }
                return file;
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
              setState(() {
                recentFiles.removeWhere(
                  (element) => element['path'] == fileInfo['path'],
                );
              });
              SharedPreferences.getInstance().then((prefs) {
                prefs.setString(
                  PreferencesKeys.kRecentFiles,
                  jsonEncode(recentFiles.toList()),
                );
              });
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(S.of(context).errorOpeningFile + e.toString()),
                ),
              );
            }
          },
        );
      } else {
        return ListTile(
          leading: Icon(Icons.info),
          title: Text(S.of(context).noRecentFiles),
          trailing: IconButton(
            icon: Icon(Icons.note_add),
            tooltip: S.of(context).newNotebook,
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (context) => CanvasPage())),
          ),
        );
      }
    });
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
    return 'Last modified: ${DateFormat.yMd(locale).add_Hm().format(modified)}';
  }

  int _currentPageFromRecentFile(Map fileInfo) {
    final page = fileInfo['currentPage'];
    if (page is int) return page < 0 ? 0 : page;
    return int.tryParse(page?.toString() ?? '') ?? 0;
  }

  showDeleteDialog(path) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).confirmDelete),
        content: Text(
          S.of(context).areYouSureToDeleteTheSelectedFileThisCannot,
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: Text(S.of(context).cancel),
          ),
          TextButton(
            onPressed: () async {
              XppPickedFile.delete(path: path);
              setState(() {
                recentFiles.removeWhere((element) => element['path'] == path);
              });

              Navigator.of(context).pop();
              SharedPreferences.getInstance().then((prefs) {
                prefs.setString(
                  PreferencesKeys.kRecentFiles,
                  jsonEncode(recentFiles.toList()),
                );
              });
            },
            child: Text(S.of(context).delete),
          ),
        ],
      ),
    );
  }
}

final Map<String, Future<XppPickedFile>> _missingFileSelections = {};

Future<XppPickedFile> showMissingFileDialog(
  BuildContext context,
  String? path,
) async {
  final cacheKey = path ?? '__missing_pdf__';
  final existingSelection = _missingFileSelections[cacheKey];
  if (existingSelection != null) return existingSelection;

  late Future<XppPickedFile> selection;
  selection = _resolveMissingPdfFile(context, path).catchError((error) {
    if (identical(_missingFileSelections[cacheKey], selection)) {
      _missingFileSelections.remove(cacheKey);
    }
    throw error;
  });
  _missingFileSelections[cacheKey] = selection;
  return selection;
}

Future<XppPickedFile> _resolveMissingPdfFile(
  BuildContext context,
  String? path,
) async {
  final mappedPath = await _mappedMissingPdfPath(path);
  if (mappedPath != null) {
    try {
      return await XppPickedFile.fromInternalPath(path: mappedPath);
    } catch (_) {
      await _forgetMissingPdfMapping(path);
    }
  }

  final file = await _pickMissingPdfFile(context, path);
  await _rememberMissingPdfMapping(path, file.path);
  return file;
}

Future<XppPickedFile> _pickMissingPdfFile(
  BuildContext context,
  String? path,
) async {
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
