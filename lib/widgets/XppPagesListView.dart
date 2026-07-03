import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/src/PdfImage.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:xournalpp/widgets/ContextualBottomSheet.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';

class XppPagesListView extends StatefulWidget {
  final List<XppPage>? pages;
  final Function(int pageNumber)? onPageChange;
  final Function(int pageNumber)? onPageDelete;
  final Function(int pageNumber, int newIndex)? onPageMove;
  final int currentPage;

  const XppPagesListView({
    Key? key,
    this.pages,
    this.onPageChange,
    this.currentPage = 0,
    this.onPageDelete,
    this.onPageMove,
  }) : super(key: key);

  @override
  XppPagesListViewState createState() => XppPagesListViewState();
}

class XppPagesListViewState extends State<XppPagesListView> {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemBuilder: (c, i) {
        final page = widget.pages![i];
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Center(
            child: GestureDetector(
              onTap: () {
                //setState(() => widget.currentPage = i);
                widget.onPageChange!(i);
              },
              onSecondaryTap: () => showContext(i),
              onLongPress: () => showContext(i),
              child: Card(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: (widget.currentPage == i)
                        ? Border.all(color: Colors.red)
                        : Border.all(color: Color.fromARGB(1, 0, 0, 0)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: AspectRatio(
                      aspectRatio: page.pageSize!.ratio,
                      child: FittedBox(child: _PageThumbnail(page: page)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      itemCount: widget.pages!.length,
      scrollDirection: Axis.horizontal,
      primary: false,
      // ignore: deprecated_member_use
      cacheExtent: 0,
      addAutomaticKeepAlives: false,
    );
  }

  showContext(int i) => showModalBottomSheet(
    backgroundColor: Colors.transparent,
    context: context,
    builder: (context) => ContextualBottomSheet(
      children: [
        ListTile(
          title: Text(S.of(context).deletePage),
          leading: Icon(Icons.delete_forever),
          onTap: () {
            widget.onPageDelete!(i);
            Navigator.of(context).pop();
          },
        ),
        ListTile(
          title: Text(S.of(context).movePage + '...'),
          leading: Icon(Icons.open_with),
          onTap: () async {
            int newIndex = i;
            if (await (showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(S.of(context).movePage + ' $i'),
                    content: TextField(
                      onChanged: (string) => newIndex = int.parse(string),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: S.of(context).newPageIndex,
                        helperText:
                            S.of(context).between1And +
                            ' ${widget.pages!.length}.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        child: Text(S.of(context).cancel),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      TextButton(
                        child: Text(S.of(context).okay),
                        onPressed: () {
                          if (newIndex <= widget.pages!.length)
                            Navigator.of(context).pop(true);
                        },
                      ),
                    ],
                  ),
                )
                as FutureOr<bool>)) {
              widget.onPageMove!(i, newIndex);
            }
            Navigator.of(context).pop();
          },
        ),
      ],
    ),
  );
}

class _PageThumbnail extends StatelessWidget {
  final XppPage page;

  const _PageThumbnail({required this.page});

  @override
  Widget build(BuildContext context) {
    final background = page.background;
    if (background is XppBackgroundPdf) {
      return _PdfPageThumbnail(page: page, background: background);
    }

    return IgnorePointer(
      child: XppPageStack(page: page, rasterScale: .25, keepAlive: false),
    );
  }
}

class _PdfPageThumbnail extends StatefulWidget {
  final XppPage page;
  final XppBackgroundPdf background;

  const _PdfPageThumbnail({required this.page, required this.background});

  @override
  State<_PdfPageThumbnail> createState() => _PdfPageThumbnailState();
}

class _PdfPageThumbnailState extends State<_PdfPageThumbnail> {
  Future<Uint8List>? _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = _loadPdfThumbnail();
  }

  @override
  void didUpdateWidget(covariant _PdfPageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.background != oldWidget.background) {
      _imageFuture = _loadPdfThumbnail();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageSize = widget.page.pageSize!.toSize();
    return IgnorePointer(
      child: SizedBox(
        width: pageSize.width,
        height: pageSize.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder(
              future: _imageFuture,
              builder: (context, AsyncSnapshot<Uint8List> snapshot) {
                if (snapshot.hasData) {
                  return Image.memory(snapshot.data!, fit: BoxFit.fill);
                }
                return const ColoredBox(color: Colors.white);
              },
            ),
            ...widget.page.layers!.map(
              (layer) => XppLayerStack(
                layer: layer,
                pageSize: pageSize,
                rasterScale: .25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List> _loadPdfThumbnail() async {
    final filename = widget.background.filename;
    if (filename != null && filename.isNotEmpty) {
      try {
        final file = await XppPickedFile.fromInternalPath(path: filename);
        return pdfThumbnailImage(file, widget.background.page);
      } catch (_) {
        // Fall through to the missing-file callback below.
      }
    }

    final file = await widget.background.onUnavailable(context, filename);
    return pdfThumbnailImage(file, widget.background.page);
  }
}
