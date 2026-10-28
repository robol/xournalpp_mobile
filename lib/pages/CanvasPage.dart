import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:xournalpp/src/ContentSpatialIndex.dart';
import 'package:xournalpp/src/PageGeometry.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';

import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:xournalpp/src/RecentFiles.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xournalpp/src/TransparentImage.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/src/PdfBackgroundRenderService.dart';
import 'package:xournalpp/src/PdfExporter.dart';
import 'package:xournalpp/src/PdfImage.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/EditingToolbar.dart';
import 'package:xournalpp/widgets/LoadingFileDialog.dart';
import 'package:xournalpp/widgets/MainDrawer.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';
import 'package:xournalpp/widgets/XppPagesBrowser.dart';

@visibleForTesting
String annotatedPdfFileName(String title) {
  final baseName = title.replaceFirst(
    RegExp(r'\.(?:xopp|pdf)$', caseSensitive: false),
    '',
  );
  return '${baseName}_annotated.pdf';
}

@visibleForTesting
List<({XppLayer layer, XppContent content, int index})>
duplicateSelectedContents(
  XppPage page,
  Set<XppContent> selectedContents, {
  Offset offset = const Offset(12, 12),
}) {
  final duplicates = <({XppLayer layer, XppContent content, int index})>[];

  for (final layer in page.layers ?? <XppLayer>[]) {
    final content = layer.content ?? <XppContent?>[];
    final updatedContent = <XppContent?>[];
    var duplicatedFromLayer = false;

    for (final item in content) {
      updatedContent.add(item);
      if (item == null || !selectedContents.contains(item)) continue;

      final duplicate = item.translatedBy(offset);
      final duplicateIndex = updatedContent.length;
      updatedContent.add(duplicate);
      duplicates.add((layer: layer, content: duplicate, index: duplicateIndex));
      duplicatedFromLayer = true;
    }

    if (duplicatedFromLayer) layer.content = updatedContent;
  }

  return duplicates;
}

@visibleForTesting
List<({XppLayer layer, XppContent content, int index})> pasteCopiedContents(
  XppPage page,
  List<({XppLayer layer, XppContent content})> copiedContents, {
  Offset offset = const Offset(12, 12),
}) {
  final pasted = <({XppLayer layer, XppContent content, int index})>[];

  for (final layer in page.layers ?? <XppLayer>[]) {
    final layerCopies = copiedContents.where(
      (copied) => identical(copied.layer, layer),
    );
    if (layerCopies.isEmpty) continue;

    final updatedContent = List<XppContent?>.from(
      layer.content ?? <XppContent?>[],
    );
    for (final copied in layerCopies) {
      final content = copied.content.translatedBy(offset);
      final index = updatedContent.length;
      updatedContent.add(content);
      pasted.add((layer: layer, content: content, index: index));
    }
    layer.content = updatedContent;
  }

  return pasted;
}

@visibleForTesting
Offset pasteOffsetForVisiblePage(
  Rect copiedBounds,
  Rect visiblePageBounds,
  Rect pageBounds,
) {
  final left = (visiblePageBounds.center.dx - copiedBounds.width / 2).clamp(
    pageBounds.left,
    max(pageBounds.left, pageBounds.right - copiedBounds.width),
  );
  final top = (visiblePageBounds.center.dy - copiedBounds.height / 2).clamp(
    pageBounds.top,
    max(pageBounds.top, pageBounds.bottom - copiedBounds.height),
  );
  return Offset(left - copiedBounds.left, top - copiedBounds.top);
}

@visibleForTesting
void resizePageForPdfIfEmpty(XppPage page, XppPageSize pdfSize) {
  final hasContent =
      page.layers?.any(
        (layer) => layer.content?.any((content) => content != null) ?? false,
      ) ??
      false;
  if (!hasContent) page.pageSize = pdfSize;
}

class CanvasPage extends StatefulWidget {
  CanvasPage({
    Key? key,
    this.file,
    this.filePath,
    this.initialPage = 0,
    this.pdfRenderService,
  }) : super(key: key);

  final XppFile? file;
  final String? filePath;
  final int initialPage;
  final PdfBackgroundRenderService? pdfRenderService;

