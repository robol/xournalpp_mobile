import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show ValueListenable, visibleForTesting, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:xournalpp/src/RasterWorkQueue.dart';
import 'package:xournalpp/src/ContentSpatialIndex.dart';
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/PdfBackgroundRenderService.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/RasterImageCache.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPageContentWidget.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

class XppPageStack extends StatefulWidget {
  @visibleForTesting
  static Future<ui.Image> Function(ui.Picture, int, int)? debugRasterizePicture;

  @visibleForTesting
  static int? debugMaxActiveRasterBytes;

  final XppPage? page;
  final double rasterScale;
  final void Function(
    XppLayer layer,
    XppContent oldContent,
    XppContent newContent,
  )?
  onReplaceContent;
  final void Function(PointerDownEvent event)? onContentPointerDown;
  final EditingTool? activeTool;
  final Set<XppContent> selectedContents;
  final ValueListenable<Offset>? selectionTranslation;
  final void Function(XppLayer layer, XppContent content)? onSelectContent;
  final VoidCallback? onDuplicateSelection;
  final VoidCallback? onDeleteSelection;
  final bool keepAlive;
  final double? backgroundTargetPixelWidth;
  final double? backgroundTargetPixelHeight;
  final ValueListenable<bool>? deferBackgroundRasterUpdates;

  const XppPageStack({
    Key? key,
    this.page,
    this.rasterScale = 1,
    this.onReplaceContent,
    this.onContentPointerDown,
    this.activeTool,
    this.selectedContents = const {},
    this.selectionTranslation,
    this.onSelectContent,
    this.onDuplicateSelection,
    this.onDeleteSelection,
    this.keepAlive = true,
    this.backgroundTargetPixelWidth,
    this.backgroundTargetPixelHeight,
    this.deferBackgroundRasterUpdates,
  }) : super(key: key);

  @override
  XppPageStackState createState() => XppPageStackState();
}

