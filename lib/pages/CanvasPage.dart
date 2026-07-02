import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/src/TransparentImage.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3, Vector4;
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/EditingToolbar.dart';
import 'package:xournalpp/widgets/MainDrawer.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';
import 'package:xournalpp/widgets/XppPagesListView.dart';
import 'package:xournalpp/widgets/ZoomableWidget.dart';

class CanvasPage extends StatefulWidget {
  CanvasPage({Key? key, this.file, this.filePath}) : super(key: key);

  final XppFile? file;
  final String? filePath;

  @override
  _CanvasPageState createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage> with TickerProviderStateMixin {
  static const int _defaultToolColor = 0xFF607D8B;
  static const int _defaultHighlighterColor = 0xFFFFFF00;
  static const Color _laserColor = Colors.redAccent;
  static const double _fitWidthHorizontalMargin = 50;
  static const double _penMinWidth = 0.1;
  static const double _penMaxWidth = 3;
  static const int _penWidthDivisions = 29;
  static const double _highlighterMinWidth = 5;
  static const double _highlighterMaxWidth = 50;
  static const int _highlighterWidthDivisions = 45;
  static const double _eraserMinWidth = 1;
  static const double _eraserMaxWidth = 20;
  static const int _eraserWidthDivisions = 19;

  XppFile? _file;
  String? filePath;

  int currentPage = 0;

  Color toolColor = Colors.blueGrey;
  Color highlighterColor = Colors.yellow;
  double toolWidth = 1;
  double highlighterWidth = 20;
  double eraserWidth = 20;

  TransformationController _zoomController = TransformationController();

  Map<PointerDeviceKind?, EditingTool> _toolData = {};
  PointerDeviceKind? _currentDevice = PointerDeviceKind.touch;

  /// used fro parent-child communication
  final GlobalKey<XppPageStackState> _pageStackKey = GlobalKey();
  final GlobalKey<EditingToolBarState> _editingToolbarKey = GlobalKey();
  final GlobalKey<PointerListenerState> _pointerListenerKey = GlobalKey();
  final GlobalKey<ZoomableWidgetState> _zoomableKey = GlobalKey();
  final GlobalKey<XppPagesListViewState> pageListViewKey = GlobalKey();

  double pageScale = 1;

  bool savingFile = false;

  _EraserContentIndex? _eraserIndex;
  final List<_UndoEntry> _undoStack = [];
  Set<XppContent> _selectedContents = {};

  Animation<Matrix4>? _animationReset;
  late AnimationController _controllerReset;

  @override
  void initState() {
    _setMetadata();
    super.initState();
    _controllerReset = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    loadToolSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: MainDrawer(),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: 'ZoomArea',
            child: ZoomableWidget(
              key: _zoomableKey,
              controller: _zoomController,
              onInteractionStart: _onInteractionStart,
              onInteractionUpdate: (details) {
                //print(details);
                _updatePageScale();
              },
              onTransformationChanged: _updatePageScale,
              child: Center(
                child: Card(
                  elevation: 12,
                  color: Colors.white,
                  child: AspectRatio(
                    aspectRatio: _file!.pages![currentPage].pageSize!.ratio,
                    child: FittedBox(
                      child: PointerListener(
                        key: _pointerListenerKey,
                        translationMatrix: _zoomController.value,
                        toolData: _toolData,
                        strokeWidth: toolWidth,
                        highlighterWidth: highlighterWidth,
                        eraserWidth: eraserWidth,
                        color: toolColor,
                        highlighterColor: highlighterColor,
                        laserColor: _laserColor,
                        onDeviceChange: _handleDeviceChange,
                        filterEraser: ({Offset? coordinates, double? radius}) {
                          _eraseContentAt(
                            coordinates: coordinates,
                            radius: radius,
                          );
                        },
                        filterEraserPath:
                            ({List<Offset>? coordinates, double? radius}) {
                              _eraseContentAlongPath(
                                coordinates: coordinates,
                                radius: radius,
                              );
                            },
                        onSelectionRegionChange: _selectRegion,
                        onSelectionClear: _clearSelection,
                        onNewContent: (newContent) {
                          if (newContent == null) return;

                          /// TODO: manage layers
                          final page = _file!.pages![currentPage];
                          final layer = page.layers![0];
                          setState(() {
                            final content = List<XppContent?>.from(
                              layer.content!,
                            )..add(newContent);
                            layer.content = content;
                            _undoStack.add(
                              _UndoEntry([
                                _LayerOperation.added(
                                  page: page,
                                  layer: layer,
                                  content: newContent,
                                  index: content.length - 1,
                                ),
                              ]),
                            );
                          });
                          _eraserIndex?.add(newContent);

                          _pageStackKey.currentState!.setPageData(page);
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: XppPageStack(
                            /// to communicate from [PointerListener] to [XppPageStack]
                            key: _pageStackKey,
                            page: _file!.pages![currentPage],
                            rasterScale: pageScale,
                            activeTool: _activeTool,
                            selectedContents: _selectedContents,
                            onSelectContent: _selectContent,
                            onReplaceContent: _replaceContent,
                            onContentPointerDown: (event) => _pointerListenerKey
                                .currentState
                                ?.markContentPointerDown(event),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            /*ColorFiltered(
                  colorFilter: ColorFilter.mode(
                      Theme.of(context).colorScheme.surface.withOpacity(.5),
                      BlendMode.darken),
                  child: child,
                )*/
          ),
        ],
      ),
      appBar: AppBar(
        toolbarHeight: kToolbarHeight,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onPrimary,
        ),
        actionsIconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onPrimary,
        ),
        elevation: 4,
        title: Tooltip(
          message: S.of(context).doubleTapToChange,
          child: GestureDetector(
            onDoubleTap: _showTitleDialog,
            child: Text(widget.file?.title ?? S.of(context).newDocument),
          ),
        ),
        actions: [
          _buildZoomControls(context),
          IconButton(
            icon: Icon(Icons.undo),
            onPressed: _canUndo ? _undoLastOperation : null,
            tooltip: 'Undo last operation',
          ),
          savingFile
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(
                        Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                )
              : IconButton(
                  icon: Icon(Icons.save),
                  onPressed: saveFile,
                  tooltip: S.of(context).save,
                ),
          PopupMenuButton<String>(
            onSelected: (item) async {
              if (item == S.of(context).saveAs) saveFile(export: true);
              if (item == S.of(context).sharePage) shareScreenshot();
            },
            itemBuilder: (BuildContext context) {
              return {
                S.of(context).saveAs,
                if (!kIsWeb) S.of(context).sharePage,
              }.map((String choice) {
                return PopupMenuItem<String>(
                  value: choice,
                  child: Text(choice),
                );
              }).toList();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(64),
          child: EditingToolBar(
            key: _editingToolbarKey,
            deviceMap: _toolData,
            getColor: getColor,
            getWidth: getWidth,
            getMinWidth: getMinWidth,
            getMaxWidth: getMaxWidth,
            getWidthDivisions: getWidthDivisions,
            onWidthChange: (newWidth, tool) {
              setState(() {
                if (tool == EditingTool.ERASER) {
                  eraserWidth = newWidth * 2;
                } else if (tool == EditingTool.HIGHLIGHT) {
                  highlighterWidth = newWidth;
                } else {
                  toolWidth =
                      newWidth *
                      2; // average pressure is 0.5, so multiplying by 2
                }
              });
              rememberToolSettings();
            },
            onColorChange: (newColor, tool) {
              setState(() {
                if (tool == EditingTool.HIGHLIGHT) {
                  highlighterColor = newColor;
                } else {
                  toolColor = newColor;
                }
              });
              rememberToolSettings();
            },
            onNewDeviceMap: (newDeviceMap) => setState(() {
              _toolData = newDeviceMap!;
              _setZoomableState();
              if (_activeTool != EditingTool.SELECT) {
                _selectedContents = {};
              }
            }),
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        shape: kIsWeb ? null : CircularNotchedRectangle(),
        child: Container(
          color: Theme.of(context).colorScheme.surface,
          constraints: BoxConstraints(maxHeight: 100),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              XppPagesListView(
                key: pageListViewKey,
                pages: _file!.pages,
                onPageChange: (newPage) {
                  setState(() {
                    currentPage = newPage;
                    _selectedContents = {};
                    _invalidateEraserIndex();
                  });
                  _pageStackKey.currentState!.setPageData(
                    _file!.pages![currentPage],
                  );
                },
                onPageDelete: (deletedIndex) => setState(() {
                  _file!.pages!.removeAt(deletedIndex);
                  _selectedContents = {};
                  _invalidateEraserIndex();
                  if (_file!.pages!.length >= currentPage)
                    currentPage = _file!.pages!.length - 1;
                  if (_file!.pages!.isEmpty) {
                    _file!.pages!.add(XppPage.empty(background: Colors.white));
                    currentPage = 0;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          S.of(context).thereWereNoMorePagesWeAddedOne,
                        ),
                      ),
                    );
                  }
                }),
                onPageMove: (initialIndex, movedTo) => setState(() {
                  final page = _file!.pages![initialIndex];
                  _file!.pages!.removeAt(initialIndex);
                  _file!.pages!.insert(movedTo - 1, page);
                  _selectedContents = {};
                  _invalidateEraserIndex();
                }),
                currentPage: currentPage,
              ),
              FloatingActionButton(
                heroTag: 'AddXppPage',
                onPressed: () => setState(() {
                  currentPage++;
                  _selectedContents = {};
                  _invalidateEraserIndex();
                  _file!.pages!.insert(
                    currentPage,
                    XppPage.empty(background: Colors.white),
                  );

                  _pageStackKey.currentState!.setPageData(
                    _file!.pages![currentPage],
                  );
                }),
                child: Icon(Icons.add),
                tooltip: S.of(context).addPage,
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: kIsWeb
          ? FloatingActionButtonLocation.centerFloat
          : FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            elevation: 16,
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            context: context,
            builder: (context) => ToolBoxBottomSheet(
              onBackgroundChange: (newBackground) {
                newBackground.size = _file!.pages![currentPage].pageSize;
                setState(
                  () => _file!.pages![currentPage].background = newBackground,
                );
              },
            ),
          );
        },
        tooltip: S.of(context).tools,
        child: Icon(Icons.format_paint),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  void _setMetadata() {
    _file = widget.file;
    filePath = widget.filePath;
  }

  Future<bool> _showTitleDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) {
            TextEditingController titleController = TextEditingController(
              text: _file!.title,
            );
            return AlertDialog(
              title: Text(S.of(context).setDocumentTitle),
              content: Padding(
                padding: const EdgeInsets.only(left: 8, right: 8),
                child: TextField(
                  autofocus: true,
                  controller: titleController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: S.of(context).newTitle,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(S.of(context).cancel),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _file!.title = titleController.text;
                    });
                    Navigator.of(context).pop(true);
                  },
                  child: Text(S.of(context).apply),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Widget _buildZoomControls(BuildContext context) {
    return Tooltip(
      message: '${(pageScale * 100).round()} %',
      child: SizedBox(
        height: 64,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.remove),
              color: Theme.of(context).colorScheme.onPrimary,
              onPressed: () {
                _setScale(pageScale - 0.1);
              },
            ),
            IconButton(
              icon: Icon(Icons.fit_screen),
              color: Theme.of(context).colorScheme.onPrimary,
              tooltip: 'Fit width',
              onPressed: _fitPageToWidth,
            ),
            IconButton(
              icon: Icon(Icons.add),
              color: Theme.of(context).colorScheme.onPrimary,
              onPressed: () {
                _setScale(pageScale + 0.1);
              },
            ),
          ],
        ),
      ),
    );
  }

  void setDefaultDeviceIfNotSet({PointerDeviceKind? kind}) {
    if (!_toolData.keys.contains(kind)) {
      EditingTool tool;
      switch (kind) {
        case PointerDeviceKind.touch:
          tool = EditingTool.MOVE;
          break;
        case PointerDeviceKind.invertedStylus:
          tool = EditingTool.ERASER;
          break;
        case PointerDeviceKind.stylus:
          tool = EditingTool.STYLUS;
          break;
        case PointerDeviceKind.mouse:
          tool = EditingTool.SELECT;
          break;
        default:
          tool = EditingTool.MOVE;
          break;
      }
      _toolData[kind] = tool;
    }
  }

  void _handleDeviceChange({int? device, PointerDeviceKind? kind}) {
    final hadDeviceTool = _toolData.keys.contains(kind);
    final deviceChanged = _currentDevice != kind;

    setDefaultDeviceIfNotSet(kind: kind);

    if (!deviceChanged && hadDeviceTool) return;

    setState(() {
      _currentDevice = kind;
      if (_activeTool != EditingTool.SELECT) {
        _selectedContents = {};
      }
    });
    _editingToolbarKey.currentState!.setState(() {
      _editingToolbarKey.currentState!.currentDevice = kind;
      _setZoomableState();
    });
  }

  void _setZoomableState() {
    final zoomEnabled =
        _toolData[_currentDevice] == null ||
        _toolData[_currentDevice] == EditingTool.MOVE;
    _zoomableKey.currentState!.setState(
      () => _zoomableKey.currentState!.enabled = zoomEnabled,
    );
    _pointerListenerKey.currentState!.setState(() {
      _pointerListenerKey.currentState!.drawingEnabled = !zoomEnabled;
    });
  }

  EditingTool? get _activeTool => _toolData[_currentDevice];

  void _updatePageScale() {
    setState(() => pageScale = _zoomController.value.getMaxScaleOnAxis());
  }

  void _setScale(double newZoom, {animate = true}) {
    newZoom = max(.1, min(5, newZoom));
    if (newZoom != pageScale) {
      pageScale = newZoom;
      final scaledMatrix = _scaleAroundViewportCenter(newZoom);
      if (animate) {
        _animateTransformation(scaledMatrix);
      } else {
        _zoomController.value = scaledMatrix;
      }
      setState(() {});
    }
  }

  Matrix4 _scaleAroundViewportCenter(double targetScale) {
    final viewportObject = _zoomableKey.currentContext?.findRenderObject();
    if (viewportObject is! RenderBox) {
      return _zoomController.value.clone()
        ..setDiagonal(Vector4(targetScale, targetScale, 1, 1));
    }

    final matrix = _zoomController.value;
    final currentScale = matrix.getMaxScaleOnAxis();
    if (currentScale <= 0) {
      return matrix.clone()
        ..setDiagonal(Vector4(targetScale, targetScale, 1, 1));
    }

    final scaleRatio = targetScale / currentScale;
    final focalPoint = viewportObject.size.center(Offset.zero);
    final currentX = matrix.entry(0, 3);
    final currentY = matrix.entry(1, 3);

    return Matrix4.identity()
      ..setDiagonal(Vector4(targetScale, targetScale, 1, 1))
      ..setTranslation(
        Vector3(
          focalPoint.dx - (focalPoint.dx - currentX) * scaleRatio,
          focalPoint.dy - (focalPoint.dy - currentY) * scaleRatio,
          0,
        ),
      );
  }

  void _fitPageToWidth() {
    final viewportObject = _zoomableKey.currentContext?.findRenderObject();
    final pageObject = _pageStackKey.currentContext?.findRenderObject();
    if (viewportObject is! RenderBox || pageObject is! RenderBox) return;

    final pageLeft = pageObject.localToGlobal(Offset.zero).dx;
    final pageRight = pageObject
        .localToGlobal(Offset(pageObject.size.width, 0))
        .dx;
    final currentPageWidth = (pageRight - pageLeft).abs();
    final currentScale = _zoomController.value.getMaxScaleOnAxis();
    if (currentPageWidth <= 0 || currentScale <= 0) return;

    final unzoomedPageWidth = currentPageWidth / currentScale;
    final targetWidth = max(
      1.0,
      viewportObject.size.width - _fitWidthHorizontalMargin * 2,
    );
    final targetScale = max(0.1, min(5.0, targetWidth / unzoomedPageWidth));
    final centeredTransform = Matrix4.identity()
      ..setDiagonal(Vector4(targetScale, targetScale, 1, 1))
      ..setTranslation(
        Vector3(
          viewportObject.size.width * (1 - targetScale) / 2,
          viewportObject.size.height * (1 - targetScale) / 2,
          0,
        ),
      );

    pageScale = targetScale;
    _animateTransformation(centeredTransform);
    setState(() {});
  }

  void _eraseContentAt({Offset? coordinates, double? radius}) {
    if (coordinates == null) return;
    _eraseContentAlongPath(coordinates: [coordinates], radius: radius);
  }

  bool get _canUndo => _undoStack.isNotEmpty;

  void _undoLastOperation() {
    if (_undoStack.isEmpty) return;

    final undoEntry = _undoStack.removeLast();
    setState(() {
      for (final operation in undoEntry.operations.reversed) {
        operation.undo();
      }
      _invalidateEraserIndex();
    });

    if (undoEntry.page == _file!.pages![currentPage]) {
      _pageStackKey.currentState!.setPageData(undoEntry.page);
    }
  }

  void _replaceContent(
    XppLayer layer,
    XppContent oldContent,
    XppContent newContent,
  ) {
    final page = _file!.pages![currentPage];
    final content = List<XppContent?>.from(layer.content ?? []);
    final index = content.indexWhere((item) => identical(item, oldContent));
    if (index == -1) return;

    setState(() {
      content[index] = newContent;
      layer.content = content;
      if (_selectedContents.contains(oldContent)) {
        _selectedContents = {
          ..._selectedContents.where(
            (content) => !identical(content, oldContent),
          ),
          newContent,
        };
      }
      _undoStack.add(
        _UndoEntry([
          _LayerOperation.removed(
            page: page,
            layer: layer,
            content: oldContent,
            index: index,
          ),
          _LayerOperation.added(
            page: page,
            layer: layer,
            content: newContent,
            index: index,
          ),
        ]),
      );
      _invalidateEraserIndex();
    });
    _pageStackKey.currentState!.setPageData(page);
  }

  void _selectContent(XppLayer _, XppContent content) {
    if (_activeTool != EditingTool.SELECT) return;
    setState(() => _selectedContents = {content});
  }

  void _selectRegion(Rect? region) {
    if (_activeTool != EditingTool.SELECT || region == null) return;

    final selected = <XppContent>{};
    for (final layer in _file!.pages![currentPage].layers ?? <XppLayer>[]) {
      for (final content in layer.content ?? <XppContent?>[]) {
        final bounds = content?.selectionBounds;
        if (content == null || bounds == null || bounds.isEmpty) continue;
        if (region.overlaps(bounds) || region.contains(bounds.center)) {
          selected.add(content);
        }
      }
    }

    setState(() => _selectedContents = selected);
  }

  void _clearSelection() {
    if (_activeTool != EditingTool.SELECT || _selectedContents.isEmpty) return;
    setState(() => _selectedContents = {});
  }

  void _eraseContentAlongPath({List<Offset>? coordinates, double? radius}) {
    if (coordinates == null || coordinates.isEmpty || radius == null) return;

    final page = _file!.pages![currentPage];
    final layer = page.layers![0];
    final eraserIndex = _eraserIndexForLayer(layer);
    final eraseCandidates = <XppContent>{};
    for (final coordinate in coordinates) {
      final eraserRect = Rect.fromCircle(
        center: coordinate,
        radius: radius / 2,
      );
      eraseCandidates.addAll(eraserIndex.query(eraserRect));
    }
    if (eraseCandidates.isEmpty) return;

    final List<XppContent?> updatedContent = [];
    final operations = <_LayerOperation>[];
    bool erasedAnything = false;

    for (var index = 0; index < layer.content!.length; index++) {
      final content = layer.content![index];
      if (content == null) {
        updatedContent.add(null);
        continue;
      }

      if (!eraseCandidates.contains(content)) {
        updatedContent.add(content);
        continue;
      }

      final delta = _eraseContentWithPath(
        content: content,
        coordinates: coordinates,
        radius: radius,
      );

      if (delta.affected) {
        erasedAnything = true;
        operations.add(
          _LayerOperation.removed(
            page: page,
            layer: layer,
            content: content,
            index: index,
          ),
        );
        eraserIndex.remove(content);
        for (final newContent in delta.newContent) {
          operations.add(
            _LayerOperation.added(
              page: page,
              layer: layer,
              content: newContent,
              index: updatedContent.length,
            ),
          );
          eraserIndex.add(newContent);
          updatedContent.add(newContent);
        }
      } else {
        updatedContent.add(content);
      }
    }

    if (!erasedAnything) return;

    layer.content = updatedContent;
    _undoStack.add(_UndoEntry(operations));
    _pageStackKey.currentState!.setPageData(page);
    setState(() {});
  }

  XppContentEraseData _eraseContentWithPath({
    required XppContent content,
    required List<Offset> coordinates,
    required double radius,
  }) {
    var remainingContent = <XppContent>[content];
    var affected = false;

    for (final coordinate in coordinates) {
      if (remainingContent.isEmpty) break;

      final nextContent = <XppContent>[];
      for (final currentContent in remainingContent) {
        final delta = currentContent.eraseWhere(
          coordinates: coordinate,
          radius: radius,
        );
        if (delta.affected) {
          affected = true;
          nextContent.addAll(delta.newContent);
        } else {
          nextContent.add(currentContent);
        }
      }
      remainingContent = nextContent;
    }

    if (!affected) return XppContentEraseData();

    return XppContentEraseData(
      affected: true,
      delete: remainingContent.isEmpty,
      newContent: remainingContent,
    );
  }

  _EraserContentIndex _eraserIndexForLayer(XppLayer layer) {
    return _eraserIndex ??= _EraserContentIndex.fromContent(layer.content);
  }

  void _invalidateEraserIndex() {
    _eraserIndex = null;
  }

  void shareScreenshot() async {
    Uint8List imageBytes = await pageListViewKey.currentState!.getPng(
      currentPage,
    );
    String fileName =
        await (XppPickedFile(
          imageBytes,
          fileExtension: '.png',
          path:
              '/export/' +
              (_file?.title ?? S.of(context).newFile) +
              ' ${currentPage + 1}' +
              '.png',
        ).exportToStorage()) ??
        (_file?.title ?? S.of(context).newFile);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).successfullyShared + ' ' + fileName),
      ),
    );
  }

  void saveFile({bool export = false}) async {
    setState(() {
      savingFile = true;
    });
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.clearSnackBars();
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(S.of(context).savingFile),
        duration: Duration(days: 999),
      ),
    );
    //try {
    if (_file!.title == null) {
      final titleApplied = await _showTitleDialog();
      if (!titleApplied || _file!.title == null) {
        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (mounted) {
          setState(() {
            savingFile = false;
          });
        }
        return;
      }
    }
    String path = export
        ? _file!.title! + '.xopp'
        : filePath ?? _file!.title! + '.xopp';
    _file!.previewImage = kIsWeb
        ? kTransparentImage
        : await pageListViewKey.currentState!.getPng(0);
    XppPickedFile file = _file!.toXppPickedFile(filePath: path);
    String? savedPath;
    if (export) {
      savedPath = await file.exportToStorage();
    } else {
      savedPath = await file.saveToPath(path: path);
    }
    if (savedPath == null) {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (mounted) {
        setState(() {
          savingFile = false;
        });
      }
      return;
    }
    filePath = savedPath;

    /// starting async task to save recent files list
    SharedPreferences.getInstance().then((prefs) {
      String jsonData = prefs.getString(PreferencesKeys.kRecentFiles) ?? '[]';
      Set files = (jsonDecode(jsonData) as Iterable).toSet();
      files.removeWhere((element) => element['path'] == savedPath);
      files.add({
        'preview': base64Encode(_file!.previewImage!),
        'name': _file!.title,
        'path': savedPath,
        'modified': DateTime.now().toIso8601String(),
      });
      jsonData = jsonEncode(files.toList());
      prefs.setString(PreferencesKeys.kRecentFiles, jsonData);
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      savingFile = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(S.of(context).successfullySaved)));
    /*} catch (e) {
      snackBarController.close();
      setState(() {
        savingFile = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(S.of(context).unfortunatelyThereWasAnErrorSavingThisFile),
        ),
      );
    }*/
  }

  void _onAnimationReset() {
    _zoomController.value = _animationReset!.value;
    if (!_controllerReset.isAnimating) {
      _animationReset?.removeListener(_onAnimationReset);
      _animationReset = null;
      _controllerReset.reset();
    }
  }

  void _animateTransformation(Matrix4 animateTo) {
    _controllerReset.reset();
    _animationReset = Matrix4Tween(
      begin: _zoomController.value,
      end: animateTo,
    ).animate(_controllerReset);
    _animationReset!.addListener(_onAnimationReset);
    _controllerReset.forward();
  }

  void _onInteractionStart(ScaleStartDetails details) {
    // If the user tries to cause a transformation while the reset animation is
    // running, cancel the reset animation.
    if (_controllerReset.status == AnimationStatus.forward) {
      _controllerReset.stop();
      _animationReset?.removeListener(_onAnimationReset);
      _animationReset = null;
      // assign animateTo value to skip to end
      // _zoomController.value = _animateTo;
    }
  }

  @override
  void dispose() {
    _controllerReset.dispose();
    super.dispose();
  }

  Color getColor(EditingTool? tool) {
    if (tool == EditingTool.HIGHLIGHT) {
      return highlighterColor;
    }
    if (tool == EditingTool.LASER) {
      return _laserColor;
    }
    return toolColor;
  }

  double getWidth(EditingTool? tool) {
    // average pressure is 0.5, so divide by 2
    // see L266
    if (tool == EditingTool.ERASER) {
      return eraserWidth / 2;
    }
    if (tool == EditingTool.HIGHLIGHT) {
      return highlighterWidth;
    }
    return toolWidth / 2;
  }

  double getMinWidth(EditingTool? tool) {
    if (tool == EditingTool.ERASER) {
      return _eraserMinWidth;
    }
    if (tool == EditingTool.HIGHLIGHT) {
      return _highlighterMinWidth;
    }
    return _penMinWidth;
  }

  double getMaxWidth(EditingTool? tool) {
    if (tool == EditingTool.ERASER) {
      return _eraserMaxWidth;
    }
    if (tool == EditingTool.HIGHLIGHT) {
      return _highlighterMaxWidth;
    }
    return _penMaxWidth;
  }

  int getWidthDivisions(EditingTool? tool) {
    if (tool == EditingTool.ERASER) {
      return _eraserWidthDivisions;
    }
    if (tool == EditingTool.HIGHLIGHT) {
      return _highlighterWidthDivisions;
    }
    return _penWidthDivisions;
  }

  void rememberToolSettings() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(PreferencesKeys.kToolColor, toolColor.toARGB32());
      prefs.setInt(
        PreferencesKeys.kHighlighterColor,
        highlighterColor.toARGB32(),
      );
      prefs.setDouble(PreferencesKeys.kToolWidth, toolWidth);
      prefs.setDouble(PreferencesKeys.kHighlighterWidth, highlighterWidth);
      prefs.setDouble(PreferencesKeys.kEraserWidth, eraserWidth);
    });
  }

  void loadToolSettings() {
    SharedPreferences.getInstance().then((prefs) {
      toolColor = Color(
        prefs.getInt(PreferencesKeys.kToolColor) ?? _defaultToolColor,
      );
      highlighterColor = Color(
        prefs.getInt(PreferencesKeys.kHighlighterColor) ??
            _defaultHighlighterColor,
      );
      toolWidth = prefs.getDouble(PreferencesKeys.kToolWidth) ?? toolWidth;
      highlighterWidth =
          prefs.getDouble(PreferencesKeys.kHighlighterWidth) ??
          highlighterWidth;
      eraserWidth =
          prefs.getDouble(PreferencesKeys.kEraserWidth) ?? eraserWidth;
    });
  }
}

