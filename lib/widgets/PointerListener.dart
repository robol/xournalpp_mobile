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
  final Function({Offset? coordinates, double? radius})? filterEraser;
  final Function({List<Offset>? coordinates, double? radius})? filterEraserPath;
  final Function()? removeLastContent;

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
    this.filterEraser,
    this.filterEraserPath,
    this.removeLastContent,
  }) : super(key: key);

  @override
  PointerListenerState createState() => PointerListenerState();
}

class PointerListenerState extends State<PointerListener> {
  bool drawingEnabled = true;

  final StrokePointBuffer strokePoints = StrokePointBuffer();
  final EraserPreviewController eraserPreview = EraserPreviewController();
  late final StrokePreviewController strokePreview = StrokePreviewController(
    colorProvider: () => _activeStrokeColor,
  );

  XppStrokeTool tool = XppStrokeTool.PEN;

  Map<int, DateTime> pointerTimestamps = Map();

  bool poppedContentForCurrentPointer = false;

  PointerDeviceKind? _lastNotifiedDeviceKind;

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
          if (isPen(data) || isHighlighter(data)) addStrokePoint(data);

          if (isEraser(data)) eraseAt(data);
        },
        onPointerDown: (data) {
          if (_detectTwoFingerGesture(data, shouldPop: true)) return;

          setState(() {
            tool = getToolFromPointer(data);
          });
          notifyDeviceChange(data);
          if (drawingEnabled && (isPen(data) || isHighlighter(data))) {
            resetPreview();
            addStrokePoint(data);
          }
          if (drawingEnabled && isEraser(data)) {
            eraserPreview.start();
            eraseAt(data);
          }
          if (isLaTeX(data)) {
            XppTexImage.edit(
              context: context,
              topLeft: data.localPosition,
              color: _activeStrokeColor,
            ).then((value) {
              widget.onNewContent!(value);
            });
          }
          if (isText(data)) {
            XppText(
              offset: data.localPosition,
              color: _activeStrokeColor,
              size: widget.strokeWidth! * 3,
            );
          }
        },
        onPointerUp: (data) {
          if (tool == XppStrokeTool.ERASER) {
            applyEraserPath();
          } else if (!poppedContentForCurrentPointer) {
            saveStroke(tool);
          }
          poppedContentForCurrentPointer = false;
          eraserPreview.reset();
          strokePoints.clear();
          resetPreview(rebuild: true);
        },
        onPointerCancel: (data) {
          strokePoints.clear();
          poppedContentForCurrentPointer = false;
          eraserPreview.reset();
          resetPreview(rebuild: true);
        },
        onPointerSignal: (data) {
          setState(() {
            tool = getToolFromPointer(data);
          });
          notifyDeviceChange(data);
        },
        child: Stack(
          children: [
            widget.child!,
            ...strokePreview.buildWidgets(),
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
    resetPreview(rebuild: true);
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

  void addStrokePoint(PointerEvent data) {
    tool = getToolFromPointer(data);

    double? width = (data.pressure == 0
        ? widget.strokeWidth
        : data.pressure * widget.strokeWidth!);

    //A highlighter should not change its width
    if (isHighlighter(data)) width = widget.highlighterWidth;

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
    strokePreview.addPoint(point, onChunkReady: () => setState(() {}));
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
