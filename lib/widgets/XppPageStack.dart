import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPageContentWidget.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

class XppPageStack extends StatefulWidget {
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
  final void Function(XppLayer layer, XppContent content)? onSelectContent;
  final VoidCallback? onDeleteSelection;
  final bool keepAlive;

  const XppPageStack({
    Key? key,
    this.page,
    this.rasterScale = 1,
    this.onReplaceContent,
    this.onContentPointerDown,
    this.activeTool,
    this.selectedContents = const {},
    this.onSelectContent,
    this.onDeleteSelection,
    this.keepAlive = true,
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
  bool _isBackgroundLoading = false;

  @override
  void initState() {
    page = widget.page;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    List<Widget> children = [];

    if (page!.background != null && _lastKnownBackground != page!.background) {
      _lastKnownBackground = page!.background;
      _isBackgroundLoading = page!.background is XppBackgroundPdf;
      background = page!.background!.render(
        onLoadingChanged: _handleBackgroundLoadingChanged,
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
          onSelectContent: widget.onSelectContent,
        ),
      ),
    );
    final deleteButton = _buildDeleteSelectionButton();
    if (deleteButton != null) children.add(deleteButton);
    if (_isBackgroundLoading) children.add(_buildLoadingOverlay());
    return RepaintBoundary(
      key: pngKey,
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
    );
  }

  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.white70,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }

  void _handleBackgroundLoadingChanged(bool isLoading) {
    if (!mounted || _isBackgroundLoading == isLoading) return;
    setState(() => _isBackgroundLoading = isLoading);
  }

  Widget? _buildDeleteSelectionButton() {
    if (widget.activeTool != EditingTool.SELECT ||
        widget.selectedContents.isEmpty ||
        widget.onDeleteSelection == null) {
      return null;
    }

    Rect? selectionBounds;
    for (final content in widget.selectedContents) {
      final bounds = content.selectionBounds;
      if (bounds == null || bounds.isEmpty) continue;
      selectionBounds = selectionBounds?.expandToInclude(bounds) ?? bounds;
    }
    if (selectionBounds == null) return null;

    final pageSize = page!.pageSize!.toSize();
    const buttonSize = 32.0;
    final left = (selectionBounds.right + 6)
        .clamp(0.0, max(0.0, pageSize.width - buttonSize))
        .toDouble();
    final top = (selectionBounds.top - buttonSize - 6)
        .clamp(0.0, max(0.0, pageSize.height - buttonSize))
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      width: buttonSize,
      height: buttonSize,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: widget.onContentPointerDown,
        child: Material(
          color: Colors.redAccent,
          shape: CircleBorder(),
          elevation: 3,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 18,
            color: Colors.white,
            tooltip: 'Delete selection',
            icon: Icon(Icons.delete),
            onPressed: widget.onDeleteSelection,
          ),
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
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Could not encode page preview as PNG.');
    }
    Uint8List pngBytes = byteData.buffer.asUint8List();
    return pngBytes;
  }

  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void didUpdateWidget(covariant XppPageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.page != oldWidget.page) {
      setState(() {
        page = widget.page;
      });
    }
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
    List<Widget> children = [];
    List<Widget> selectionChildren = [];
    List<XppStroke> pendingStrokes = [];
    final selectionMode = widget.activeTool == EditingTool.SELECT;

    void flushPendingStrokes() {
      if (pendingStrokes.isEmpty) return;
      children.add(
        Positioned.fill(
          child: _RasterizedStrokeRun(
            strokes: List<XppStroke>.unmodifiable(pendingStrokes),
            pageSize: widget.pageSize,
            rasterScale: widget.rasterScale,
          ),
        ),
      );
      pendingStrokes = [];
    }

    widget.layer!.content!.forEach((element) {
      if (element == null) return;

      if (element is XppStroke) {
        pendingStrokes.add(element);
        if (selectionMode) {
          selectionChildren.add(_buildStrokeSelectionRegion(element));
        }
        return;
      }

      flushPendingStrokes();
      if (!renderedContent.keys.contains(element)) {
        renderedContent[element] = Positioned(
          child: element.render(
            onReplace: (newContent) => widget.onReplaceContent?.call(
              widget.layer!,
              element,
              newContent,
            ),
            onPointerDown: widget.onContentPointerDown,
            selectionMode: selectionMode,
            selected: widget.selectedContents.contains(element),
            onSelect: () =>
                widget.onSelectContent?.call(widget.layer!, element),
          ),
          top: element.getOffset()?.dy ?? 0,
          left: element.getOffset()?.dx ?? 0,
        );
      }
      final child = renderedContent[element];
      if (child != null) children.add(child);
    });
    flushPendingStrokes();
    children.addAll(selectionChildren);
    return Stack(children: children);
  }

  Widget _buildStrokeSelectionRegion(XppStroke stroke) {
    final bounds = stroke.eraseBounds;
    if (bounds == null || bounds.isEmpty) return SizedBox.shrink();

    final selectionBounds = bounds.inflate(6);
    return Positioned.fromRect(
      rect: selectionBounds,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: widget.onContentPointerDown,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => widget.onSelectContent?.call(widget.layer!, stroke),
          child: widget.selectedContents.contains(stroke)
              ? CustomPaint(foregroundPainter: _SelectionFramePainter())
              : SizedBox.expand(),
        ),
      ),
    );
  }
}