class _UndoEntry {
  final List<_LayerOperation> operations;

  _UndoEntry(this.operations);

  XppPage get page => operations.first.page;
}

enum _LayerOperationType { added, removed }

class _LayerOperation {
  final XppPage page;
  final XppLayer layer;
  final XppContent content;
  final int index;
  final _LayerOperationType type;

  _LayerOperation._({
    required this.page,
    required this.layer,
    required this.content,
    required this.index,
    required this.type,
  });

  factory _LayerOperation.added({
    required XppPage page,
    required XppLayer layer,
    required XppContent content,
    required int index,
  }) {
    return _LayerOperation._(
      page: page,
      layer: layer,
      content: content,
      index: index,
      type: _LayerOperationType.added,
    );
  }

  factory _LayerOperation.removed({
    required XppPage page,
    required XppLayer layer,
    required XppContent content,
    required int index,
  }) {
    return _LayerOperation._(
      page: page,
      layer: layer,
      content: content,
      index: index,
      type: _LayerOperationType.removed,
    );
  }

  void undo() {
    switch (type) {
      case _LayerOperationType.added:
        _removeContent();
        break;
      case _LayerOperationType.removed:
        _restoreContent();
        break;
    }
  }

  void _removeContent() {
    final contentList = List<XppContent?>.from(layer.content ?? []);
    final contentIndex = contentList.indexWhere(
      (item) => identical(item, content),
    );
    if (contentIndex == -1) return;

    contentList.removeAt(contentIndex);
    layer.content = contentList;
  }