  @override
  _CanvasPageState createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage> with TickerProviderStateMixin {
  static const String _exportPdfMenuItem = 'Export PDF...';
  static const String _sharePdfMenuItem = 'Share PDF...';
  static const Duration _saveOverwriteTimeout = Duration(seconds: 30);
  static const int _defaultToolColor = 0xFF336699;
  static const int _defaultHighlighterColor = 0xFFFFFF00;
  static const Color _laserColor = Colors.redAccent;
  static const double _penMinWidth = 0.1;
  static const double _penMaxWidth = 3;
  static const int _penWidthDivisions = 29;
  static const double _highlighterMinWidth = 5;
  static const double _highlighterMaxWidth = 50;
  static const int _highlighterWidthDivisions = 45;
  static const double _eraserMinWidth = 1;
  static const double _eraserMaxWidth = 20;
  static const int _eraserWidthDivisions = 19;
  static const double _pageGap = 24;
  static const double _pageHorizontalPadding = 16;
  static const double _pageCardMargin = 4;
  static const Duration _zoomAnimationDuration = Duration(milliseconds: 180);
  static const Duration _backgroundRenderCommitDelay = Duration(
    milliseconds: 180,
  );
  static const Duration _viewportInteractionIdleDelay = Duration(
    milliseconds: 180,
  );

  XppFile? _file;
  String? filePath;

  int currentPage = 0;

  Color toolColor = Color(_defaultToolColor); // This is Colorfab3
  Color highlighterColor = Colors.yellow;
  double toolWidth = 2.6;
  double highlighterWidth = 20;
  double eraserWidth = 20;
  bool drawWithStylusOnly = false;

  Map<PointerDeviceKind?, EditingTool> _toolData = {};
  PointerDeviceKind? _currentDevice = PointerDeviceKind.touch;

  /// used fro parent-child communication
  final Map<int, GlobalKey<XppPageStackState>> _pageStackKeys = {};
  final Map<int, GlobalKey<PointerListenerState>> _pointerListenerKeys = {};
  final Map<int, GlobalKey> _pageItemKeys = {};
  final GlobalKey<EditingToolBarState> _editingToolbarKey = GlobalKey();
  final GlobalKey _pagesViewportKey = GlobalKey();
  final ScrollController _pagesScrollController = ScrollController();
  final ScrollController _pagesHorizontalScrollController = ScrollController();
  late final AnimationController _zoomAnimationController;
  Timer? _backgroundRenderCommitTimer;
  Timer? _viewportInteractionIdleTimer;
  Animation<double>? _zoomAnimation;
  _TopScrollPosition? _zoomTopScrollPosition;
  final ValueNotifier<bool> _deferPdfRasterUpdates = ValueNotifier(false);

  double pageScale = 1;
  double _backgroundRenderScale = 1;
  double _strokeRasterScale = 1;
  double _lastViewportWidth = 0;

  bool savingFile = false;
  bool _pinchZoomActive = false;
  bool _viewportPinchZooming = false;
  final Map<int, Offset> _viewportTouchPositions = {};
  double? _lastViewportPinchDistance;
  Offset? _lastViewportPinchFocalPoint;
  bool _allowPop = false;
  bool _confirmingLeave = false;
  bool _currentPageUpdateScheduled = false;
  bool _pdfBackgroundPrefetchScheduled = false;
  bool _pdfBackgroundPrefetchPendingUntilIdle = false;
  int _pdfBackgroundPrefetchGeneration = 0;
  final Object _prefetchOwner = Object();
  PdfBackgroundRenderService get _pdfService =>
      widget.pdfRenderService ?? pdfBackgroundRenderService;
  int _navigationGeneration = 0;
  int? _navigationTarget;
  _PinchAnchor? _pinchAnchor;
  Offset? _pinchFocalPoint;
  int _pinchGeneration = 0;
  bool _pinchCorrectionScheduled = false;
  int _revision = 0;
  int _savedRevision = 0;

  final Map<XppLayer, _EraserContentIndex> _eraserIndexes = {};
  final List<_UndoEntry> _undoStack = [];
  Set<XppContent> _selectedContents = {};
  List<({XppLayer layer, XppContent content})>? _copiedContents;
  PageGeometry? _pageGeometry;
  PageGeometry get _geometry => _pageGeometry ??= PageGeometry(_file!.pages!);
  List<_SelectionMoveOriginal>? _selectionMoveOriginals;
  final _selectionTranslation = ValueNotifier<Offset>(Offset.zero);
  final _selectionIndexes = <XppLayer, ContentSpatialIndex>{};

  @override
  void initState() {
    _setMetadata();
    super.initState();
    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: _zoomAnimationDuration,
    )..addListener(_handleZoomAnimationTick);
    _pagesScrollController.addListener(_scheduleCurrentPageFromScroll);
    loadToolSettings();
    unawaited(_rememberOpenedFile());
    _scheduleInputModeRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToPage(currentPage, animated: false);
      _schedulePdfBackgroundPrefetch();
    });
  }

  Future<void> _rememberOpenedFile() async {
    final path = filePath;
    final file = _file;
    if (path == null || path.isEmpty || file == null) return;
    try {
      await RecentFiles.remember(
        path: path,
        name: file.title ?? Uri.tryParse(path)?.pathSegments.lastOrNull ?? path,
        preview: file.previewImage,
        currentPage: currentPage,
      );
    } catch (error) {
      // History storage is optional; failure must not prevent editing.
      debugPrint('Could not remember opened document: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PdfSourceScope(
      resolve: _resolvePdfSource,
      child: LayoutBuilder(
        builder: (context, constraints) =>
            _buildEditor(context, embedToolbar: constraints.maxWidth >= 1000),
      ),
    );
  }

  Future<PdfBackgroundRenderSource> _resolvePdfSource(
    XppBackgroundPdf background,
  ) => _file!.resolvePdfSource(context, background, renderService: _pdfService);

  Widget _buildEditor(BuildContext context, {required bool embedToolbar}) {
    final editingToolbar = _buildEditingToolbar(compact: embedToolbar);
    final documentTitle = Tooltip(
      message:
          '${widget.file?.title ?? S.of(context).newDocument}\n'
          '${S.of(context).doubleTapToChange}',
      child: GestureDetector(
        onDoubleTap: _showTitleDialog,
        child: Text(
          widget.file?.title ?? S.of(context).newDocument,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    return PopScope(
      canPop: _allowPop || !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _confirmingLeave) return;
        _confirmingLeave = true;
        if (!await _confirmLeave()) {
          _confirmingLeave = false;
          return;
        }
        if (!context.mounted) return;
        setState(() => _allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!context.mounted) return;
          final navigator = Navigator.of(context);
          if (navigator.canPop()) {
            navigator.pop(result);
          } else {
            await SystemNavigator.pop();
          }
        });
      },
      child: Scaffold(
        drawer: MainDrawer(onLeaveRequested: _confirmLeave),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Hero(
                tag: 'ZoomArea',
                child: _buildScrollablePages(),
                /*ColorFiltered(
                  colorFilter: ColorFilter.mode(
                      Theme.of(context).colorScheme.surface.withOpacity(.5),
                      BlendMode.darken),
                  child: child,
                )*/
              ),
            ),
            if (embedToolbar)
              Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                elevation: 4,
                child: SafeArea(
                  left: false,
                  top: false,
                  child: SizedBox(
                    width: 88,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: _buildPageBrowser(direction: Axis.vertical),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        appBar: AppBar(
          toolbarHeight: kToolbarHeight,
          title: embedToolbar
              ? Row(
                  children: [
                    Expanded(child: documentTitle),
                    const SizedBox(width: 16),
                    editingToolbar,
                  ],
                )
              : documentTitle,
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
                          Theme.of(context).colorScheme.onSurface,
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
                if (item == S.of(context).saveAs) saveFile(saveAs: true);
                if (item == S.of(context).sharePage) shareScreenshot();
                if (item == _exportPdfMenuItem) exportPdf();
                if (item == _sharePdfMenuItem) sharePdf();
              },
              itemBuilder: (BuildContext context) {
                return {
                  S.of(context).saveAs,
                  if (!kIsWeb) S.of(context).sharePage,
                  if (!kIsWeb) _exportPdfMenuItem,
                  if (_sharePdfSupported) _sharePdfMenuItem,
                }.map((String choice) {
                  return PopupMenuItem<String>(
                    value: choice,
                    child: Text(choice),
                  );
                }).toList();
              },
            ),
          ],
          bottom: embedToolbar
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(64),
                  child: editingToolbar,
                ),
        ),
        bottomNavigationBar: embedToolbar
            ? null
            : BottomAppBar(
                shape: kIsWeb ? null : CircularNotchedRectangle(),
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  constraints: BoxConstraints(maxHeight: 72),
                  child: Center(child: _buildPageBrowser()),
                ),
              ),
      ),
    );
  }

  XppPagesBrowser _buildPageBrowser({Axis direction = Axis.horizontal}) {
    return XppPagesBrowser(
      direction: direction,
      currentPage: currentPage,
      pageCount: _file!.pages!.length,
      onPageChange: _switchToPage,
      onPageAdd: _addPageAfterCurrent,
      onPageDelete: () => _deletePage(currentPage),
    );
  }

  EditingToolBar _buildEditingToolbar({required bool compact}) {
    return EditingToolBar(
      compact: compact,
      key: _editingToolbarKey,
      deviceMap: _toolData,
      getColor: getColor,
      getWidth: getWidth,
      getMinWidth: getMinWidth,
      getMaxWidth: getMaxWidth,
      getWidthDivisions: getWidthDivisions,
      onBackgroundSettings: _showBackgroundSettings,
      onPasteSelection: _canPasteSelection(_file!.pages![currentPage])
          ? _pasteSelection
          : null,
      onWidthChange: (newWidth, tool) {
        setState(() {
          if (tool == EditingTool.ERASER) {
            eraserWidth = newWidth * 2;
          } else if (tool == EditingTool.HIGHLIGHT) {
            highlighterWidth = newWidth;
          } else {
            toolWidth =
                newWidth * 2; // average pressure is 0.5, so multiplying by 2
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
          _cancelSelectionMove();
          _selectedContents = {};
        }
      }),
    );
  }

  void _setMetadata() {
    _file = widget.file;
    _pageGeometry = null;
    filePath = widget.filePath;
    currentPage = widget.initialPage
        .clamp(0, max((_file?.pages?.length ?? 1) - 1, 0))
        .toInt();
  }

  GlobalKey<XppPageStackState> get _currentPageStackKey =>
      _pageStackKeyFor(currentPage);

  Widget _buildScrollablePages() {
    final pages = _file?.pages ?? <XppPage>[];
    return LayoutBuilder(
      builder: (context, constraints) {
        _lastViewportWidth = constraints.maxWidth;
        final contentWidth = max(
          constraints.maxWidth,
          _pageDisplayWidth(constraints.maxWidth) +
              (_pageHorizontalPadding + _pageCardMargin) * 2,
        );
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _handleViewportPointerDown,
          onPointerMove: _handleViewportPointerMove,
          onPointerUp: _handleViewportPointerUp,
          onPointerCancel: _handleViewportPointerUp,
          onPointerSignal: _handleViewportPointerSignal,
          child: SingleChildScrollView(
            key: _pagesViewportKey,
            controller: _pagesHorizontalScrollController,
            physics: _viewportScrollPhysics,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              height: constraints.maxHeight,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification ||
                      notification is ScrollUpdateNotification ||
                      notification is UserScrollNotification) {
                    _noteViewportInteraction();
                  }
                  _scheduleCurrentPageFromScroll();
                  return false;
                },
                child: ListView.builder(
                  controller: _pagesScrollController,
                  physics: _viewportScrollPhysics,
                  padding: const EdgeInsets.symmetric(vertical: _pageGap),
                  itemExtentBuilder: (index, _) =>
                      _pageItemExtent(index, _lastViewportWidth),
                  scrollCacheExtent: ScrollCacheExtent.pixels(
                    _estimatedPageExtent(_lastViewportWidth) * 1.5,
                  ),
                  itemCount: pages.length,
                  itemBuilder: (context, index) =>
                      _buildScrollablePage(context, index, _lastViewportWidth),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleViewportPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _panPages(-event.scrollDelta);
    });
  }

  void _handleViewportPointerDown(PointerDownEvent event) {
    _cancelPageNavigation();
    if (!_viewportPinchZooming) _supersedeViewportCorrection();
    if (event.kind != PointerDeviceKind.touch) return;
    _noteViewportInteraction();

    _viewportTouchPositions[event.pointer] = event.position;
    if (_viewportPinchZooming) {
      for (final key in _pointerListenerKeys.values) {
        key.currentState?.cancelForViewportGesture();
      }
      return;
    }
    if (_viewportTouchPositions.length != 2) {
      return;
    }

    final metrics = _currentViewportPinchMetrics();
    if (metrics == null) return;

    _viewportPinchZooming = true;
    _lastViewportPinchDistance = metrics.distance;
    _lastViewportPinchFocalPoint = metrics.focalPoint;
    _handlePinchZoomStart(metrics.focalPoint);
    for (final key in _pointerListenerKeys.values) {
      key.currentState?.cancelForViewportGesture();
    }
  }

  void _handleViewportPointerMove(PointerMoveEvent event) {
    if (event.kind == PointerDeviceKind.touch &&
        _viewportTouchPositions.containsKey(event.pointer)) {
      _viewportTouchPositions[event.pointer] = event.position;
      _noteViewportInteraction();
    }
    if (!_viewportPinchZooming) return;

    final metrics = _currentViewportPinchMetrics();
    final previousDistance = _lastViewportPinchDistance;
    final previousFocalPoint = _lastViewportPinchFocalPoint;
    if (metrics == null ||
        previousDistance == null ||
        previousDistance <= 0 ||
        previousFocalPoint == null) {
      return;
    }

    _lastViewportPinchDistance = metrics.distance;
    _lastViewportPinchFocalPoint = metrics.focalPoint;
    _handlePinchZoomUpdate(
      scaleDelta: metrics.distance / previousDistance,
      globalFocalPoint: metrics.focalPoint,
      globalFocalDelta: metrics.focalPoint - previousFocalPoint,
    );
  }

  void _handleViewportPointerUp(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _viewportTouchPositions.remove(event.pointer);
    }

    if (!_viewportPinchZooming) return;
    if (_viewportTouchPositions.length >= 2) {
      final metrics = _currentViewportPinchMetrics();
      _lastViewportPinchDistance = metrics?.distance;
      _lastViewportPinchFocalPoint = metrics?.focalPoint;
      if (metrics != null) {
        _applyPinchAnchor();
        _capturePinchAnchor(metrics.focalPoint);
      }
      return;
    }

    _viewportPinchZooming = false;
    _lastViewportPinchDistance = null;
    _lastViewportPinchFocalPoint = null;
    _handlePinchZoomEnd();
  }

  _ViewportPinchMetrics? _currentViewportPinchMetrics() {
    if (_viewportTouchPositions.length < 2) return null;
    final points = _viewportTouchPositions.values.take(2).toList();
    final focalPoint = Offset(
      (points[0].dx + points[1].dx) / 2,
      (points[0].dy + points[1].dy) / 2,
    );
    return _ViewportPinchMetrics(
      focalPoint: focalPoint,
      distance: (points[1] - points[0]).distance,
    );
  }

  Widget _buildScrollablePage(
    BuildContext context,
    int pageIndex,
    double viewportWidth,
  ) {
    final page = _file!.pages![pageIndex];
    final displayWidth = _pageDisplayWidth(viewportWidth);
    final displayHeight = displayWidth / page.pageSize!.ratio;
    final backgroundDisplayWidth = _pageDisplayWidthForScale(
      viewportWidth,
      _backgroundRenderScale,
    );
    final backgroundDisplayHeight =
        backgroundDisplayWidth / page.pageSize!.ratio;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final isActivePage = pageIndex == currentPage;

    return Padding(
      padding: const EdgeInsets.only(
        left: _pageHorizontalPadding,
        right: _pageHorizontalPadding,
        bottom: _pageGap,
      ),
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(_pageCardMargin),
          elevation: isActivePage ? 12 : 6,
          color: Colors.white,
          child: SizedBox(
            key: _pageItemKeyFor(pageIndex),
            width: displayWidth,
            height: displayHeight,
            child: FittedBox(
              child: PointerListener(
                key: _pointerListenerKeyFor(pageIndex),
                viewportGesturesExternallyManaged: true,
                toolData: _toolData,
                strokeWidth: toolWidth,
                highlighterWidth: highlighterWidth,
                eraserWidth: eraserWidth,
                color: toolColor,
                highlighterColor: highlighterColor,
                laserColor: _laserColor,
                drawWithStylusOnly: drawWithStylusOnly,
                onPointerActivity: () => _activatePageForEditing(pageIndex),
                onPan: _panPages,
                onDeviceChange: _handleDeviceChange,
                filterEraser: ({Offset? coordinates, double? radius}) {
                  _activatePageForEditing(pageIndex);
                  _eraseContentAt(coordinates: coordinates, radius: radius);
                },
                filterEraserPath:
                    ({List<Offset>? coordinates, double? radius}) {
                      _activatePageForEditing(pageIndex);
                      _eraseContentAlongPath(
                        coordinates: coordinates,
                        radius: radius,
                      );
                    },
                onSelectionRegionChange: (region) {
                  _activatePageForEditing(pageIndex);
                  _selectRegion(region);
                },
                onSelectionClear: () {
                  _activatePageForEditing(pageIndex);
                  _clearSelection();
                },
                shouldMoveSelection: (position) {
                  _activatePageForEditing(pageIndex);
                  return _shouldMoveSelection(position);
                },
                onSelectionMoveCancel: _cancelSelectionMove,
                onSelectionMove: (delta, {bool done = false}) {
                  _activatePageForEditing(pageIndex);
                  _moveSelection(delta, done: done);
                },
                onSwipeLeft: () => _switchToPage(pageIndex + 1),
                onSwipeRight: () => _switchToPage(pageIndex - 1),
                onNewContent: (newContent) =>
                    _addContentToPage(pageIndex, newContent),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      XppPageStack(
                        key: _pageStackKeyFor(pageIndex),
                        page: page,
                        rasterScale:
                            _pageDisplayWidthForScale(
                              viewportWidth,
                              _strokeRasterScale,
                            ) /
                            page.pageSize!.width!,
                        keepAlive: false,
                        backgroundTargetPixelWidth:
                            backgroundDisplayWidth * devicePixelRatio,
                        backgroundTargetPixelHeight:
                            backgroundDisplayHeight * devicePixelRatio,
                        deferBackgroundRasterUpdates: _deferPdfRasterUpdates,
                        activeTool: isActivePage ? _activeTool : null,
                        selectionTranslation: isActivePage
                            ? _selectionTranslation
                            : null,
                        selectedContents: isActivePage
                            ? _selectedContents
                            : const <XppContent>{},
                        onSelectContent: (layer, content) {
                          _activatePageForEditing(pageIndex);
                          _selectContent(layer, content);
                        },
                        onDeleteSelection: () {
                          _activatePageForEditing(pageIndex);
                          _deleteSelection();
                        },
                        onDuplicateSelection: () {
                          _activatePageForEditing(pageIndex);
                          _duplicateSelection();
                        },
                        onReplaceContent: (layer, oldContent, newContent) {
                          _activatePageForEditing(pageIndex);
                          _replaceContent(layer, oldContent, newContent);
                        },
                        onContentPointerDown: (event) => _pointerListenerKeyFor(
                          pageIndex,
                        ).currentState?.markContentPointerDown(event),
                      ),
                      if (kDebugMode) _buildPageTopCoordinateOverlay(pageIndex),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  GlobalKey<XppPageStackState> _pageStackKeyFor(int pageIndex) {
    return _pageStackKeys.putIfAbsent(
      pageIndex,
      () => GlobalKey<XppPageStackState>(),
    );
  }

  GlobalKey<PointerListenerState> _pointerListenerKeyFor(int pageIndex) {
    return _pointerListenerKeys.putIfAbsent(
      pageIndex,
      () => GlobalKey<PointerListenerState>(),
    );
  }

  GlobalKey _pageItemKeyFor(int pageIndex) {
    return _pageItemKeys.putIfAbsent(pageIndex, GlobalKey.new);
  }

  Widget _buildPageTopCoordinateOverlay(int pageIndex) {
    return Positioned(
      left: 8,
      top: 8,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                height: 1.2,
              ),
              child: AnimatedBuilder(
                animation: _pagesScrollController,
                builder: (context, _) {
                  final topOffset = _pageScrollOffset(pageIndex);
                  final currentOffset = _pagesScrollController.hasClients
                      ? _pagesScrollController.offset
                      : 0.0;
                  final topCoordinate = _pageCoordinateForScrollOffset(
                    pageIndex,
                    topOffset,
                  );
                  final currentCoordinate = _pageCoordinateForScrollOffset(
                    pageIndex,
                    currentOffset,
                  );

                  return Text(
                    'p${pageIndex + 1} top ${topOffset.toStringAsFixed(1)} '
                    '-> ${_formatCoordinate(topCoordinate)}\n'
                    'current ${currentOffset.toStringAsFixed(1)} '
                    '-> ${_formatCoordinate(currentCoordinate)}',
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatCoordinate(Offset? coordinate) {
    if (coordinate == null) return 'unavailable';
    return '(${coordinate.dx.toStringAsFixed(1)}, '
        '${coordinate.dy.toStringAsFixed(1)})';
  }

  Offset? _pageCoordinateForScrollOffset(int pageIndex, double scrollOffset) {
    final pages = _file?.pages ?? <XppPage>[];
    if (pageIndex < 0 || pageIndex >= pages.length) return null;

    final page = pages[pageIndex];
    final pageSize = page.pageSize?.toSize();
    if (pageSize == null) return null;

    final displayWidth = _pageDisplayWidth(_lastViewportWidth);
    final displayHeight = displayWidth / page.pageSize!.ratio;
    final pageTopOffset = _pageScrollOffset(pageIndex);
    final y =
        ((scrollOffset - pageTopOffset) / displayHeight) * pageSize.height;

    return Offset(0, y);
  }

  void _clearPageWidgetKeys() {
    _cancelSelectionMove();
    _selectionIndexes.clear();
    _pageGeometry = null;
    _cancelPageNavigation();
    _invalidatePrefetch();
    _pinchGeneration++;
    _pinchCorrectionScheduled = false;
    _pinchAnchor = null;
    _pageStackKeys.clear();
    _pointerListenerKeys.clear();
    _pageItemKeys.clear();
  }

  void _activatePageForEditing(int pageIndex) {
    _cancelPageNavigation();
    _setCurrentPage(pageIndex);
  }

  void _setCurrentPage(int pageIndex) {
    final pages = _file?.pages;
    if (pages == null || pages.isEmpty) return;
    if (pageIndex < 0 || pageIndex >= pages.length) return;
    if (pageIndex == currentPage) return;
    _cancelSelectionMove();

    _invalidatePrefetch();

    setState(() {
      currentPage = pageIndex;
      _selectedContents = {};
      _invalidateEraserIndex();
    });
    _schedulePdfBackgroundPrefetch();
  }

  void _schedulePdfBackgroundPrefetch() {
    if (_deferPdfRasterUpdates.value || _pinchZoomActive) {
      _pdfBackgroundPrefetchPendingUntilIdle = true;
      return;
    }
    if (_pdfBackgroundPrefetchScheduled) return;
    _pdfBackgroundPrefetchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pdfBackgroundPrefetchScheduled = false;
      if (!mounted) return;
      if (_deferPdfRasterUpdates.value || _pinchZoomActive) {
        _pdfBackgroundPrefetchPendingUntilIdle = true;
        return;
      }
      _prefetchPdfBackgroundWindow();
    });
    // Idle timers do not otherwise guarantee that another frame will occur.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _noteViewportInteraction() {
    if (!_deferPdfRasterUpdates.value) {
      _invalidatePrefetch();
      _pdfBackgroundPrefetchPendingUntilIdle = true;
      _deferPdfRasterUpdates.value = true;
    }
    _viewportInteractionIdleTimer?.cancel();
    _viewportInteractionIdleTimer = Timer(_viewportInteractionIdleDelay, () {
      if (!mounted) return;
      if (_pinchZoomActive || _viewportPinchZooming) {
        _noteViewportInteraction();
        return;
      }
      _deferPdfRasterUpdates.value = false;
      if (_pdfBackgroundPrefetchPendingUntilIdle) {
        _pdfBackgroundPrefetchPendingUntilIdle = false;
        _schedulePdfBackgroundPrefetch();
      }
    });
  }

  void _prefetchPdfBackgroundWindow() {
    final pages = _file?.pages;
    if (pages == null || pages.isEmpty) return;

    _invalidatePrefetch();
    final generation = _pdfBackgroundPrefetchGeneration;
    final prefetchPages = <int>{
      for (var i = currentPage - 1; i <= currentPage + 1; i++)
        if (i >= 0 && i < pages.length) i,
    };

    for (final pageIndex in [currentPage, currentPage - 1, currentPage + 1]) {
      if (!prefetchPages.contains(pageIndex)) continue;
      unawaited(
        _prefetchPdfBackgroundPage(
          pageIndex,
          PdfBackgroundRenderVariant.full,
          generation,
        ),
      );
    }
  }

  void _invalidatePrefetch() {
    _pdfBackgroundPrefetchGeneration++;
    _pdfService.cancelRequests(_prefetchOwner);
  }

  Future<void> _prefetchPdfBackgroundPage(
    int pageIndex,
    PdfBackgroundRenderVariant variant,
    int generation,
  ) async {
    final pages = _file?.pages;
    if (pages == null || pageIndex < 0 || pageIndex >= pages.length) return;

    final page = pages[pageIndex];
    final background = page.background;
    if (background is! XppBackgroundPdf) return;
    final filename = background.filename;
    if (filename == null || filename.isEmpty) return;

    try {
      // Warm only resolved document snapshots; prefetch must never open UI.
      final pendingSource = _file!.resolvedPdfSource(background, _pdfService);
      if (pendingSource == null) return;
      final source = await pendingSource;
      if (!mounted || generation != _pdfBackgroundPrefetchGeneration) return;
      if (!identical(pages[pageIndex], page) ||
          !identical(page.background, background))
        return;
      final pageSize = page.pageSize!.toSize();
      final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      final width = _pageDisplayWidthForScale(
        _lastViewportWidth,
        _backgroundRenderScale,
      );
      await _pdfService.request(
        source,
        background.page,
        variant,
        targetWidth: width * devicePixelRatio,
        targetHeight: width / page.pageSize!.ratio * devicePixelRatio,
        pageWidthPoints: pageSize.width,
        pageHeightPoints: pageSize.height,
        priority: PdfBackgroundRenderPriority.prefetch,
        owner: _prefetchOwner,
      );
    } catch (_) {
      // Prefetch should never interrupt scrolling with missing-file UI.
    }
  }

  void _scheduleCurrentPageFromScroll() {
    if (_currentPageUpdateScheduled) return;
    _currentPageUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _currentPageUpdateScheduled = false;
      if (mounted) _updateCurrentPageFromScroll();
    });
  }

  void _updateCurrentPageFromScroll() {
    if (_navigationTarget != null) return;
    final viewportObject = _pagesViewportKey.currentContext?.findRenderObject();
    if (viewportObject is! RenderBox) return;

    final viewportTop = viewportObject.localToGlobal(Offset.zero).dy;
    final viewportCenter = viewportTop + viewportObject.size.height / 2;
    var bestPage = currentPage;
    var bestDistance = double.infinity;

    final stalePages = <int>[];
    for (final entry in _pageItemKeys.entries) {
      final pageObject = entry.value.currentContext?.findRenderObject();
      if (pageObject is! RenderBox || !pageObject.attached) {
        stalePages.add(entry.key);
        continue;
      }

      final pageTop = pageObject.localToGlobal(Offset.zero).dy;
      final pageCenter = pageTop + pageObject.size.height / 2;
      final distance = (pageCenter - viewportCenter).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestPage = entry.key;
      }
    }

    for (final page in stalePages) {
      _pageItemKeys.remove(page);
      _pageStackKeys.remove(page);
      _pointerListenerKeys.remove(page);
    }

    if (bestPage != currentPage) _setCurrentPage(bestPage);
  }

  void _scrollToPage(int pageIndex, {bool animated = true}) {
    if (!_pagesScrollController.hasClients) return;
    _supersedeViewportCorrection();

    final generation = ++_navigationGeneration;
    _navigationTarget = pageIndex;

    final offset = _pageScrollOffset(pageIndex);
    final maxOffset = _pagesScrollController.position.maxScrollExtent;
    final target = offset.clamp(0.0, maxOffset).toDouble();
    if (animated) {
      unawaited(
        _pagesScrollController
            .animateTo(
              target,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            )
            .then((_) {
              if (!mounted || generation != _navigationGeneration) return;
              _navigationTarget = null;
              _scheduleCurrentPageFromScroll();
            }),
      );
    } else {
      _pagesScrollController.jumpTo(target);
      _navigationTarget = null;
    }
  }

  void _cancelPageNavigation() {
    if (_navigationTarget == null) return;
    _navigationGeneration++;
    _navigationTarget = null;
    if (_pagesScrollController.hasClients) {
      _pagesScrollController.jumpTo(_pagesScrollController.offset);
    }
  }

  void _panPages(Offset delta, {bool duringPinch = false}) {
    if (_pinchZoomActive && !duringPinch) return;
    if (!duringPinch) _supersedeViewportCorrection();
    _cancelPageNavigation();
    _noteViewportInteraction();

    if (_pagesHorizontalScrollController.hasClients) {
      final horizontal = _pagesHorizontalScrollController.position;
      final target = (horizontal.pixels - delta.dx)
          .clamp(horizontal.minScrollExtent, horizontal.maxScrollExtent)
          .toDouble();
      if (target != horizontal.pixels) {
        _pagesHorizontalScrollController.jumpTo(target);
      }
    }

    if (_pagesScrollController.hasClients) {
      final vertical = _pagesScrollController.position;
      final target = (vertical.pixels - delta.dy)
          .clamp(vertical.minScrollExtent, vertical.maxScrollExtent)
          .toDouble();
      if (target != vertical.pixels) {
        _pagesScrollController.jumpTo(target);
      }
    }
  }

  void _clampHorizontalScroll() {
    if (!_pagesHorizontalScrollController.hasClients) return;
    final horizontal = _pagesHorizontalScrollController.position;
    final target = horizontal.pixels
        .clamp(horizontal.minScrollExtent, horizontal.maxScrollExtent)
        .toDouble();
    if (target != horizontal.pixels) {
      _pagesHorizontalScrollController.jumpTo(target);
    }
  }

  double _pageScrollOffset(int pageIndex) {
    return _pageScrollOffsetForScale(pageIndex, pageScale);
  }

  double _pageScrollOffsetForScale(int pageIndex, double scale) {
    return _geometry.offset(
      pageIndex,
      _pageDisplayWidthForScale(_lastViewportWidth, scale),
      _pageGap + _pageCardMargin * 2,
      _pageGap + _pageCardMargin,
    );
  }

  double? _pageItemExtent(int pageIndex, double viewportWidth) {
    return _pageItemExtentForScale(pageIndex, viewportWidth, pageScale);
  }

  double? _pageItemExtentForScale(
    int pageIndex,
    double viewportWidth,
    double scale,
  ) {
    final pages = _file?.pages ?? <XppPage>[];
    if (pageIndex < 0 || pageIndex >= pages.length) return null;

    final displayWidth = _pageDisplayWidthForScale(viewportWidth, scale);
    return displayWidth / pages[pageIndex].pageSize!.ratio +
        _pageGap +
        _pageCardMargin * 2;
  }

  _TopScrollPosition? _currentTopScrollPosition() {
    if (!_pagesScrollController.hasClients) return null;

    final pages = _file?.pages ?? <XppPage>[];
    if (pages.isEmpty) return null;

    final scrollOffset = _pagesScrollController.offset;
    final pageIndex = _geometry.pageAt(
      scrollOffset,
      _pageDisplayWidth(_lastViewportWidth),
      _pageGap + _pageCardMargin * 2,
      _pageGap + _pageCardMargin,
    );

    final pageSize = pages[pageIndex].pageSize?.toSize();
    if (pageSize == null) return null;

    final pageTop = _pageScrollOffsetForScale(pageIndex, pageScale);
    final displayHeight = _pageDisplayHeightForScale(pageIndex, pageScale);
    if (displayHeight <= 0) return null;

    return _TopScrollPosition(
      pageIndex: pageIndex,
      pageY: ((scrollOffset - pageTop) / displayHeight) * pageSize.height,
    );
  }

  void _restoreTopScrollPosition(
    _TopScrollPosition? position, {
    required double scale,
  }) {
    if (position == null || !_pagesScrollController.hasClients) return;

    final pages = _file?.pages ?? <XppPage>[];
    if (position.pageIndex < 0 || position.pageIndex >= pages.length) return;

    final pageSize = pages[position.pageIndex].pageSize?.toSize();
    if (pageSize == null || pageSize.height <= 0) return;

    final pageTop = _pageScrollOffsetForScale(position.pageIndex, scale);
    final displayHeight = _pageDisplayHeightForScale(position.pageIndex, scale);
    final target = pageTop + (position.pageY / pageSize.height) * displayHeight;
    final vertical = _pagesScrollController.position;
    final clampedTarget = max(vertical.minScrollExtent, target).toDouble();
    if (clampedTarget != vertical.pixels) {
      _pagesScrollController.jumpTo(clampedTarget);
    }
  }

  double _estimatedPageExtent(double viewportWidth) {
    final pages = _file?.pages;
    if (pages == null || pages.isEmpty) return 800;
    return _pageItemExtent(currentPage, viewportWidth) ?? 800;
  }

  double _pageDisplayWidth(double viewportWidth) {
    return _pageDisplayWidthForScale(viewportWidth, pageScale);
  }

  double _pageDisplayWidthForScale(double viewportWidth, double scale) {
    return max(
          1.0,
          viewportWidth - (_pageHorizontalPadding + _pageCardMargin) * 2,
        ) *
        scale;
  }

  double _pageDisplayHeightForScale(int pageIndex, double scale) {
    final pages = _file?.pages ?? <XppPage>[];
    if (pageIndex < 0 || pageIndex >= pages.length) return 0;
    return _pageDisplayWidthForScale(_lastViewportWidth, scale) /
        pages[pageIndex].pageSize!.ratio;
  }

  void _refreshPageStack(int pageIndex, XppPage page) {
    for (final layer in page.layers ?? <XppLayer>[]) {
      _selectionIndexes.remove(layer);
    }
    _pageStackKeys[pageIndex]?.currentState?.setPageData(page);
  }

  Future<Uint8List> _currentPagePng() async {
    var state = _currentPageStackKey.currentState;
    if (state != null) return state.toPng();

    _scrollToPage(currentPage, animated: false);
    await WidgetsBinding.instance.endOfFrame;
    state = _currentPageStackKey.currentState;
    if (state == null) {
      throw StateError('Current page is not available for export.');
    }
    return state.toPng();
  }

  void _addContentToPage(int pageIndex, XppContent? newContent) {
    if (newContent == null) return;
    _activatePageForEditing(pageIndex);

    /// TODO: manage layers
    final page = _file!.pages![pageIndex];
    final layer = page.layers!.last;
    setState(() {
      final content = List<XppContent?>.from(layer.content!)..add(newContent);
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
      _markDirty();
    });
    _eraserIndexes[layer]?.add(newContent);

    _refreshPageStack(pageIndex, page);
  }

  bool get _isDirty => filePath == null || _revision != _savedRevision;

  void _markDirty() {
    _revision++;
  }

  Future<bool> _confirmLeave() async {
    if (!_isDirty) return true;

    final action = await showDialog<_UnsavedChangesAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save changes?'),
        content: const Text('This document has unsaved changes.'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_UnsavedChangesAction.cancel),
            child: Text(S.of(context).cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_UnsavedChangesAction.discard),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_UnsavedChangesAction.save),
            child: Text(S.of(context).save),
          ),
        ],
      ),
    );

    switch (action) {
      case _UnsavedChangesAction.save:
        return saveFile();
      case _UnsavedChangesAction.discard:
        return true;
      case _UnsavedChangesAction.cancel:
      case null:
        return false;
    }
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
                      _markDirty();
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
              color: Theme.of(context).colorScheme.onSurface,
              onPressed: () {
                _setScale(pageScale - 0.1);
              },
            ),
            IconButton(
              icon: Icon(Icons.fit_screen),
              color: Theme.of(context).colorScheme.onSurface,
              tooltip: 'Fit width',
              onPressed: _fitPageToWidth,
            ),
            IconButton(
              icon: Icon(Icons.add),
              color: Theme.of(context).colorScheme.onSurface,
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
    for (final key in _pointerListenerKeys.values) {
      key.currentState?.setState(() {
        key.currentState!.drawingEnabled = !_canPanViewport;
      });
    }
  }

  void _scheduleInputModeRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setDefaultDeviceIfNotSet(kind: _currentDevice);
      _setZoomableState();
    });
  }

  EditingTool? get _activeTool => _toolData[_currentDevice];

  ScrollPhysics get _viewportScrollPhysics =>
      _canPanViewport && !_pinchZoomActive
      ? const ClampingScrollPhysics()
      : const NeverScrollableScrollPhysics();

  bool get _canPanViewport {
    return _activeTool == EditingTool.MOVE ||
        (drawWithStylusOnly && _isNonStylusPointerKind(_currentDevice));
  }

  bool _isNonStylusPointerKind(PointerDeviceKind? kind) {
    return kind != PointerDeviceKind.stylus &&
        kind != PointerDeviceKind.invertedStylus;
  }

  void _setScale(double newZoom) {
    newZoom = max(.1, min(5, newZoom));
    if (newZoom == pageScale) return;
    if (_viewportPinchZooming) return;
    _cancelPageNavigation();
    _supersedeViewportCorrection();

    _noteViewportInteraction();
    _backgroundRenderCommitTimer?.cancel();
    _zoomAnimationController.stop();
    _zoomTopScrollPosition = _currentTopScrollPosition();
    _zoomAnimation = Tween<double>(begin: pageScale, end: newZoom).animate(
      CurvedAnimation(parent: _zoomAnimationController, curve: Curves.easeOut),
    );
    _pinchZoomActive = false;
    _backgroundRenderScale = newZoom;
    _strokeRasterScale = newZoom;
    _zoomAnimationController.forward(from: 0);
  }

  void _handlePinchZoomStart(Offset globalFocalPoint) {
    _cancelPageNavigation();
    _supersedeViewportCorrection();
    _noteViewportInteraction();
    _backgroundRenderCommitTimer?.cancel();
    _zoomAnimationController.stop();
    _zoomAnimation = null;
    _zoomTopScrollPosition = null;
    _capturePinchAnchor(globalFocalPoint);
    setState(() => _pinchZoomActive = true);
  }

  Offset? _viewportLocalPoint(Offset globalPoint) {
    final box = _pagesViewportKey.currentContext?.findRenderObject();
    return box is RenderBox ? box.globalToLocal(globalPoint) : null;
  }

  double _pageLeftForScale(double scale) => max(
    _pageHorizontalPadding + _pageCardMargin,
    (_lastViewportWidth -
            _pageDisplayWidthForScale(_lastViewportWidth, scale)) /
        2,
  );

  void _capturePinchAnchor(Offset globalPoint) {
    final local = _viewportLocalPoint(globalPoint);
    final pages = _file?.pages;
    if (local == null ||
        pages == null ||
        pages.isEmpty ||
        !_pagesScrollController.hasClients)
      return;
    final y = _pagesScrollController.offset + local.dy;
    final index = _geometry.pageAt(
      y,
      _pageDisplayWidth(_lastViewportWidth),
      _pageGap + _pageCardMargin * 2,
      _pageGap + _pageCardMargin,
    );
    final top = _pageScrollOffset(index);
    final x =
        (_pagesHorizontalScrollController.hasClients
            ? _pagesHorizontalScrollController.offset
            : 0) +
        local.dx;
    _pinchAnchor = _PinchAnchor(
      page: pages[index],
      fraction: Offset(
        (x - _pageLeftForScale(pageScale)) /
            _pageDisplayWidth(_lastViewportWidth),
        (y - top) / _pageDisplayHeightForScale(index, pageScale),
      ),
    );
    _pinchFocalPoint = globalPoint;
  }

  void _applyPinchAnchor({bool clampToLayout = false}) {
    final anchor = _pinchAnchor;
    final focal = _pinchFocalPoint;
    if (anchor == null || focal == null) return;
    final index = _geometry.indexOf(anchor.page);
    final local = _viewportLocalPoint(focal);
    if (index < 0 || local == null) return;
    void jump(ScrollController controller, double target) {
      if (!controller.hasClients) return;
      final position = controller.position;
      target = max(position.minScrollExtent, target);
      if (clampToLayout) target = min(position.maxScrollExtent, target);
      if (position.pixels != target) controller.jumpTo(target);
    }

    jump(
      _pagesScrollController,
      _pageScrollOffset(index) +
          anchor.fraction.dy * _pageDisplayHeightForScale(index, pageScale) -
          local.dy,
    );
    jump(
      _pagesHorizontalScrollController,
      _pageLeftForScale(pageScale) +
          anchor.fraction.dx * _pageDisplayWidth(_lastViewportWidth) -
          local.dx,
    );
  }

  void _schedulePinchCorrection() {
    if (_pinchCorrectionScheduled) return;
    _pinchCorrectionScheduled = true;
    final generation = _pinchGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _pinchGeneration) return;
      _pinchCorrectionScheduled = false;
      _applyPinchAnchor(clampToLayout: true);
    });
  }

  // All new viewport operations supersede outstanding anchor corrections,
  // including corrections queued by an already-ended pinch.
  void _supersedeViewportCorrection() {
    _pinchGeneration++;
    _pinchCorrectionScheduled = false;
    _pinchAnchor = null;
    _pinchFocalPoint = null;
    final wasAnimating = _zoomAnimationController.isAnimating;
    _zoomAnimationController.stop();
    _zoomAnimation = null;
    _zoomTopScrollPosition = null;
    if (wasAnimating) {
      setState(() {
        _backgroundRenderScale = pageScale;
        _strokeRasterScale = pageScale;
      });
    }
  }

  void _handlePinchZoomUpdate({
    required double scaleDelta,
    required Offset globalFocalPoint,
    required Offset globalFocalDelta,
  }) {
    if (!_pinchZoomActive || scaleDelta <= 0 || !scaleDelta.isFinite) return;

    final nextScale = max(.1, min(5.0, pageScale * scaleDelta));
    if (nextScale == pageScale && globalFocalDelta == Offset.zero) return;

    _noteViewportInteraction();
    _pinchFocalPoint = globalFocalPoint;
    setState(() {
      pageScale = nextScale;
      _applyPinchAnchor();
    });
    _schedulePinchCorrection();
  }

  void _handlePinchZoomEnd() {
    if (!_pinchZoomActive) return;
    setState(() {
      _pinchZoomActive = false;
      _strokeRasterScale = pageScale;
    });
    _noteViewportInteraction();
    _scheduleBackgroundRenderScaleCommit();
    final generation = _pinchGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _pinchGeneration) return;
      _clampHorizontalScroll();
    });
  }

  void _scheduleBackgroundRenderScaleCommit() {
    _backgroundRenderCommitTimer?.cancel();
    _backgroundRenderCommitTimer = Timer(_backgroundRenderCommitDelay, () {
      if (!mounted) return;
      if (_pinchZoomActive) return;
      if (_backgroundRenderScale == pageScale) return;
      setState(() => _backgroundRenderScale = pageScale);
      _schedulePdfBackgroundPrefetch();
    });
  }

  void _handleZoomAnimationTick() {
    final animation = _zoomAnimation;
    if (animation == null) return;

    final nextScale = animation.value;
    setState(() {
      pageScale = nextScale;
      _restoreTopScrollPosition(_zoomTopScrollPosition, scale: nextScale);
    });
    _noteViewportInteraction();
    final generation = _pinchGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _pinchGeneration) return;
      _clampHorizontalScroll();
    });
  }

  void _fitPageToWidth() {
    _setScale(1.0);
  }

  void _eraseContentAt({Offset? coordinates, double? radius}) {
    if (coordinates == null) return;
    _eraseContentAlongPath(coordinates: [coordinates], radius: radius);
  }

  void _switchToPage(int pageIndex) {
    final pages = _file?.pages;
    if (pages == null || pages.isEmpty) return;
    if (pageIndex < 0 || pageIndex >= pages.length) return;

    _setCurrentPage(pageIndex);
    _scrollToPage(pageIndex);
  }

  void _addPageAfterCurrent() {
    setState(() {
      currentPage++;
      _selectedContents = {};
      _invalidateEraserIndex();
      _file!.pages!.insert(
        currentPage,
        XppPage.empty(background: Colors.white),
      );
      _clearPageWidgetKeys();
      _markDirty();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToPage(currentPage);
    });
  }

  void _deletePage(int pageIndex) {
    setState(() {
      _file!.pages!.removeAt(pageIndex);
      _selectedContents = {};
      _invalidateEraserIndex();
      if (currentPage >= _file!.pages!.length) {
        currentPage = _file!.pages!.length - 1;
      }
      if (_file!.pages!.isEmpty) {
        _file!.pages!.add(XppPage.empty(background: Colors.white));
        currentPage = 0;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).thereWereNoMorePagesWeAddedOne)),
        );
      }
      _clearPageWidgetKeys();
      _markDirty();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToPage(currentPage, animated: false);
    });
  }

  void _showBackgroundSettings() {
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
        onPdfBackgroundChange: _changeBackgroundWithPdf,
        onBackgroundChange: (newBackground) {
          newBackground.size = _file!.pages![currentPage].pageSize;
          setState(() {
            _file!.pages![currentPage].background = newBackground;
            _markDirty();
          });
        },
      ),
    );
  }

  Future<void> _changeBackgroundWithPdf() async {
    final pdf = await XppPickedFile.importFromStorage(
      type: XppFilePickType.custom,
      fileExtension: 'pdf',
    );
    if (!mounted) return;

    await runWithLoadingFileDialog(context, () async {
      final pageSizes = await pdfPageSizes(pdf);
      final pdfPath = pdf.path ?? await pdf.saveToTemporaryPath();
      if (!mounted) return;

      setState(() {
        for (var i = 0; i < pageSizes.length; i++) {
          final page = i < _file!.pages!.length
              ? _file!.pages![i]
              : XppPage.empty(background: Colors.white);
          resizePageForPdfIfEmpty(page, pageSizes[i]);
          page.background = XppBackgroundPdf(
            onUnavailable: (context, String? path) async =>
                XppPickedFile.fromInternalPath(path: pdfPath),
            filename: pdfPath,
            page: i + 1,
          );
          if (i >= _file!.pages!.length) {
            _file!.pages!.add(page);
          }
        }

        if (currentPage >= _file!.pages!.length) {
          currentPage = _file!.pages!.length - 1;
        }
        _selectedContents = {};
        _invalidateEraserIndex();
        _clearPageWidgetKeys();
        _markDirty();
      });

      _refreshPageStack(currentPage, _file!.pages![currentPage]);
      _schedulePdfBackgroundPrefetch();
    });
  }

  bool get _canUndo => _undoStack.isNotEmpty;

  void _undoLastOperation() {
    if (_undoStack.isEmpty) return;

    final undoEntry = _undoStack.removeLast();
    setState(() {
      for (final operation in undoEntry.operations.reversed) {
        operation.undo();
      }
      if (undoEntry.page == _file!.pages![currentPage]) {
        final remainingContents =
            undoEntry.page.layers
                ?.expand((layer) => layer.content ?? <XppContent?>[])
                .whereType<XppContent>()
                .toSet() ??
            <XppContent>{};
        _selectedContents = _selectedContents.intersection(remainingContents);
      }
      _invalidateEraserIndex();
      _markDirty();
    });

    if (undoEntry.page == _file!.pages![currentPage]) {
      _refreshPageStack(currentPage, undoEntry.page);
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
      _markDirty();
    });
    _refreshPageStack(currentPage, page);
  }

  void _selectContent(XppLayer _, XppContent content) {
    if (_activeTool != EditingTool.SELECT) return;
    setState(() => _selectedContents = {content});
  }

  void _selectRegion(Rect? region) {
    if (_activeTool != EditingTool.SELECT || region == null) return;

    final selected = <XppContent>{};
    for (final layer in _file!.pages![currentPage].layers ?? <XppLayer>[]) {
      final index = _selectionIndexes.putIfAbsent(
        layer,
        () => ContentSpatialIndex(layer.content ?? []),
      );
      selected.addAll(index.query(region));
    }

    if (!setEquals(_selectedContents, selected)) {
      setState(() => _selectedContents = selected);
    }
  }

  void _clearSelection() {
    if (_activeTool != EditingTool.SELECT || _selectedContents.isEmpty) return;
    _cancelSelectionMove();
    setState(() => _selectedContents = {});
  }

  void _deleteSelection() {
    if (_activeTool != EditingTool.SELECT || _selectedContents.isEmpty) return;

    final page = _file!.pages![currentPage];
    final operations = <_LayerOperation>[];

    for (final layer in page.layers ?? <XppLayer>[]) {
      final content = layer.content ?? <XppContent?>[];
      final updatedContent = <XppContent?>[];
      var deletedFromLayer = false;

      for (var index = 0; index < content.length; index++) {
        final item = content[index];
        if (item == null || !_selectedContents.contains(item)) {
          updatedContent.add(item);
          continue;
        }

        operations.add(
          _LayerOperation.removed(
            page: page,
            layer: layer,
            content: item,
            index: index,
          ),
        );
        deletedFromLayer = true;
      }

      if (deletedFromLayer) layer.content = updatedContent;
    }

    if (operations.isEmpty) return;

    setState(() {
      _undoStack.add(_UndoEntry(operations));
      _selectedContents = {};
      _invalidateEraserIndex();
      _markDirty();
    });
    _refreshPageStack(currentPage, page);
  }

  void _duplicateSelection() {
    if (_activeTool != EditingTool.SELECT || _selectedContents.isEmpty) return;

    final page = _file!.pages![currentPage];
    final duplicates = duplicateSelectedContents(page, _selectedContents);
    if (duplicates.isEmpty) return;

    setState(() {
      _addCopiesToUndoStack(page, duplicates);
      _selectedContents = duplicates
          .map((duplicate) => duplicate.content)
          .toSet();
      _copiedContents = duplicates
          .map(
            (duplicate) => (
              layer: duplicate.layer,
              content: duplicate.content.translatedBy(Offset.zero),
            ),
          )
          .toList();
      _invalidateEraserIndex();
      _markDirty();
    });
    _refreshPageStack(currentPage, page);
  }

  bool _canPasteSelection(XppPage page) {
    final copiedContents = _copiedContents;
    if (copiedContents == null || copiedContents.isEmpty) return false;
    final layers = page.layers ?? <XppLayer>[];
    return copiedContents.every((copied) => layers.contains(copied.layer));
  }

  Rect? _visibleCurrentPageBounds(XppPage page) {
    final viewport = _pagesViewportKey.currentContext?.findRenderObject();
    final pageBox = _pageItemKeys[currentPage]?.currentContext
        ?.findRenderObject();
    if (viewport is! RenderBox || pageBox is! RenderBox) return null;

    final viewportInPage = Rect.fromPoints(
      pageBox.globalToLocal(viewport.localToGlobal(Offset.zero)),
      pageBox.globalToLocal(
        viewport.localToGlobal(viewport.size.bottomRight(Offset.zero)),
      ),
    );
    final visible = viewportInPage.intersect(Offset.zero & pageBox.size);
    if (visible.isEmpty) return null;

    final pageSize = page.pageSize!.toSize();
    return Rect.fromLTRB(
      visible.left * pageSize.width / pageBox.size.width,
      visible.top * pageSize.height / pageBox.size.height,
      visible.right * pageSize.width / pageBox.size.width,
      visible.bottom * pageSize.height / pageBox.size.height,
    );
  }

  void _pasteSelection() {
    final page = _file!.pages![currentPage];
    final copiedContents = _copiedContents;
    if (copiedContents == null || !_canPasteSelection(page)) return;

    final visiblePageBounds = _visibleCurrentPageBounds(page);
    if (visiblePageBounds == null) return;
    Rect? copiedBounds;
    for (final copied in copiedContents) {
      final bounds = copied.content.selectionBounds;
      if (bounds == null || bounds.isEmpty) continue;
      copiedBounds = copiedBounds?.expandToInclude(bounds) ?? bounds;
    }
    if (copiedBounds == null) return;
    final pageSize = page.pageSize!.toSize();
    final offset = pasteOffsetForVisiblePage(
      copiedBounds,
      visiblePageBounds,
      Offset.zero & pageSize,
    );

    final pasted = pasteCopiedContents(page, copiedContents, offset: offset);
    if (pasted.isEmpty) return;

    setState(() {
      _addCopiesToUndoStack(page, pasted);
      _selectedContents = pasted.map((copy) => copy.content).toSet();
      _copiedContents = pasted
          .map(
            (copy) => (
              layer: copy.layer,
              content: copy.content.translatedBy(Offset.zero),
            ),
          )
          .toList();
      _invalidateEraserIndex();
      _markDirty();
    });
    _refreshPageStack(currentPage, page);
  }

  void _addCopiesToUndoStack(
    XppPage page,
    List<({XppLayer layer, XppContent content, int index})> copies,
  ) {
    _undoStack.add(
      _UndoEntry(
        copies
            .map(
              (copy) => _LayerOperation.added(
                page: page,
                layer: copy.layer,
                content: copy.content,
                index: copy.index,
              ),
            )
            .toList(),
      ),
    );
  }

  bool _shouldMoveSelection(Offset position) {
    if (_activeTool != EditingTool.SELECT || _selectedContents.isEmpty) {
      return false;
    }

    return _selectedContents.any((content) {
      final bounds = content.selectionBounds;
      return bounds != null && bounds.inflate(6).contains(position);
    });
  }

  void _moveSelection(Offset delta, {bool done = false}) {
    if (_activeTool != EditingTool.SELECT || _selectedContents.isEmpty) return;

    _selectionMoveOriginals ??= _selectionMoveStartData();
    _selectionTranslation.value += delta;
    if (!done) return;
    final total = _selectionTranslation.value;
    if (total == Offset.zero) {
      _cancelSelectionMove();
      return;
    }
    final selected = <XppContent>{};
    for (final original in _selectionMoveOriginals!) {
      final content = original.layer.content!;
      if (original.index >= content.length ||
          !identical(content[original.index], original.content))
        continue;
      final translated = original.content.translatedBy(total);
      content[original.index] = translated;
      selected.add(translated);
    }
    _selectionTranslation.value = Offset.zero;
    _selectedContents = selected;
    _invalidateEraserIndex();
    _finishSelectionMove();
    _refreshPageStack(currentPage, _file!.pages![currentPage]);
  }

  void _cancelSelectionMove() {
    _selectionMoveOriginals = null;
    _selectionTranslation.value = Offset.zero;
  }

  List<_SelectionMoveOriginal> _selectionMoveStartData() {
    final originals = <_SelectionMoveOriginal>[];
    final page = _file!.pages![currentPage];

    for (final layer in page.layers ?? <XppLayer>[]) {
      final content = layer.content ?? <XppContent?>[];
      for (var index = 0; index < content.length; index++) {
        final item = content[index];
        if (item == null || !_selectedContents.contains(item)) continue;
        originals.add(
          _SelectionMoveOriginal(
            page: page,
            layer: layer,
            content: item,
            index: index,
          ),
        );
      }
    }

    return originals;
  }

  void _finishSelectionMove() {
    final originals = _selectionMoveOriginals;
    _selectionMoveOriginals = null;
    if (originals == null || originals.isEmpty) return;

    final operations = <_LayerOperation>[];
    for (final original in originals) {
      final movedContent = original.layer.content?[original.index];
      if (movedContent == null || identical(movedContent, original.content)) {
        continue;
      }
      operations.add(
        _LayerOperation.removed(
          page: original.page,
          layer: original.layer,
          content: original.content,
          index: original.index,
        ),
      );
      operations.add(
        _LayerOperation.added(
          page: original.page,
          layer: original.layer,
          content: movedContent,
          index: original.index,
        ),
      );
    }

    if (operations.isNotEmpty) {
      setState(() {
        _undoStack.add(_UndoEntry(operations));
        _markDirty();
      });
    }
  }

  void _eraseContentAlongPath({List<Offset>? coordinates, double? radius}) {
    if (coordinates == null || coordinates.isEmpty || radius == null) return;

    final page = _file!.pages![currentPage];
    final operations = <_LayerOperation>[];
    for (final layer in page.layers ?? <XppLayer>[]) {
      final eraserIndex = _eraserIndexForLayer(layer);
      final eraseCandidates = <XppContent, List<Offset>>{};
      for (final coordinate in coordinates) {
        for (final candidate in eraserIndex.query(
          Rect.fromCircle(center: coordinate, radius: radius / 2),
        )) {
          (eraseCandidates[candidate] ??= []).add(coordinate);
        }
      }
      if (eraseCandidates.isEmpty) continue;

      final updatedContent = <XppContent?>[];
      var erasedFromLayer = false;
      for (var index = 0; index < layer.content!.length; index++) {
        final content = layer.content![index];
        if (content == null || !eraseCandidates.containsKey(content)) {
          updatedContent.add(content);
          continue;
        }

        final delta = _eraseContentWithPath(
          content: content,
          coordinates: eraseCandidates[content]!,
          radius: radius,
        );
        if (!delta.affected) {
          updatedContent.add(content);
          continue;
        }

        erasedFromLayer = true;
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
      }
      if (erasedFromLayer) layer.content = updatedContent;
    }

    if (operations.isEmpty) return;

    _undoStack.add(_UndoEntry(operations));
    _markDirty();
    _refreshPageStack(currentPage, page);
    setState(() {});
  }

  XppContentEraseData _eraseContentWithPath({
    required XppContent content,
    required List<Offset> coordinates,
    required double radius,
  }) {
    if (content is XppStroke)
      return content.eraseAlongPath(coordinates, radius);
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
    return _eraserIndexes.putIfAbsent(
      layer,
      () => _EraserContentIndex.fromContent(layer.content),
    );
  }

  void _invalidateEraserIndex() {
    _selectionIndexes.clear();
    _eraserIndexes.clear();
  }

  void shareScreenshot() async {
    Uint8List imageBytes = await _currentPagePng();
    if (!mounted) return;
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).successfullyShared + ' ' + fileName),
      ),
    );
  }

  Future<void> exportPdf() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    _clearSnackBars(scaffoldMessenger);
    final exportSnackBar = _showSnackBar(
      scaffoldMessenger,
      SnackBar(
        content: Text('Exporting PDF...'),
        duration: Duration(days: 999),
      ),
    );

    try {
      final (:pdfBytes, :fileName) = await _buildPdfExport();
      final savedPath = await XppPickedFile(
        pdfBytes,
        fileExtension: '.pdf',
        path: '/export/$fileName',
        fileName: fileName,
      ).exportToStorage();

      if (!mounted) return;
      _closeSnackBar(exportSnackBar);
      _removeCurrentSnackBar(scaffoldMessenger);
      _showSnackBar(
        scaffoldMessenger,
        SnackBar(
          content: Text(
            '${S.of(context).successfullySaved} ${savedPath ?? fileName}',
          ),
        ),
      );
    } on PdfExportException catch (error) {
      if (!mounted) return;
      _closeSnackBar(exportSnackBar);
      _removeCurrentSnackBar(scaffoldMessenger);
      _showSnackBar(scaffoldMessenger, SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      _closeSnackBar(exportSnackBar);
      _removeCurrentSnackBar(scaffoldMessenger);
      _showSnackBar(
        scaffoldMessenger,
        SnackBar(
          content: Text(
            S.of(context).unfortunatelyThereWasAnErrorSavingThisFile,
          ),
        ),
      );
    }
  }

  Future<void> sharePdf() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (!_sharePdfSupported) {
      _showSnackBar(
        scaffoldMessenger,
        SnackBar(
          content: Text('PDF sharing is not supported on this platform.'),
        ),
      );
      return;
    }

    _clearSnackBars(scaffoldMessenger);
    final exportSnackBar = _showSnackBar(
      scaffoldMessenger,
      SnackBar(
        content: Text('Exporting PDF...'),
        duration: Duration(days: 999),
      ),
    );

    try {
      final (:pdfBytes, :fileName) = await _buildPdfExport();

      if (!mounted) return;
      _closeSnackBar(exportSnackBar);
      _removeCurrentSnackBar(scaffoldMessenger);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              pdfBytes,
              mimeType: 'application/pdf',
              name: fileName,
            ),
          ],
        ),
      );
    } on PdfExportException catch (error) {
      if (!mounted) return;
      _closeSnackBar(exportSnackBar);
      _removeCurrentSnackBar(scaffoldMessenger);
      _showSnackBar(scaffoldMessenger, SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      _closeSnackBar(exportSnackBar);
      _removeCurrentSnackBar(scaffoldMessenger);
      _showSnackBar(
        scaffoldMessenger,
        SnackBar(
          content: Text('Unfortunately, there was an error sharing the PDF.'),
        ),
      );
    }
  }

  bool get _sharePdfSupported {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      TargetPlatform.fuchsia || TargetPlatform.linux => false,
    };
  }

  Future<({Uint8List pdfBytes, String fileName})> _buildPdfExport() async {
    final pdfBytes = await exportPdfDocument(
      _file!,
      pdfResolver: (background) async {
        final filename = background.filename;
        if (filename != null && filename.isNotEmpty) {
          try {
            return await XppPickedFile.fromInternalPath(path: filename);
          } catch (_) {
            // Fall through to the missing-file callback below.
          }
        }
        return background.onUnavailable(context, filename);
      },
    );
    final title = _file?.title ?? S.of(context).newFile;
    final fileName = annotatedPdfFileName(title);
    return (pdfBytes: pdfBytes, fileName: fileName);
  }

  void _clearSnackBars(ScaffoldMessengerState scaffoldMessenger) {
    try {
      scaffoldMessenger.removeCurrentSnackBar();
      scaffoldMessenger.clearSnackBars();
    } catch (_) {}
  }

  void _removeCurrentSnackBar(ScaffoldMessengerState scaffoldMessenger) {
    try {
      scaffoldMessenger.removeCurrentSnackBar();
    } catch (_) {}
  }

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _showSnackBar(
    ScaffoldMessengerState scaffoldMessenger,
    SnackBar snackBar,
  ) {
    try {
      return scaffoldMessenger.showSnackBar(snackBar);
    } catch (_) {
      return null;
    }
  }

  void _closeSnackBar(
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? snackBar,
  ) {
    try {
      snackBar?.close();
    } catch (_) {}
  }

  Future<bool> saveFile({bool saveAs = false}) async {
    if (savingFile) return false;
    setState(() {
      savingFile = true;
    });
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.removeCurrentSnackBar();
    scaffoldMessenger.clearSnackBars();
    final savingSnackBar = scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(S.of(context).savingFile),
        duration: Duration(days: 999),
      ),
    );
    try {
      if (_file!.title == null) {
        final titleApplied = await _showTitleDialog();
        if (!titleApplied || _file!.title == null) {
          if (mounted) {
            savingSnackBar.close();
            scaffoldMessenger.removeCurrentSnackBar();
            setState(() {
              savingFile = false;
            });
          }
          return false;
        }
      }
      String path = _file!.title! + '.xopp';
      _file!.previewImage = kIsWeb
          ? kTransparentImage
          : await _currentPagePng();
      XppPickedFile file = _file!.toXppPickedFile(filePath: path);
      final savedRevision = _revision;
      final savedPath = !saveAs && filePath != null
          ? await file
                .saveToPath(path: filePath!)
                .timeout(_saveOverwriteTimeout)
          : await file.exportToStorage();
      if (savedPath == null) {
        if (mounted) {
          savingSnackBar.close();
          scaffoldMessenger.removeCurrentSnackBar();
          setState(() {
            savingFile = false;
          });
        }
        return false;
      }
      filePath = savedPath;

      await RecentFiles.remember(
        path: savedPath,
        name: _file!.title!,
        preview: _file!.previewImage,
        modified: DateTime.now(),
        currentPage: currentPage,
      );

      if (!mounted) return false;
      savingSnackBar.close();
      scaffoldMessenger.removeCurrentSnackBar();
      setState(() {
        savingFile = false;
        _savedRevision = savedRevision;
      });
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(S.of(context).successfullySaved)),
      );
      return !_isDirty;
    } catch (error) {
      if (!mounted) return false;
      savingSnackBar.close();
      scaffoldMessenger.removeCurrentSnackBar();
      setState(() => savingFile = false);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            S.of(context).unfortunatelyThereWasAnErrorSavingThisFile,
          ),
        ),
      );
      return false;
    }
  }

  @override
  void dispose() {
    _backgroundRenderCommitTimer?.cancel();
    _viewportInteractionIdleTimer?.cancel();
    _deferPdfRasterUpdates.dispose();
    _selectionTranslation.dispose();
    _invalidatePrefetch();
    _navigationGeneration++;
    _pinchGeneration++;
    _zoomAnimationController.dispose();
    _pagesScrollController.dispose();
    _pagesHorizontalScrollController.dispose();
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
      if (!mounted) return;
      setState(() {
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
        drawWithStylusOnly =
            prefs.getBool(PreferencesKeys.kDrawWithStylusOnly) ??
            drawWithStylusOnly;
      });
      _scheduleInputModeRefresh();
    });
  }
}

class _UndoEntry {
  final List<_LayerOperation> operations;

  _UndoEntry(this.operations);

  XppPage get page => operations.first.page;
}

enum _UnsavedChangesAction { save, discard, cancel }

class _TopScrollPosition {
  const _TopScrollPosition({required this.pageIndex, required this.pageY});

  final int pageIndex;
  final double pageY;
}

class _ViewportPinchMetrics {
  const _ViewportPinchMetrics({
    required this.focalPoint,
    required this.distance,
  });

  final Offset focalPoint;
  final double distance;
}

class _SelectionMoveOriginal {
  final XppPage page;
  final XppLayer layer;
  final XppContent content;
  final int index;

  _SelectionMoveOriginal({
    required this.page,
    required this.layer,
    required this.content,
    required this.index,
  });
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

class _PinchAnchor {
  final XppPage page;
  final Offset fraction;

  const _PinchAnchor({required this.page, required this.fraction});
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