class XppPageStackState extends State<XppPageStack>
    with AutomaticKeepAliveClientMixin {
  GlobalKey pngKey = GlobalKey();
  XppPage? page;

  XppBackground? _lastKnownBackground;
  Widget background = Container();

  @override
  void initState() {
    page = widget.page;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    List<Widget> children = [];

    final pageBackground = page!.background;
    if (pageBackground == null) {
      _lastKnownBackground = null;
      background = const SizedBox.shrink();
    } else if (_lastKnownBackground != pageBackground) {
      _lastKnownBackground = pageBackground;
      final pageSize = page!.pageSize!.toSize();
      final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      final targetPixelWidth =
          widget.backgroundTargetPixelWidth ??
          pageSize.width * widget.rasterScale * devicePixelRatio;
      final targetPixelHeight =
          widget.backgroundTargetPixelHeight ??
          pageSize.height * widget.rasterScale * devicePixelRatio;
      background = pageBackground.render(
        deferRasterUpdates: widget.deferBackgroundRasterUpdates,
        targetPixelWidth: targetPixelWidth,
        targetPixelHeight: targetPixelHeight,
        pageWidthPoints: pageSize.width,
        pageHeightPoints: pageSize.height,
      );
    }
    children.add(const Positioned.fill(child: ColoredBox(color: Colors.white)));
    children.add(Positioned.fill(child: background));

    children.addAll(
      page!.layers!.map(
        (e) => XppLayerStack(
          layer: e,
          pageSize: page!.pageSize!.toSize(),
          rasterScale: widget.rasterScale,
          onReplaceContent: widget.onReplaceContent,
          onContentPointerDown: widget.onContentPointerDown,
          activeTool: widget.activeTool,
          selectedContents: widget.selectedContents,
          selectionTranslation: widget.selectionTranslation,
          onSelectContent: widget.onSelectContent,
        ),
      ),
    );
    final selectionActions = _buildSelectionActions();
    if (selectionActions != null) {
      final translation = widget.selectionTranslation;
      children.add(
        translation == null
            ? selectionActions
            : ValueListenableBuilder<Offset>(
                valueListenable: translation,
                builder: (_, __, ___) =>
                    _buildSelectionActions() ?? const SizedBox.shrink(),
              ),
      );
    }
    return RepaintBoundary(
      key: pngKey,
      child: ImageRasterScale(
        scale: widget.rasterScale * MediaQuery.devicePixelRatioOf(context),
        child: Theme(
          data: Theme.of(context).copyWith(
            iconTheme: const IconThemeData(color: Colors.black),
            textTheme: Theme.of(context).textTheme.apply(
              bodyColor: Colors.black,
              displayColor: Colors.black,
            ),
            inputDecorationTheme: const InputDecorationTheme(
              labelStyle: TextStyle(color: Colors.black),
              helperStyle: TextStyle(color: Colors.black87),
            ),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.black),
            child: SizedBox(
              width: page!.pageSize!.width,
              height: page!.pageSize!.height,
              child: Stack(fit: StackFit.expand, children: children),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildSelectionActions() {
    if (widget.activeTool != EditingTool.SELECT ||
        widget.selectedContents.isEmpty ||
        (widget.onDuplicateSelection == null &&
            widget.onDeleteSelection == null)) {
      return null;
    }

    Rect? selectionBounds;
    for (final content in widget.selectedContents) {
      final bounds = content.selectionBounds;
      if (bounds == null || bounds.isEmpty) continue;
      selectionBounds = selectionBounds?.expandToInclude(bounds) ?? bounds;
    }
    if (selectionBounds == null) return null;
    selectionBounds = selectionBounds.shift(
      widget.selectionTranslation?.value ?? Offset.zero,
    );

    final pageSize = page!.pageSize!.toSize();
    const buttonSize = 32.0;
    const buttonGap = 6.0;
    final actionCount = [
      widget.onDuplicateSelection,
      widget.onDeleteSelection,
    ].whereType<VoidCallback>().length;
    final actionsWidth =
        buttonSize * actionCount + buttonGap * max(0, actionCount - 1);
    final left = (selectionBounds.right + 6)
        .clamp(0.0, max(0.0, pageSize.width - actionsWidth))
        .toDouble();
    final top = (selectionBounds.top - buttonSize - 6)
        .clamp(0.0, max(0.0, pageSize.height - buttonSize))
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      width: actionsWidth,
      height: buttonSize,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: widget.onContentPointerDown,
        child: Row(
          spacing: buttonGap,
          children: [
            if (widget.onDuplicateSelection != null)
              _buildSelectionActionButton(
                color: Theme.of(context).colorScheme.primary,
                tooltip: 'Duplicate selection',
                icon: Icons.content_copy,
                onPressed: widget.onDuplicateSelection!,
              ),
            if (widget.onDeleteSelection != null)
              _buildSelectionActionButton(
                color: Colors.redAccent,
                tooltip: 'Delete selection',
                icon: Icons.delete,
                onPressed: widget.onDeleteSelection!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionActionButton({
    required Color color,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox.square(
      dimension: 32,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        elevation: 3,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 18,
          color: Colors.white,
          tooltip: tooltip,
          icon: Icon(icon),
          onPressed: onPressed,
        ),
      ),
    );
  }

  void setPageData(XppPage pageData) {
    setState(() => page = pageData);
  }

  Future<Uint8List> toPng() async {
    RenderRepaintBoundary boundary =
        pngKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    ui.Image image = await boundary.toImage();
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null)
        throw StateError('Could not encode page preview as PNG.');
      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void didUpdateWidget(covariant XppPageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    final backgroundRenderChanged =
        _backgroundRenderSignature(widget) !=
            _backgroundRenderSignature(oldWidget) ||
        widget.deferBackgroundRasterUpdates !=
            oldWidget.deferBackgroundRasterUpdates;
    if (widget.page != oldWidget.page || backgroundRenderChanged) {
      setState(() {
        page = widget.page;
        _lastKnownBackground = null;
      });
    }
  }

  String? _backgroundRenderSignature(XppPageStack widget) {
    final page = widget.page;
    final background = page?.background;
    final pageSize = page?.pageSize?.toSize();
    if (background == null || pageSize == null) return null;

    final devicePixelRatio =
        MediaQuery.maybeDevicePixelRatioOf(context) ??
        View.of(context).devicePixelRatio;
    final targetPixelWidth =
        widget.backgroundTargetPixelWidth ??
        pageSize.width * widget.rasterScale * devicePixelRatio;
    final targetPixelHeight =
        widget.backgroundTargetPixelHeight ??
        pageSize.height * widget.rasterScale * devicePixelRatio;
    if (background is XppBackgroundPdf) {
      final size = pdfBackgroundRenderService.renderSizeFor(
        PdfBackgroundRenderVariant.full,
        targetWidth: targetPixelWidth,
        targetHeight: targetPixelHeight,
        pageWidthPoints: pageSize.width,
        pageHeightPoints: pageSize.height,
      );
      return '${identityHashCode(background)}|${size.cachePart}';
    }

    return '${identityHashCode(background)}|'
        '${targetPixelWidth.round()}x${targetPixelHeight.round()}';
  }
}

class XppLayerStack extends StatefulWidget {
  final XppLayer? layer;
  final Size pageSize;
  final double rasterScale;
  final void Function(
    XppLayer layer,
    XppContent oldContent,
    XppContent newContent,
  )?
  onReplaceContent;
  final void Function(PointerDownEvent event)? onContentPointerDown;
  final EditingTool? activeTool;
  final Set<XppContent> selectedContents;
  final ValueListenable<Offset>? selectionTranslation;
  final void Function(XppLayer layer, XppContent content)? onSelectContent;

  const XppLayerStack({
    Key? key,
    this.layer,
    required this.pageSize,
    required this.rasterScale,
    this.onReplaceContent,
    this.onContentPointerDown,
    this.activeTool,
    this.selectedContents = const {},
    this.selectionTranslation,
    this.onSelectContent,
  }) : super(key: key);
  @override
  _XppLayerStackState createState() => _XppLayerStackState();
}

class _XppLayerStackState extends State<XppLayerStack> {
  Map<XppContent, Widget> renderedContent = {};

  @override
  void didUpdateWidget(covariant XppLayerStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeTool != oldWidget.activeTool ||
        widget.selectedContents != oldWidget.selectedContents) {
      renderedContent.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final contents = widget.layer!.content!;
    final liveContents = contents.toSet();
    renderedContent.removeWhere(
      (content, _) => !liveContents.contains(content),
    );
    List<Widget> children = [];
    final selectableStrokes = <XppStroke>[];
    List<XppStroke> pendingStrokes = [];
    final selectionMode = widget.activeTool == EditingTool.SELECT;

    void flushPendingStrokes() {
      if (pendingStrokes.isEmpty) return;
      children.add(
        Positioned.fill(
          child: _translateSelected(
            widget.selectedContents.contains(pendingStrokes.first),
            _RasterizedStrokeRun(
              strokes: List<XppStroke>.unmodifiable(pendingStrokes),
              bounds: _strokeRasterBounds(pendingStrokes, widget.pageSize),
              pageSize: widget.pageSize,
              rasterScale: widget.rasterScale,
            ),
          ),
        ),
      );
      pendingStrokes = [];
    }

    widget.layer!.content!.forEach((element) {
      if (element == null) return;

      if (element is XppStroke) {
        if (pendingStrokes.isNotEmpty &&
            widget.selectedContents.contains(pendingStrokes.first) !=
                widget.selectedContents.contains(element))
          flushPendingStrokes();
        pendingStrokes.add(element);
        if (pendingStrokes.length >= 64) flushPendingStrokes();
        if (selectionMode) {
          selectableStrokes.add(element);
        }
        return;
      }

      flushPendingStrokes();
      if (!renderedContent.containsKey(element)) {
        renderedContent[element] = element.render(
          onReplace: (newContent) =>
              widget.onReplaceContent?.call(widget.layer!, element, newContent),
          onPointerDown: widget.onContentPointerDown,
          selectionMode: selectionMode,
          selected: widget.selectedContents.contains(element),
          onSelect: () => widget.onSelectContent?.call(widget.layer!, element),
        );
      }
      final child = renderedContent[element];
      if (child != null)
        children.add(
          Positioned(
            top: element.getOffset()?.dy ?? 0,
            left: element.getOffset()?.dx ?? 0,
            child: _translateSelected(
              widget.selectedContents.contains(element),
              child,
            ),
          ),
        );
    });
    flushPendingStrokes();
    if (selectionMode && selectableStrokes.isNotEmpty) {
      final index = ContentSpatialIndex(selectableStrokes);
      children.add(
        Positioned.fill(
          child: _StrokeHitRegion(
            contains: (position) => index
                .query(Rect.fromCircle(center: position, radius: 6))
                .isNotEmpty,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                final candidates = index.query(
                  Rect.fromCircle(center: event.localPosition, radius: 6),
                );
                if (candidates.isNotEmpty)
                  widget.onContentPointerDown?.call(event);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (event) {
                  final candidates = index.query(
                    Rect.fromCircle(center: event.localPosition, radius: 6),
                  );
                  for (final stroke in selectableStrokes.reversed) {
                    if (candidates.contains(stroke)) {
                      widget.onSelectContent?.call(widget.layer!, stroke);
                      break;
                    }
                  }
                },
                child: _translateSelected(
                  true,
                  CustomPaint(
                    painter: _StrokeSelectionPainter(
                      selectableStrokes
                          .where(widget.selectedContents.contains)
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Stack(children: children);
  }

  Widget _translateSelected(bool selected, Widget child) {
    final translation = widget.selectionTranslation;
    if (!selected || translation == null) return child;
    return ValueListenableBuilder<Offset>(
      valueListenable: translation,
      child: child,
      builder: (_, offset, child) =>
          Transform.translate(offset: offset, child: child),
    );
  }
}

class _StrokeSelectionPainter extends CustomPainter {
  _StrokeSelectionPainter(this.strokes);
  final List<XppStroke> strokes;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = XppPageContentWidget.selectionColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final stroke in strokes) {
      final bounds = stroke.eraseBounds;
      if (bounds != null)
        canvas.drawRect(bounds.inflate(6).deflate(.75), paint);
    }
  }

  @override
  bool shouldRepaint(_StrokeSelectionPainter oldDelegate) =>
      !listEquals(strokes, oldDelegate.strokes);
}

class _RasterizedStrokeRun extends StatefulWidget {
  final List<XppStroke> strokes;
  final Size pageSize;
  final Rect bounds;
  final double rasterScale;

  const _RasterizedStrokeRun({
    required this.strokes,
    required this.bounds,
    required this.pageSize,
    required this.rasterScale,
  });

  @override
  State<_RasterizedStrokeRun> createState() => _RasterizedStrokeRunState();
}

class _RasterizedStrokeRunState extends State<_RasterizedStrokeRun> {
  static final _workQueue = RasterWorkQueue();
  static final _cache = RasterImageCache<_StrokeRunKey>(
    maxBytes: 48 * 1024 * 1024,
  );

  // Count mounted handles conservatively, including handles also in the LRU.
  // Bound dense, interleaved pages even when many regions cover the same area.
  static int get _maxActiveBytes =>
      XppPageStack.debugMaxActiveRasterBytes ?? 64 * 1024 * 1024;
  static int _activeBytes = 0;
  static final _imageOwners = <_RasterizedStrokeRunState>{};

  int get _imageBytes =>
      _image == null ? 0 : _image!.width * _image!.height * 4;

  void _replaceImage(ui.Image? image) {
    _activeBytes -= _imageBytes;
    _image?.dispose();
    _image = image;
    _activeBytes += _imageBytes;
    _imageOwners.remove(this);
    if (image != null) _imageOwners.add(this);
  }

  bool _reserveImage(int bytes, {bool evictOffscreen = false}) {
    if (_activeBytes - _imageBytes + bytes <= _maxActiveBytes) return true;
    if (!evictOffscreen) return false;
    for (final owner in _imageOwners.toList()) {
      if (identical(owner, this) || !owner.mounted || owner._isVisible())
        continue;
      owner.setState(() {
        // Pending append jobs may hold this image as their base. Invalidate
        // their generation before releasing that handle.
        owner._generation++;
        owner._rasterizeTimer?.cancel();
        owner._rasterizeAfterCurrent = false;
        owner._replaceImage(null);
        owner._requestedSignature = null;
        owner._cachedSignature = null;
      });
      if (_activeBytes - _imageBytes + bytes <= _maxActiveBytes) return true;
    }
    // Keep exact vector rendering when the visible working set exceeds budget.
    return false;
  }

  ui.Image? _image;
  _StrokeRunKey? _requestedSignature;
  _StrokeRunKey? _cachedSignature;
  double _imagePixelRatio = 1;
  Size? _imagePageSize;
  Rect? _imageBounds;
  List<XppStroke> _cachedStrokeIdentities = const [];
  int _generation = 0;
  Timer? _rasterizeTimer;
  bool _rasterizationInProgress = false;
  bool _rasterizeAfterCurrent = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rasterizeIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _RasterizedStrokeRun oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rasterizeIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final cachedPrefixLength = _cachedPrefixLength(pageSize: widget.pageSize);

    if (image == null || cachedPrefixLength == null) {
      return CustomPaint(
        painter: _StrokeRunVectorPainter(widget.strokes),
        size: widget.pageSize,
      );
    }

    final children = <Widget>[
      Positioned.fromRect(
        rect: _imageBounds!,
        child: RawImage(
          image: image,
          width: _imageBounds!.width,
          height: _imageBounds!.height,
          fit: BoxFit.fill,
          scale: _imagePixelRatio,
          filterQuality: FilterQuality.medium,
        ),
      ),
    ];

    if (cachedPrefixLength < widget.strokes.length) {
      children.add(
        CustomPaint(
          painter: _StrokeRunVectorPainter(
            widget.strokes.sublist(cachedPrefixLength),
          ),
          size: widget.pageSize,
        ),
      );
    }

    return Stack(fit: StackFit.expand, children: children);
  }

  bool _isVisible() {
    if (!mounted) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final rect = Rect.fromPoints(
      box.localToGlobal(widget.bounds.topLeft),
      box.localToGlobal(widget.bounds.bottomRight),
    );
    return rect.overlaps(Offset.zero & MediaQuery.sizeOf(context));
  }

  void _rasterizeIfNeeded() {
    if (!mounted) return;
    final pixelRatio = _rasterPixelRatio();
    final signature = _strokeRunSignature(
      widget.strokes,
      widget.pageSize,
      pixelRatio,
    );
    if (_requestedSignature == signature) return;

    _requestedSignature = signature;
    final generation = ++_generation;
    final cached = _cache.get(signature);
    if (cached != null) {
      _rasterizeTimer?.cancel();
      if (!_reserveImage(cached.width * cached.height * 4)) {
        cached.dispose();
        _requestedSignature = null;
        return;
      }
      _replaceImage(cached);
      _imagePixelRatio = pixelRatio;
      _imagePageSize = widget.pageSize;
      _imageBounds = widget.bounds;
      _cachedSignature = signature;
      _cachedStrokeIdentities = widget.strokes;
      return;
    }
    if (_rasterizationInProgress) {
      _rasterizeAfterCurrent = true;
      _rasterizeTimer?.cancel();
      return;
    }

    final strokes = List<XppStroke>.unmodifiable(widget.strokes);
    final cachedPrefixLength = _cachedPrefixLength(
      pageSize: widget.pageSize,
      pixelRatio: pixelRatio,
    );
    final baseImage =
        cachedPrefixLength == null || cachedPrefixLength >= strokes.length
        ? null
        : _image;

    _rasterizeTimer?.cancel();
    _rasterizeTimer = Timer(const Duration(milliseconds: 120), () {
      _workQueue.schedule(
        isCurrent: () => mounted && generation == _generation,
        isVisible: _isVisible,
        run: () => _startRasterization(
          strokes,
          widget.pageSize,
          pixelRatio,
          signature,
          generation,
          baseImage,
          cachedPrefixLength,
        ),
      );
    });
  }

  Future<void> _startRasterization(
    List<XppStroke> strokes,
    Size pageSize,
    double pixelRatio,
    _StrokeRunKey signature,
    int generation,
    ui.Image? baseImage,
    int? cachedPrefixLength,
  ) async {
    final outputBytes =
        (signature.bounds.width * pixelRatio).ceil() *
        (signature.bounds.height * pixelRatio).ceil() *
        4;
    if (!_reserveImage(outputBytes, evictOffscreen: true)) {
      _requestedSignature = null;
      return;
    }
    _rasterizationInProgress = true;
    final trace = developer.TimelineTask()
      ..start(
        'stroke raster',
        arguments: {
          'strokes': strokes.length,
          'outputBytes':
              (signature.bounds.width * pixelRatio).ceil() *
              (signature.bounds.height * pixelRatio).ceil() *
              4,
          'retainedCacheBytes': _cache.bytes,
          'activeImageBytes': _activeBytes,
        },
      );
    final baseHandle = baseImage?.clone();
    try {
      final image = await _rasterize(
        strokes,
        pageSize,
        pixelRatio,
        baseImage: baseHandle,
        cachedPrefixLength: cachedPrefixLength,
        generation: generation,
        bounds: signature.bounds,
      );
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }

      if (!_reserveImage(
        image.width * image.height * 4,
        evictOffscreen: true,
      )) {
        image.dispose();
        _requestedSignature = null;
        return;
      }
      setState(() {
        _replaceImage(image);
        _imagePixelRatio = pixelRatio;
        _imagePageSize = pageSize;
        _imageBounds = signature.bounds;
        _cachedSignature = signature;
        _cachedStrokeIdentities = strokes;
        _cache.put(signature, image);
      });
    } catch (_) {
      // Vector painting remains available. Permit a later update to retry,
      // without spinning indefinitely on an allocation/native-render failure.
      if (generation == _generation) _requestedSignature = null;
    } finally {
      baseHandle?.dispose();
      trace.finish();
      _rasterizationInProgress = false;
      _rerasterizeIfRequested();
    }
  }

  void _rerasterizeIfRequested() {
    if (!mounted || !_rasterizeAfterCurrent) return;
    _rasterizeAfterCurrent = false;
    _requestedSignature = null;
    _rasterizeIfNeeded();
  }

  Future<ui.Image> _rasterize(
    List<XppStroke> strokes,
    Size pageSize,
    double pixelRatio, {
    ui.Image? baseImage,
    int? cachedPrefixLength,
    required int generation,
    required Rect bounds,
  }) async {
    final tailStart = baseImage == null ? 0 : cachedPrefixLength ?? 0;
    if (tailStart >= strokes.length) return baseImage!;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (baseImage != null) {
      canvas.drawImage(baseImage, Offset.zero, Paint());
    }
    canvas.scale(pixelRatio);
    canvas.translate(-bounds.left, -bounds.top);
    // Recording is synchronous UI-isolate work even though toImage is async.
    // Yield between small batches, and stop obsolete work before native raster.
    try {
      var pointsRecorded = 0;
      for (final stroke in strokes.skip(tailStart)) {
        final points = stroke.points;
        if (points == null || points.isEmpty) continue;
        // Pen segments are independent drawLine calls. Keep one shared end
        // point between batches to preserve pressure and round caps exactly.
        // Highlighter paths stay intact to preserve translucent joins.
        final batches = _strokeBatches(stroke, points);
        for (final batch in batches) {
          XppStrokePainter(
            points: batch,
            color: _strokeColor(stroke),
            topLeft: Offset.zero,
            smoothPressure: stroke.tool == XppStrokeTool.PEN,
          ).paint(canvas, Size.zero);
          pointsRecorded += batch.length;
          if (pointsRecorded >= 512) {
            await Future<void>.delayed(Duration.zero);
            if (!mounted || generation != _generation) {
              throw StateError('Obsolete stroke raster');
            }
            pointsRecorded = 0;
          }
        }
      }
    } catch (_) {
      recorder.endRecording().dispose();
      rethrow;
    }
    final picture = recorder.endRecording();
    final width = (bounds.width * pixelRatio).ceil().clamp(1, 100000);
    final height = (bounds.height * pixelRatio).ceil().clamp(1, 100000);
    try {
      return await (XppPageStack.debugRasterizePicture?.call(
            picture,
            width,
            height,
          ) ??
          picture.toImage(width, height));
    } finally {
      picture.dispose();
    }
  }

  _StrokeRunKey _strokeRunSignature(
    List<XppStroke> strokes,
    Size pageSize,
    double pixelRatio,
  ) => _StrokeRunKey(strokes, pageSize, pixelRatio, widget.bounds);

  int? _cachedPrefixLength({Size? pageSize, double? pixelRatio}) {
    if (_cachedSignature == null) return null;
    if (pageSize != null && _imagePageSize != pageSize) return null;
    if (pixelRatio != null &&
        (_imagePixelRatio != pixelRatio || _imageBounds != widget.bounds))
      return null;
    if (_cachedStrokeIdentities.length > widget.strokes.length) return null;

    for (var i = 0; i < _cachedStrokeIdentities.length; i++) {
      if (!identical(_cachedStrokeIdentities[i], widget.strokes[i])) {
        return null;
      }
    }
    return _cachedStrokeIdentities.length;
  }

  double _rasterPixelRatio() {
    final mediaQueryRatio = MediaQuery.maybeDevicePixelRatioOf(context);
    final devicePixelRatio =
        mediaQueryRatio ?? View.of(context).devicePixelRatio;
    final requestedRatio = devicePixelRatio * widget.rasterScale;
    final size = boundedRasterSize(
      widget.pageSize.width * requestedRatio,
      widget.pageSize.height * requestedRatio,
    );
    return min(
      size.width / widget.pageSize.width,
      size.height / widget.pageSize.height,
    );
  }

  @override
  void dispose() {
    _generation++;
    _rasterizeAfterCurrent = false;
    _rasterizeTimer?.cancel();
    _replaceImage(null);
    super.dispose();
  }
}

class _StrokeRunVectorPainter extends CustomPainter {
  final List<XppStroke> strokes;

  _StrokeRunVectorPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    _paintStrokes(canvas, strokes);
  }

  @override
  bool shouldRepaint(covariant _StrokeRunVectorPainter oldDelegate) {
    return !listEquals(oldDelegate.strokes, strokes);
  }
}

void _paintStrokes(Canvas canvas, Iterable<XppStroke> strokes) {
  final clip = canvas.getLocalClipBounds();
  for (final stroke in strokes) {
    final bounds = stroke.eraseBounds;
    if (bounds != null && !clip.overlaps(bounds)) continue;
    final points = stroke.points;
    if (points == null || points.isEmpty) continue;

    XppStrokePainter(
      points: points,
      color: _strokeColor(stroke),
      topLeft: Offset.zero,
      smoothPressure: stroke.tool == XppStrokeTool.PEN,
    ).paint(canvas, Size.zero);
  }
}

Color _strokeColor(XppStroke stroke) {
  if (stroke.tool == XppStrokeTool.ERASER) return Colors.white;
  if (stroke.tool == XppStrokeTool.HIGHLIGHTER) {
    return stroke.color!.withValues(alpha: .5);
  }
  return stroke.color!;
}

class _StrokeRunKey {
  _StrokeRunKey(
    List<XppStroke> strokes,
    this.pageSize,
    this.pixelRatio,
    this.bounds,
  ) : strokes = List.unmodifiable(strokes);
  final List<XppStroke> strokes;
  final Size pageSize;
  final double pixelRatio;
  final Rect bounds;
  @override
  int get hashCode => _hash;
  late final int _hash = Object.hash(
    pageSize,
    pixelRatio,
    bounds,
    Object.hashAll(strokes.map(identityHashCode)),
  );
  @override
  bool operator ==(Object other) =>
      other is _StrokeRunKey &&
      pageSize == other.pageSize &&
      pixelRatio == other.pixelRatio &&
      bounds == other.bounds &&
      listEquals(strokes, other.strokes);
}

Iterable<List<XppStrokePoint>> _strokeBatches(
  XppStroke stroke,
  List<XppStrokePoint> points,
) sync* {
  if (stroke.tool != XppStrokeTool.PEN || points.length <= 512) {
    yield points;
    return;
  }
  for (var start = 0; start < points.length - 1; start += 512) {
    yield points.sublist(start, min(start + 513, points.length));
  }
}

Rect _strokeRasterBounds(List<XppStroke> strokes, Size pageSize) {
  Rect? bounds;
  for (final stroke in strokes) {
    final rect = stroke.eraseBounds;
    if (rect != null) bounds = bounds?.expandToInclude(rect) ?? rect;
  }
  if (bounds == null) return const Rect.fromLTWH(0, 0, 1, 1);
  bounds = Rect.fromLTRB(
    bounds.left.floorToDouble(),
    bounds.top.floorToDouble(),
    bounds.right.ceilToDouble(),
    bounds.bottom.ceilToDouble(),
  ).intersect(Offset.zero & pageSize);
  return bounds.isEmpty ? const Rect.fromLTWH(0, 0, 1, 1) : bounds;
}

class _StrokeHitRegion extends SingleChildRenderObjectWidget {
  const _StrokeHitRegion({required this.contains, required super.child});
  final bool Function(Offset) contains;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderStrokeHitRegion(contains);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderStrokeHitRegion renderObject,
  ) {
    renderObject.contains = contains;
  }
}

class _RenderStrokeHitRegion extends RenderProxyBox {
  _RenderStrokeHitRegion(this.contains);
  bool Function(Offset) contains;
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      contains(position) && super.hitTest(result, position: position);
}