  void _restoreContent() {
    final contentList = List<XppContent?>.from(layer.content ?? []);
    if (contentList.any((item) => identical(item, content))) return;

    contentList.insert(index.clamp(0, contentList.length), content);
    layer.content = contentList;
  }
}

class _EraserContentIndex {
  static const double _cellSize = 96;

  final Map<_EraserIndexCell, Set<XppContent>> _cellContent = {};
  final Map<XppContent, Set<_EraserIndexCell>> _contentCells = {};

  _EraserContentIndex.fromContent(Iterable<XppContent?>? content) {
    if (content == null) return;
    for (final item in content) {
      add(item);
    }
  }

  void add(XppContent? content) {
    final bounds = content?.eraseBounds;
    if (content == null || bounds == null || bounds.isEmpty) return;

    final cells = _cellsForRect(bounds);
    _contentCells[content] = cells;
    for (final cell in cells) {
      (_cellContent[cell] ??= <XppContent>{}).add(content);
    }
  }

  void remove(XppContent content) {
    final cells = _contentCells.remove(content);
    if (cells == null) return;

    for (final cell in cells) {
      final contentForCell = _cellContent[cell];
      if (contentForCell == null) continue;
      contentForCell.remove(content);
      if (contentForCell.isEmpty) _cellContent.remove(cell);
    }
  }

