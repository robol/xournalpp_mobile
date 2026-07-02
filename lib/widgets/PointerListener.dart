import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppTexImage.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/widgets/EraserPreviewController.dart';
import 'package:xournalpp/widgets/StrokePointBuffer.dart';
import 'package:xournalpp/widgets/StrokePreviewController.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

class PointerListener extends StatefulWidget {
  final Function(XppContent?)? onNewContent;
  final Function({int? device, PointerDeviceKind? kind})? onDeviceChange;
  final Widget? child;
  final Map<PointerDeviceKind?, EditingTool> toolData;
  final Matrix4? translationMatrix;
  final double? strokeWidth;
  final double? highlighterWidth;
  final double? eraserWidth;
  final Color? color;
  final Color? highlighterColor;
  final Color? laserColor;
  final Function({Offset? coordinates, double? radius})? filterEraser;
  final Function({List<Offset>? coordinates, double? radius})? filterEraserPath;
  final Function()? removeLastContent;
  final void Function(Rect? region)? onSelectionRegionChange;
  final VoidCallback? onSelectionClear;

  const PointerListener({
    Key? key,
    this.onNewContent,
    this.child,
    this.toolData = const {},
    this.translationMatrix,
    this.onDeviceChange,
    this.strokeWidth,
    this.highlighterWidth,
    this.eraserWidth,
    this.color,
    this.highlighterColor,
    this.laserColor,
    this.filterEraser,
    this.filterEraserPath,
    this.removeLastContent,
    this.onSelectionRegionChange,
    this.onSelectionClear,
  }) : super(key: key);

  @override
  PointerListenerState createState() => PointerListenerState();
}

class PointerListenerState extends State<PointerListener> {
  static const Duration _laserPreviewFadeOutDuration = Duration(seconds: 3);
  static const double _laserWidth = 20;

  bool drawingEnabled = true;

  final StrokePointBuffer strokePoints = StrokePointBuffer();
  final EraserPreviewController eraserPreview = EraserPreviewController();
  late final StrokePreviewController strokePreview = StrokePreviewController(
    colorProvider: () => _activeStrokeColor,
  );

  XppStrokeTool tool = XppStrokeTool.PEN;
  EditingTool? activeEditingTool = EditingTool.STYLUS;

  Map<int, DateTime> pointerTimestamps = Map();

  bool poppedContentForCurrentPointer = false;