class _SelectionFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = XppPageContentWidget.selectionColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(rect.deflate(.75), paint);
  }

  @override
  bool shouldRepaint(covariant _SelectionFramePainter oldDelegate) => false;
}

class _RasterizedStrokeRun extends StatefulWidget {
  final List<XppStroke> strokes;
  final Size pageSize;
  final double rasterScale;

  const _RasterizedStrokeRun({
    required this.strokes,
    required this.pageSize,
    required this.rasterScale,
  });

  @override
  State<_RasterizedStrokeRun> createState() => _RasterizedStrokeRunState();
}

class _RasterizedStrokeRunState extends State<_RasterizedStrokeRun> {
  ui.Image? _image;
  int? _requestedSignature;
  int? _cachedSignature;
  double _imagePixelRatio = 1;
  Size? _imagePageSize;
  List<int> _cachedStrokeIdentities = const [];
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
    final cachedPrefixLength = _cachedPrefixLength(
      pageSize: widget.pageSize,
      pixelRatio: _rasterPixelRatio(),
    );

    if (image == null || cachedPrefixLength == null) {
      return CustomPaint(
        painter: _StrokeRunVectorPainter(widget.strokes),
        size: widget.pageSize,
      );
    }

    final children = <Widget>[
      RawImage(
        image: image,
        width: widget.pageSize.width,
        height: widget.pageSize.height,
        fit: BoxFit.fill,
        scale: _imagePixelRatio,
        filterQuality: FilterQuality.medium,
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

  void _rasterizeIfNeeded() {
    final pixelRatio = _rasterPixelRatio();
    final signature = _strokeRunSignature(
      widget.strokes,
      widget.pageSize,
      pixelRatio,
    );
    if (_requestedSignature == signature) return;

    _requestedSignature = signature;
    final generation = ++_generation;
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
      SchedulerBinding.instance.scheduleTask<void>(() {
        if (!mounted || generation != _generation) return;
        _startRasterization(
          strokes,
          widget.pageSize,
          pixelRatio,
          signature,
          generation,
          baseImage,
          cachedPrefixLength,
        );
      }, Priority.idle);
    });
  }

  void _startRasterization(
    List<XppStroke> strokes,
    Size pageSize,
    double pixelRatio,
    int signature,
    int generation,
    ui.Image? baseImage,
    int? cachedPrefixLength,
  ) {
    _rasterizationInProgress = true;
    _rasterize(
      strokes,
      pageSize,
      pixelRatio,
      baseImage: baseImage,
      cachedPrefixLength: cachedPrefixLength,
    ).then((image) {
      _rasterizationInProgress = false;
      if (!mounted || generation != _generation) {
        image.dispose();
        _rerasterizeIfRequested();
        return;
      }

      setState(() {
        if (_image != image) _image?.dispose();
        _image = image;
        _imagePixelRatio = pixelRatio;
        _imagePageSize = pageSize;
        _cachedSignature = signature;
        _cachedStrokeIdentities = strokes.map(identityHashCode).toList();
      });
      _rerasterizeIfRequested();
    });
  }

  void _rerasterizeIfRequested() {
    if (!_rasterizeAfterCurrent) return;
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
  }) async {
    final tailStart = baseImage == null ? 0 : cachedPrefixLength ?? 0;
    if (tailStart >= strokes.length) return baseImage!;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (baseImage != null) {
      canvas.drawImage(baseImage, Offset.zero, Paint());
    }
    canvas.scale(pixelRatio);
    _paintStrokes(canvas, strokes.skip(tailStart));
    final picture = recorder.endRecording();
    final width = (pageSize.width * pixelRatio).ceil().clamp(1, 100000);
    final height = (pageSize.height * pixelRatio).ceil().clamp(1, 100000);
    final image = await picture.toImage(width, height);
    picture.dispose();
    return image;
  }

  int _strokeRunSignature(
    List<XppStroke> strokes,
    Size pageSize,
    double pixelRatio,
  ) {
    return Object.hash(
      pageSize.width,
      pageSize.height,
      pixelRatio,
      Object.hashAll(strokes.map(identityHashCode)),
    );
  }

  int? _cachedPrefixLength({Size? pageSize, double? pixelRatio}) {
    if (_cachedSignature == null) return null;
    if (pageSize != null && _imagePageSize != pageSize) return null;
    if (pixelRatio != null && _imagePixelRatio != pixelRatio) return null;
    if (_cachedStrokeIdentities.length > widget.strokes.length) return null;

    for (var i = 0; i < _cachedStrokeIdentities.length; i++) {
      if (_cachedStrokeIdentities[i] != identityHashCode(widget.strokes[i])) {
        return null;
      }
    }
    return _cachedStrokeIdentities.length;
  }

  double _rasterPixelRatio() {
    final mediaQueryRatio = MediaQuery.maybeDevicePixelRatioOf(context);
    final devicePixelRatio =
        mediaQueryRatio ?? View.of(context).devicePixelRatio;
    final effectiveScale = max(1.0, widget.rasterScale);
    return (devicePixelRatio * effectiveScale).clamp(1.0, 6.0);
  }

  @override
  void dispose() {
    _generation++;
    _rasterizeTimer?.cancel();
    _image?.dispose();
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
    return oldDelegate.strokes != strokes;
  }
}

void _paintStrokes(Canvas canvas, Iterable<XppStroke> strokes) {
  for (final stroke in strokes) {
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
