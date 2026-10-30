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
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:xournalpp/src/NextcloudManager.dart';
import 'package:xournalpp/src/NextcloudStorage.dart';
import 'package:xournalpp/src/DraftRecovery.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/DropFile.dart';
import 'package:xournalpp/widgets/LoadingFileDialog.dart';
import 'package:xournalpp/widgets/MainDrawer.dart';

class OpenPage extends StatefulWidget {
  final dynamic initialExternalIntent;

  const OpenPage({super.key, this.initialExternalIntent});

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
      if (!mounted) return;
      if (widget.initialExternalIntent != null) {
        unawaited(receivedShareNotification(widget.initialExternalIntent));
      } else {
        afterFirstLayout(context);
        unawaited(_offerRecovery());
      }
    });

    RecentFiles.changes.addListener(_loadRecentFiles);
    unawaited(
      NextcloudManager.restore().catchError((Object error) {
        debugPrint('Could not restore Nextcloud: $error');
      }),
    );
    _loadRecentFiles();
    super.initState();
  }

  Future<void> _offerRecovery() async {
    if (kIsWeb) return;
    List<RecoveryDraft> drafts;
    try {
      drafts = await DraftRecovery.list();
    } catch (error) {
      debugPrint('Could not list recovery drafts: $error');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(S.of(context).recoveryLoadFailed)),
        );
      }
      return;
    }
    if (!mounted || drafts.isEmpty || ModalRoute.of(context)?.isCurrent != true)
      return;
    while (mounted && drafts.isNotEmpty) {
      final draft = drafts.last;
      final choice = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(S.of(dialogContext).recoveryTitle),
          content: Text(
            S
                .of(dialogContext)
                .recoveryMessage(
                  draft.title ?? S.of(dialogContext).newDocument,
                ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(S.of(dialogContext).recoveryLater),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(S.of(dialogContext).recoveryDiscard),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(S.of(dialogContext).recoveryOpen),
            ),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      if (!choice) {
        try {
          await DraftRecovery.remove(draft.id);
          drafts.removeLast();
        } catch (error) {
          debugPrint('Could not discard recovery draft: $error');
          return;
        }
        continue;
      }
      try {
        final file = await XppFile.fromXppPickedFile(
          XppPickedFile(
            draft.bytes,
            fileName: '${draft.title ?? 'Untitled'}.xopp',
          ),
          null,
          showMissingFileDialog,
        );
        file.title = draft.title;
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CanvasPage(
              file: file,
              initialPage: draft.page,
              recoveryDraftId: draft.id,
              recoveryOriginalPath: draft.originalPath,
            ),
          ),
        );
        if (!mounted) return;
        drafts = await DraftRecovery.list();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.of(context).errorOpeningFile}$error')),
        );
        return;
      }
    }
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
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
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
        title: const Text('Xournal++ Mobile'),
        actions: [
          IconButton(
            tooltip: S.of(context).savedNotebooks,
            icon: const Icon(Icons.folder_outlined),
            onPressed: _showSavedNotebooks,
          ),
        ],
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
                              onOpen: _openNotebook,
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
      lastIntentData = token;
      await _openExternalFile(
        uri,
        mimeType: data['mimeType']?.toString(),
        displayName: data['displayName']?.toString(),
        writable: data['writable'] == true,
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
    bool writable = true,
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
      var pickedFile = await XppPickedFile.fromExternalPath(
        path: path,
        fileName: displayName,
        fileExtension: extension,
      );
      final XppFile file;
      final String? filePath;
      var initialPage = 0;
      if (extension == 'pdf') {
        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android &&
            path.startsWith('content://')) {
          final persistentPath = await pickedFile.saveToPersistentPath();
          pickedFile = XppPickedFile(
            pickedFile.bytes,
            path: persistentPath,
            fileName: pickedFile.fileName,
            fileExtension: 'pdf',
          );
        }
        file = await XppFile.importPdf(pdf: pickedFile);
        filePath = null;
      } else {
        file = await XppFile.fromXppPickedFile(
          pickedFile,
          (percentage) => null,
          showMissingFileDialog,
        );
        filePath = writable ? pickedFile.path : null;
        if (filePath != null) {
          initialPage = await XppFile.lastOpenedPageForPath(filePath);
        }
      }
      if (_aborted || !context.mounted) {
        if (_aborted) lastIntentData = null;
        return;
      }
      if (_dialogVisible) Navigator.of(context, rootNavigator: true).pop();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => CanvasPage(
            file: file,
            filePath: filePath,
            initialPage: initialPage,
          ),
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
      onLongPress: () =>
          showDeleteDialog(fileInfo['path'], backendId: fileInfo['backendId']),
      onOpen: () async {
        try {
          final initialPage = _currentPageFromRecentFile(fileInfo);
          final file = await runWithLoadingFileDialog(context, () async {
            final backendId = fileInfo['backendId'] as String?;
            if (backendId != null && backendId != localNotebookStorage.id) {
              await NextcloudManager.restore();
              final backend = notebookStorageBackends
                  .where((storage) => storage.id == backendId)
                  .firstOrNull;
              if (backend == null)
                throw StateError(S.of(context).recentBackendUnavailable);
              return XppFile.openStoredNotebook(
                backend,
                StoredNotebook(
                  backendId: backendId,
                  id: fileInfo['path'],
                  name: fileInfo['name'],
                ),
                showMissingFileDialog,
              );
            }
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

  Future<void> _openNotebook() async {
    try {
      await NextcloudManager.restore();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.of(context).errorOpeningFile}$error')),
      );
      return;
    }
    if (!mounted) return;
    NotebookStorage? selected = localNotebookStorage;
    if (notebookStorageBackends.length > 1) {
      selected = await showDialog<NotebookStorage>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(S.of(dialogContext).storageBackend),
          children: notebookStorageBackends
              .map(
                (backend) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, backend),
                  child: Text(
                    backend == localNotebookStorage
                        ? S.of(dialogContext).localStorage
                        : backend.id.startsWith('nextcloud:')
                        ? 'Nextcloud'
                        : backend.id,
                  ),
                ),
              )
              .toList(),
        ),
      );
    }
    if (!mounted || selected == null) return;
    if (selected == localNotebookStorage) {
      XppFile.openAndEdit(context: context);
    } else {
      await _showSavedNotebooks(initialBackend: selected);
    }
  }

  Future<void> _showSavedNotebooks({NotebookStorage? initialBackend}) async {
    NotebookStorage selected = initialBackend ?? localNotebookStorage;
    var folder = <String>[];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(S.of(context).savedNotebooks),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<NotebookStorage>(
                  value: selected,
                  items: notebookStorageBackends
                      .map(
                        (backend) => DropdownMenuItem(
                          value: backend,
                          child: Text(
                            backend == localNotebookStorage
                                ? S.of(context).localStorage
                                : backend.id.startsWith('nextcloud:')
                                ? 'Nextcloud'
                                : backend.id,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (backend) {
                    if (backend != null)
                      setDialogState(() {
                        selected = backend;
                        folder = [];
                      });
                  },
                ),
                Flexible(
                  child: ValueListenableBuilder<int>(
                    valueListenable: LocalNotebookStorage.changes,
                    builder: (context, _, __) => FutureBuilder<NextcloudFolderListing>(
                      key: ValueKey('${selected.id}:${jsonEncode(folder)}'),
                      future: selected is NextcloudStorage
                          ? (selected as NextcloudStorage).listFolder(folder)
                          : selected.list().then(
                              (items) => NextcloudFolderListing(
                                folders: const [],
                                notebooks: items.reversed.toList(),
                              ),
                            ),
                      builder: (context, snapshot) {
                        if (snapshot.hasError)
                          return Text(
                            '${S.of(context).errorOpeningFile}${snapshot.error}',
                          );
                        if (!snapshot.hasData)
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        final entries = snapshot.data!.notebooks;
                        final folders = snapshot.data!.folders;
                        if (entries.isEmpty &&
                            folders.isEmpty &&
                            folder.isEmpty)
                          return Text(S.of(context).noSavedNotebooks);
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount:
                              entries.length +
                              folders.length +
                              (folder.isEmpty ? 0 : 1),
                          itemBuilder: (context, index) {
                            if (folder.isNotEmpty) {
                              if (index == 0)
                                return ListTile(
                                  leading: const Icon(Icons.arrow_upward),
                                  title: Text(
                                    S.of(context).nextcloudParentFolder,
                                  ),
                                  onTap: () => setDialogState(
                                    () => folder = folder.sublist(
                                      0,
                                      folder.length - 1,
                                    ),
                                  ),
                                );
                              index--;
                            }
                            if (index < folders.length) {
                              final name = folders[index];
                              return ListTile(
                                leading: const Icon(Icons.folder_outlined),
                                title: Text(name),
                                onTap: () => setDialogState(
                                  () => folder = [...folder, name],
                                ),
                              );
                            }
                            final entry = entries[index - folders.length];
                            return ListTile(
                              title: Text(entry.name),
                              trailing: selected != localNotebookStorage
                                  ? null
                                  : IconButton(
                                      tooltip: S
                                          .of(context)
                                          .removeSavedNotebook,
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                      onPressed: () async {
                                        try {
                                          await selected.forget(entry);
                                        } catch (error) {
                                          if (context.mounted)
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(error.toString()),
                                              ),
                                            );
                                        }
                                      },
                                    ),
                              onTap: () async {
                                try {
                                  final file = await XppFile.openStoredNotebook(
                                    selected,
                                    entry,
                                    showMissingFileDialog,
                                  );
                                  if (!dialogContext.mounted ||
                                      !this.context.mounted)
                                    return;
                                  Navigator.of(dialogContext).pop();
                                  await Navigator.of(this.context).push(
                                    MaterialPageRoute(
                                      builder: (_) => CanvasPage(
                                        file: file,
                                        filePath: entry.id,
                                      ),
                                    ),
                                  );
                                } catch (error) {
                                  if (context.mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '${S.of(context).errorOpeningFile}$error',
                                        ),
                                      ),
                                    );
                                }
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(S.of(context).close),
            ),
          ],
        ),
      ),
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

  showDeleteDialog(String path, {String? backendId}) {
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
                if ((backendId == null ||
                        backendId == localNotebookStorage.id) &&
                    XppPickedFile.canDelete(path: path))
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
                  await RecentFiles.forget(path, backendId: backendId);
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