  PointerDeviceKind? _lastNotifiedDeviceKind;
  final Set<int> _contentPointerDownDevices = {};
  Offset? _selectionStart;
  Offset? _selectionCurrent;
  int? _selectionPointerDevice;
  bool _dragSelecting = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) {
        notifyDeviceChange(event);
      },
      opaque: false,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerMove: (data) {
          if (_detectTwoFingerGesture(data)) return;
          notifyDeviceChange(data);
          if (!drawingEnabled) return;
          if (isSelect(data)) {
            _updateSelectionRegion(data);
            return;
          }
          if (isPen(data) || isHighlighter(data) || isLaser(data)) {
            addStrokePoint(data);
          }

          if (isEraser(data)) eraseAt(data);
        },
        onPointerDown: (data) {
          if (_detectTwoFingerGesture(data, shouldPop: true)) return;

          setState(() {
            activeEditingTool = getEditingToolFromPointer(data);
            tool = getToolFromPointer(data);
          });
          notifyDeviceChange(data);
          if (isSelect(data)) {
            _startSelectionRegion(data);
            return;
          }
          if (drawingEnabled &&
              (isPen(data) || isHighlighter(data) || isLaser(data))) {
            resetPreview();
            addStrokePoint(data);
          }
          if (drawingEnabled && isEraser(data)) {
            eraserPreview.start();
            eraseAt(data);
          }
          if (isLaTeX(data)) {
            _insertLatex(data);
          }
          if (isText(data)) {
            _insertText(data);
          }
        },
        onPointerUp: (data) {
          if (activeEditingTool == EditingTool.SELECT) {
            _finishSelectionRegion();
          } else if (tool == XppStrokeTool.ERASER) {
            applyEraserPath();
          } else if (activeEditingTool == EditingTool.LASER) {
            finishLaserPreview();
          } else if (!poppedContentForCurrentPointer) {
            saveStroke(tool);
          }
          poppedContentForCurrentPointer = false;
          eraserPreview.reset();
          strokePoints.clear();
          if (activeEditingTool != EditingTool.LASER) {
            resetPreview(rebuild: true);
          }
        },
        onPointerCancel: (data) {
          if (activeEditingTool == EditingTool.LASER) {
            finishLaserPreview();
          }
          _cancelSelectionRegion();
          strokePoints.clear();
          poppedContentForCurrentPointer = false;
          eraserPreview.reset();
          if (activeEditingTool != EditingTool.LASER) {
            resetPreview(rebuild: true);
          }
        },
        onPointerSignal: (data) {
          setState(() {
            activeEditingTool = getEditingToolFromPointer(data);
            tool = getToolFromPointer(data);
          });
          notifyDeviceChange(data);
        },
        child: Stack(
          children: [
            widget.child!,
            ...strokePreview.buildWidgets(),
            if (_selectionRect != null)
              Positioned.fromRect(
                rect: _selectionRect!,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0x221976D2),
                      border: Border.all(color: Color(0xFF1976D2), width: 1.5),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    foregroundPainter: EraserPreviewPainter(
                      pointsProvider: () => eraserPreview.points,
                      radiusProvider: () => widget.eraserWidth ?? 1,
                      repaint: eraserPreview.repaint,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // clearPoints method used to reset the canvas
  // method can be called using
  //   key.currentState.clearPoints();

  void clearPoints() {
    strokePoints.clear();
    eraserPreview.reset();
    _cancelSelectionRegion();
    resetPreview(rebuild: true);
  }

  void markContentPointerDown(PointerDownEvent event) {
    _contentPointerDownDevices.add(event.device);
    Future<void>.delayed(Duration(milliseconds: 100), () {
      _contentPointerDownDevices.remove(event.device);
    });
  }

  bool _consumeContentPointerDown(PointerDownEvent event) =>
      _contentPointerDownDevices.remove(event.device);

  Rect? get _selectionRect {
    if (!_dragSelecting ||
        _selectionStart == null ||
        _selectionCurrent == null) {
      return null;
    }
    return Rect.fromPoints(_selectionStart!, _selectionCurrent!);
  }

  void _startSelectionRegion(PointerDownEvent data) {
    _selectionStart = data.localPosition;
    _selectionCurrent = data.localPosition;
    _selectionPointerDevice = data.device;
    _dragSelecting = false;
  }

  void _updateSelectionRegion(PointerMoveEvent data) {
    if (_selectionStart == null) return;
    _selectionCurrent = data.localPosition;
    final distance = (_selectionCurrent! - _selectionStart!).distance;
    if (!_dragSelecting && distance < 4) return;

    _dragSelecting = true;
    widget.onSelectionRegionChange?.call(_selectionRect);
    setState(() {});
  }

  void _finishSelectionRegion() {
    if (_dragSelecting) {
      widget.onSelectionRegionChange?.call(_selectionRect);
    } else if (_selectionStart != null) {
      final pointerDevice = _selectionPointerDevice;
      Future<void>.delayed(Duration.zero, () {
        if (!mounted || _selectionStart != null) return;
        if (_contentPointerDownDevices.remove(pointerDevice)) return;
        widget.onSelectionClear?.call();
      });
    }
    _selectionPointerDevice = null;
    _selectionStart = null;
    _selectionCurrent = null;
    _dragSelecting = false;
    setState(() {});
  }

  void _cancelSelectionRegion() {
    if (_selectionStart == null && !_dragSelecting) return;
    _selectionStart = null;
    _selectionCurrent = null;
    _selectionPointerDevice = null;
    _dragSelecting = false;
    setState(() {});
  }

  void _insertLatex(PointerDownEvent data) {
    final topLeft = data.localPosition;
    final color = _activeStrokeColor;
    Future<void>.delayed(Duration.zero, () {
      if (!mounted || _consumeContentPointerDown(data)) return;
      XppTexImage.edit(context: context, topLeft: topLeft, color: color)
          .then((value) {
            widget.onNewContent!(value);
          })
          .catchError((_) {});
    });
  }

  void _insertText(PointerDownEvent data) {
    final offset = data.localPosition;
    final color = _activeStrokeColor;
    final size = widget.strokeWidth! * 3;
    Future<void>.delayed(Duration.zero, () {
      if (!mounted || _consumeContentPointerDown(data)) return;
      XppText.edit(context: context, offset: offset, color: color, size: size)
          .then((value) {
            widget.onNewContent!(value);
          })
          .catchError((_) {});
    });
  }

  void saveStroke(XppStrokeTool tool) {
    final smoothedPoints = strokePoints.smoothedPoints();
    if (smoothedPoints.isNotEmpty) {
      XppStroke stroke = XppStroke.byTool(
        tool: tool,
        points: smoothedPoints,
        color: _colorForTool(tool),
      );
      widget.onNewContent!(stroke);
    }
  }

  Color? get _activeStrokeColor => _colorForTool(tool);

  Color? _colorForTool(XppStrokeTool tool) {
    if (activeEditingTool == EditingTool.LASER) {
      return widget.laserColor;
    }
    if (tool == XppStrokeTool.HIGHLIGHTER) {
      return widget.highlighterColor;
    }
    return widget.color;
  }

  void eraseAt(PointerEvent data) {
    eraserPreview.add(
      Offset(data.localPosition.dx, data.localPosition.dy),
      radius: widget.eraserWidth ?? 1,
    );
  }

  void applyEraserPath() {
    eraserPreview.apply(
      radius: widget.eraserWidth,
      fallback: widget.filterEraser!,
      path: widget.filterEraserPath,
    );
  }

  void finishLaserPreview() {
    strokePreview.finish(fadeOutDuration: _laserPreviewFadeOutDuration);
    setState(() {});
  }

  void addStrokePoint(PointerEvent data) {
    activeEditingTool = getEditingToolFromPointer(data);
    tool = getToolFromPointer(data);

    double? width = (data.pressure == 0
        ? widget.strokeWidth
        : data.pressure * widget.strokeWidth!);

    //A highlighter should not change its width
    if (isHighlighter(data)) width = widget.highlighterWidth;
    if (isLaser(data)) width = _laserWidth;

    final point = XppStrokePoint(
      x: data.localPosition.dx,
      y: data.localPosition.dy,
      width: width,
    );
    for (final appendedPoint in strokePoints.add(point)) {
      _appendStrokePoint(appendedPoint);
    }
  }

  void _appendStrokePoint(XppStrokePoint point) {
    strokePreview.addPoint(
      point,
      fadeOutDuration: activeEditingTool == EditingTool.LASER
          ? _laserPreviewFadeOutDuration
          : null,
      onChunkReady: () => setState(() {}),
    );
  }

  void resetPreview({bool rebuild = false}) {
    strokePreview.reset();

    if (rebuild) setState(() {});
  }

  void notifyDeviceChange(PointerEvent data) {
    final deviceToolKnown = widget.toolData.keys.contains(data.kind);
    if (_lastNotifiedDeviceKind == data.kind && deviceToolKnown) return;

    _lastNotifiedDeviceKind = data.kind;
    widget.onDeviceChange!(device: data.device, kind: data.kind);
  }

  bool isPen(PointerEvent data) {
    return (widget.toolData.keys.contains(data.kind) &&
            widget.toolData[data.kind] == EditingTool.STYLUS) ||
        (!widget.toolData.keys.contains(data.kind) &&
            data.kind == PointerDeviceKind.stylus);
  }

  bool isHighlighter(PointerEvent data) {
    return (widget.toolData.keys.contains(data.kind) &&
        widget.toolData[data.kind] == EditingTool.HIGHLIGHT);
  }

  bool isLaser(PointerEvent data) {
    return (widget.toolData.keys.contains(data.kind) &&
        widget.toolData[data.kind] == EditingTool.LASER);
  }

  bool isEraser(PointerEvent data) {
    return (widget.toolData.keys.contains(data.kind) &&
            widget.toolData[data.kind] == EditingTool.ERASER) ||
        (!widget.toolData.keys.contains(data.kind) &&
            data.kind == PointerDeviceKind.invertedStylus);
  }

  bool isText(PointerEvent data) {
    return (widget.toolData.keys.contains(data.kind) &&
        widget.toolData[data.kind] == EditingTool.TEXT);
  }

  bool isLaTeX(PointerEvent data) {
    return (widget.toolData.keys.contains(data.kind) &&
        widget.toolData[data.kind] == EditingTool.LATEX);
  }

  bool isSelect(PointerEvent data) {
    return (widget.toolData.keys.contains(data.kind) &&
        widget.toolData[data.kind] == EditingTool.SELECT);
  }

  EditingTool? getEditingToolFromPointer(PointerEvent data) {
    if (widget.toolData.keys.contains(data.kind)) {
      return widget.toolData[data.kind];
    }
    if (data.kind == PointerDeviceKind.stylus) return EditingTool.STYLUS;
    if (data.kind == PointerDeviceKind.invertedStylus) {
      return EditingTool.ERASER;
    }
    return null;
  }

  XppStrokeTool getToolFromPointer(PointerEvent data) {
    XppStrokeTool tool = XppStrokeTool.PEN;
    if (isHighlighter(data))
      tool = XppStrokeTool.HIGHLIGHTER;
    else if (isEraser(data))
      tool = XppStrokeTool.ERASER;
    return tool;
  }

  bool _detectTwoFingerGesture(PointerEvent data, {bool shouldPop = false}) {
    if (data.kind != PointerDeviceKind.touch) return false;

    // detecting two-finger gestures
    final timestamp = DateTime.now();
    bool foundCloseOffset = false;
    pointerTimestamps.remove(data.device);
    pointerTimestamps.forEach((key, value) {
      if (value.difference(timestamp).inMilliseconds.abs() < 100) {
        foundCloseOffset = true;
      }
    });
    if (shouldPop && foundCloseOffset && !poppedContentForCurrentPointer) {
      poppedContentForCurrentPointer = true;
    }
    pointerTimestamps[data.device] = timestamp;
    return foundCloseOffset;
  }

  @override
  void dispose() {
    strokePreview.dispose();
    eraserPreview.dispose();
    super.dispose();
  }
}