  Set<XppContent> query(Rect rect) {
    final candidates = <XppContent>{};
    final hitSlop = rect.width / 2;
    for (final cell in _cellsForRect(rect)) {
      final contentForCell = _cellContent[cell];
      if (contentForCell == null) continue;
      for (final content in contentForCell) {
        final bounds = content.eraseBounds;
        if (bounds != null && bounds.inflate(hitSlop).contains(rect.center)) {
          candidates.add(content);
        }
      }
    }
    return candidates;
  }

  Set<_EraserIndexCell> _cellsForRect(Rect rect) {
    final left = (rect.left / _cellSize).floor();
    final right = (rect.right / _cellSize).floor();
    final top = (rect.top / _cellSize).floor();
    final bottom = (rect.bottom / _cellSize).floor();
    final cells = <_EraserIndexCell>{};

    for (var x = left; x <= right; x++) {
      for (var y = top; y <= bottom; y++) {
        cells.add(_EraserIndexCell(x, y));
      }
    }
    return cells;
  }
}

class _EraserIndexCell {
  final int x;
  final int y;

  const _EraserIndexCell(this.x, this.y);

  @override
  bool operator ==(Object other) {
    return other is _EraserIndexCell && other.x == x && other.y == y;
  }

  @override
  int get hashCode => Object.hash(x, y);
}
