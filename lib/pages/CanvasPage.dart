import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:xournalpp/src/XppPickedFile.dart';
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

class CanvasPage extends StatefulWidget {
  CanvasPage({Key? key, this.file, this.filePath, this.initialPage = 0})
    : super(key: key);

  final XppFile? file;
  final String? filePath;
  final int initialPage;

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
  static const Duration _zoomAnimationDuration = Duration(milliseconds: 180);

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
  Animation<double>? _zoomAnimation;
  _ViewportAnchor? _zoomAnimationAnchor;

  double pageScale = 1;
  double _lastViewportWidth = 0;

  bool savingFile = false;
  bool _allowPop = false;
  bool _currentPageUpdateScheduled = false;
  bool _pdfBackgroundPrefetchScheduled = false;
  int _pdfBackgroundPrefetchGeneration = 0;
  int _revision = 0;
  int _savedRevision = 0;

  _EraserContentIndex? _eraserIndex;
  final List<_UndoEntry> _undoStack = [];
  Set<XppContent> _selectedContents = {};
  List<_SelectionMoveOriginal>? _selectionMoveOriginals;

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
    _scheduleInputModeRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToPage(currentPage, animated: false);
      _schedulePdfBackgroundPrefetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop || !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!await _confirmLeave()) return;
        _allowPop = true;
        if (!context.mounted) return;
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop(result);
        } else {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        drawer: MainDrawer(onLeaveRequested: _confirmLeave),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'ZoomArea',
              child: _buildScrollablePages(),
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
              onBackgroundSettings: _showBackgroundSettings,
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
            constraints: BoxConstraints(maxHeight: 72),
            child: Center(
              child: XppPagesBrowser(
                currentPage: currentPage,
                pageCount: _file!.pages!.length,
                onPageChange: _switchToPage,
                onPageAdd: _addPageAfterCurrent,
                onPageDelete: () => _deletePage(currentPage),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setMetadata() {
    _file = widget.file;
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
          _pageDisplayWidth(constraints.maxWidth) + _pageHorizontalPadding * 2,
        );
        return Listener(
          behavior: HitTestBehavior.translucent,
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
                  _scheduleCurrentPageFromScroll();
                  return false;
                },
                child: ListView.builder(
                  controller: _pagesScrollController,
                  physics: _viewportScrollPhysics,
                  padding: const EdgeInsets.symmetric(vertical: _pageGap),
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
    _panPages(-event.scrollDelta);
  }

  Widget _buildScrollablePage(
    BuildContext context,
    int pageIndex,
    double viewportWidth,
  ) {
    final page = _file!.pages![pageIndex];
    final displayWidth = _pageDisplayWidth(viewportWidth);
    final displayHeight = displayWidth / page.pageSize!.ratio;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final isActivePage = pageIndex == currentPage;
    final shouldRenderFullQuality = (pageIndex - currentPage).abs() <= 1;

    return Padding(
      padding: const EdgeInsets.only(
        left: _pageHorizontalPadding,
        right: _pageHorizontalPadding,
        bottom: _pageGap,
      ),
      child: Center(
        child: Card(
          elevation: isActivePage ? 12 : 6,
          color: Colors.white,
          child: SizedBox(
            key: _pageItemKeyFor(pageIndex),
            width: displayWidth,
            height: displayHeight,
            child: FittedBox(
              child: PointerListener(
                key: _pointerListenerKeyFor(pageIndex),
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
                  child: XppPageStack(
                    key: _pageStackKeyFor(pageIndex),
                    page: page,
                    rasterScale: pageScale,
                    keepAlive: false,
                    fullQualityBackground: shouldRenderFullQuality,
                    backgroundTargetPixelWidth: displayWidth * devicePixelRatio,
                    backgroundTargetPixelHeight:
                        displayHeight * devicePixelRatio,
                    activeTool: isActivePage ? _activeTool : null,
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
                    onReplaceContent: (layer, oldContent, newContent) {
                      _activatePageForEditing(pageIndex);
                      _replaceContent(layer, oldContent, newContent);
                    },
                    onContentPointerDown: (event) => _pointerListenerKeyFor(
                      pageIndex,
                    ).currentState?.markContentPointerDown(event),
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

  void _clearPageWidgetKeys() {
    _pageStackKeys.clear();
    _pointerListenerKeys.clear();
    _pageItemKeys.clear();
  }

  void _activatePageForEditing(int pageIndex) {
    _setCurrentPage(pageIndex);
  }

  void _setCurrentPage(int pageIndex) {
    final pages = _file?.pages;
    if (pages == null || pages.isEmpty) return;
    if (pageIndex < 0 || pageIndex >= pages.length) return;
    if (pageIndex == currentPage) return;

    setState(() {
      currentPage = pageIndex;
      _selectedContents = {};
      _invalidateEraserIndex();
    });
    _schedulePdfBackgroundPrefetch();
  }

  void _schedulePdfBackgroundPrefetch() {
    if (_pdfBackgroundPrefetchScheduled) return;
    _pdfBackgroundPrefetchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pdfBackgroundPrefetchScheduled = false;
      if (mounted) _prefetchPdfBackgroundWindow();
    });
  }

  void _prefetchPdfBackgroundWindow() {
    final pages = _file?.pages;
    if (pages == null || pages.isEmpty) return;

    final generation = ++_pdfBackgroundPrefetchGeneration;
    final fullQualityPages = <int>{
      for (var i = currentPage - 1; i <= currentPage + 1; i++)
        if (i >= 0 && i < pages.length) i,
    };

    for (final pageIndex in [currentPage, currentPage - 1, currentPage + 1]) {
      if (!fullQualityPages.contains(pageIndex)) continue;
      unawaited(
        _prefetchPdfBackgroundPage(
          pageIndex,
          PdfBackgroundRenderVariant.full,
          generation,
        ),
      );
    }
  }

  Future<void> _prefetchPdfBackgroundPage(
    int pageIndex,
    PdfBackgroundRenderVariant variant,
    int generation,
  ) async {
    final pages = _file?.pages;
    if (pages == null || pageIndex < 0 || pageIndex >= pages.length) return;

    final background = pages[pageIndex].background;
    if (background is! XppBackgroundPdf) return;
    final filename = background.filename;
    if (filename == null || filename.isEmpty) return;

    try {
      final source = await pdfBackgroundRenderService.sourceForPath(
        filename,
        fallback: () => XppPickedFile.fromInternalPath(path: filename),
      );
      if (!mounted || generation != _pdfBackgroundPrefetchGeneration) return;
      final pageSize = pages[pageIndex].pageSize!.toSize();
      final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      await pdfBackgroundRenderService.request(
        source,
        background.page,
        variant,
        targetWidth: pageSize.width * pageScale * devicePixelRatio,
        targetHeight: pageSize.height * pageScale * devicePixelRatio,
        priority: pageIndex == currentPage
            ? PdfBackgroundRenderPriority.active
            : PdfBackgroundRenderPriority.prefetch,
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

    final offset = _pageScrollOffset(pageIndex);
    final maxOffset = _pagesScrollController.position.maxScrollExtent;
    final target = offset.clamp(0.0, maxOffset).toDouble();
    if (animated) {
      _pagesScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pagesScrollController.jumpTo(target);
    }
  }

  void _panPages(Offset delta) {
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

  _ViewportAnchor? _currentViewportAnchor() {
    final viewportObject = _pagesViewportKey.currentContext?.findRenderObject();
    if (viewportObject is! RenderBox) return null;
    if (!_pagesScrollController.hasClients ||
        !_pagesHorizontalScrollController.hasClients) {
      return null;
    }

    final pageObject = _pageItemKeys[currentPage]?.currentContext
        ?.findRenderObject();
    if (pageObject is! RenderBox || !pageObject.attached) return null;

    final viewportTopLeft = viewportObject.localToGlobal(Offset.zero);
    final viewportCenter =
        viewportTopLeft + viewportObject.size.center(Offset.zero);
    final pageTopLeft = pageObject.localToGlobal(Offset.zero);

    return _ViewportAnchor(
      pageIndex: currentPage,
      relativeX: ((viewportCenter.dx - pageTopLeft.dx) / pageObject.size.width)
          .clamp(0.0, 1.0),
      relativeY: ((viewportCenter.dy - pageTopLeft.dy) / pageObject.size.height)
          .clamp(0.0, 1.0),
    );
  }

  void _restoreViewportAnchor(_ViewportAnchor anchor) {
    final viewportObject = _pagesViewportKey.currentContext?.findRenderObject();
    if (viewportObject is! RenderBox) return;
    if (!_pagesScrollController.hasClients ||
        !_pagesHorizontalScrollController.hasClients) {
      return;
    }

    final pageObject = _pageItemKeys[anchor.pageIndex]?.currentContext
        ?.findRenderObject();
    if (pageObject is! RenderBox || !pageObject.attached) return;

    final viewportTopLeft = viewportObject.localToGlobal(Offset.zero);
    final viewportCenter =
        viewportTopLeft + viewportObject.size.center(Offset.zero);
    final pageTopLeft = pageObject.localToGlobal(Offset.zero);
    final anchoredPoint = Offset(
      pageTopLeft.dx + pageObject.size.width * anchor.relativeX,
      pageTopLeft.dy + pageObject.size.height * anchor.relativeY,
    );
    final delta = anchoredPoint - viewportCenter;

    final vertical = _pagesScrollController.position;
    _pagesScrollController.jumpTo(
      (vertical.pixels + delta.dy)
          .clamp(vertical.minScrollExtent, vertical.maxScrollExtent)
          .toDouble(),
    );

    final horizontal = _pagesHorizontalScrollController.position;
    _pagesHorizontalScrollController.jumpTo(
      (horizontal.pixels + delta.dx)
          .clamp(horizontal.minScrollExtent, horizontal.maxScrollExtent)
          .toDouble(),
    );
  }

  double _pageScrollOffset(int pageIndex) {
    return _pageScrollOffsetForScale(pageIndex, pageScale);
  }

  double _pageScrollOffsetForScale(int pageIndex, double scale) {
    final pages = _file?.pages ?? <XppPage>[];
    final displayWidth = _pageDisplayWidthForScale(_lastViewportWidth, scale);
    var offset = _pageGap;
    for (var i = 0; i < pageIndex && i < pages.length; i++) {
      offset += displayWidth / pages[i].pageSize!.ratio + _pageGap;
    }
    return offset;
  }

  double _estimatedPageExtent(double viewportWidth) {
    final pages = _file?.pages;
    if (pages == null || pages.isEmpty) return 800;
    final displayWidth = _pageDisplayWidth(viewportWidth);
    return displayWidth / pages[currentPage].pageSize!.ratio + _pageGap;
  }

  double _pageDisplayWidth(double viewportWidth) {
    return _pageDisplayWidthForScale(viewportWidth, pageScale);
  }

  double _pageDisplayWidthForScale(double viewportWidth, double scale) {
    return max(1.0, viewportWidth - _pageHorizontalPadding * 2) * scale;
  }

  void _refreshPageStack(int pageIndex, XppPage page) {
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
    final layer = page.layers![0];
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
    _eraserIndex?.add(newContent);

    _refreshPageStack(pageIndex, page);
  }

  bool get _isDirty => _revision != _savedRevision;

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

  ScrollPhysics get _viewportScrollPhysics => _canPanViewport
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

    _zoomAnimationController.stop();
    _zoomAnimationAnchor = _currentViewportAnchor();
    _zoomAnimation = Tween<double>(begin: pageScale, end: newZoom).animate(
      CurvedAnimation(parent: _zoomAnimationController, curve: Curves.easeOut),
    );
    _zoomAnimationController.forward(from: 0);
  }

  void _handleZoomAnimationTick() {
    final animation = _zoomAnimation;
    if (animation == null) return;

    setState(() => pageScale = animation.value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchor = _zoomAnimationAnchor;
      if (anchor != null) {
        _restoreViewportAnchor(anchor);
      } else {
        _scrollToPage(currentPage, animated: false);
      }
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
          page.pageSize = pageSizes[i];
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

    if (delta != Offset.zero) {
      final translatedSelection = <XppContent>{};
      final page = _file!.pages![currentPage];

      for (final layer in page.layers ?? <XppLayer>[]) {
        final content = List<XppContent?>.from(layer.content ?? []);
        var changedLayer = false;

        for (var index = 0; index < content.length; index++) {
          final item = content[index];
          if (item == null || !_selectedContents.contains(item)) continue;

          final translated = item.translatedBy(delta);
          content[index] = translated;
          translatedSelection.add(translated);
          changedLayer = true;
        }

        if (changedLayer) layer.content = content;
      }

      setState(() {
        _selectedContents = translatedSelection;
        _invalidateEraserIndex();
        _markDirty();
      });
      _refreshPageStack(currentPage, page);
    }

    if (done) _finishSelectionMove();
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
    _markDirty();
    _refreshPageStack(currentPage, page);
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
    Uint8List imageBytes = await _currentPagePng();
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
      _showSnackBar(
        scaffoldMessenger,
        SnackBar(content: Text(error.message)),
      );
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
      _showSnackBar(
        scaffoldMessenger,
        SnackBar(content: Text(error.message)),
      );
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
    final fileName = title.endsWith('.pdf') ? title : '$title.pdf';
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

      final prefs = await SharedPreferences.getInstance();
      String jsonData = prefs.getString(PreferencesKeys.kRecentFiles) ?? '[]';
      Set files = (jsonDecode(jsonData) as Iterable).toSet();
      files.removeWhere((element) => element['path'] == savedPath);
      files.add({
        'preview': base64Encode(_file!.previewImage!),
        'name': _file!.title,
        'path': savedPath,
        'modified': DateTime.now().toIso8601String(),
        'currentPage': currentPage,
      });
      jsonData = jsonEncode(files.toList());
      await prefs.setString(PreferencesKeys.kRecentFiles, jsonData);

      if (!mounted) return false;
      savingSnackBar.close();
      scaffoldMessenger.removeCurrentSnackBar();
      setState(() {
        savingFile = false;
        _savedRevision = _revision;
      });
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(S.of(context).successfullySaved)),
      );
      return true;
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
    _pdfBackgroundPrefetchGeneration++;
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

class _ViewportAnchor {
  const _ViewportAnchor({
    required this.pageIndex,
    required this.relativeX,
    required this.relativeY,
  });

  final int pageIndex;
  final double relativeX;
  final double relativeY;
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
