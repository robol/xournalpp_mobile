import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/widgets/LoadingFileDialog.dart';

class DropFile extends StatefulWidget {
  @override
  _DropFileState createState() => _DropFileState();
}

class _DropFileState extends State<DropFile> {
  late DropzoneViewController _fileDropController;

  bool _fileHover = false;
  bool _loadingDropZone = true;

  Future<void> _openDroppedFile(dynamic droppedFile) async {
    setState(() {
      _fileHover = false;
      _loadingDropZone = true;
    });

    String? filename;
    try {
      filename = await _fileDropController.getFilename(droppedFile);
      final bytes = await _fileDropController.getFileData(droppedFile);
      if (!mounted) return;
      final file = await runWithLoadingFileDialog(context, () async {
        return XppFile.fromXppPickedFile(
          XppPickedFile(bytes, path: filename, fileExtension: 'xopp'),
          (percentage) {},
          showMissingFileDialog,
        );
      });
      if (!mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (context) => CanvasPage(file: file)));
    } catch (error) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(S.of(context).errorOpeningFile),
          content: SelectableText(
            '${S.of(context).imVerySorryButICouldntReadTheFile}'
            '${filename ?? ''}'
            '${S.of(context).areYouSureIHaveThePermissionAndAreYou}'
            '\n$error',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: error.toString())),
              child: Text(S.of(context).copyErrorMessage),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).okay),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingDropZone = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Card(
        child: AnimatedContainer(
          duration: Duration(milliseconds: 250),
          constraints: BoxConstraints(maxHeight: 256),
          child: Stack(
            children: [
              Builder(
                builder: (context) => DropzoneView(
                  onDropFile: _openDroppedFile,
                  onHover: () {
                    if (mounted) setState(() => _fileHover = true);
                  },
                  onLeave: () {
                    if (mounted) setState(() => _fileHover = false);
                  },
                  onLoaded: () {
                    if (mounted) setState(() => _loadingDropZone = false);
                  },
                  onError: (message) {
                    if (!mounted) return;
                    final errorMessage = message ?? '';
                    setState(() {
                      _fileHover = false;
                      _loadingDropZone = false;
                    });
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(S.of(context).errorLoadingFile),
                        actions: [
                          TextButton(
                            onPressed: () => Clipboard.setData(
                              ClipboardData(text: errorMessage),
                            ),
                            child: Text(S.of(context).copyErrorMessage),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(S.of(context).okay),
                          ),
                        ],
                        content: Text(
                          S.of(context).theFollowingErrorWasDetected +
                              '\n' +
                              errorMessage,
                        ),
                      ),
                    );
                  },
                  onCreated: (controller) {
                    _fileDropController = controller;
                  },
                  operation: DragOperation.all,
                  //mime: ['application/x-xopp'],
                ),
              ),
              Center(
                child: _loadingDropZone
                    ? CircularProgressIndicator()
                    : DefaultTextStyle.merge(
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.open_with,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                            Text(S.of(context).dropFilesToOpen),
                          ],
                          mainAxisAlignment: MainAxisAlignment.center,
                        ),
                      ),
              ),
            ],
          ),
          decoration: BoxDecoration(
            color: _fileHover
                ? Theme.of(context).colorScheme.secondary
                : Theme.of(context).colorScheme.surface,
            border: _fileHover
                ? Border.all(color: Theme.of(context).primaryColor, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
          ),
        ),
      ),
    );
  }
}
