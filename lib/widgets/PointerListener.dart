import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppTexImage.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

class PointerListener extends StatefulWidget {
  @required
  final Function(XppContent?)? onNewContent;
  @required
  final Function({int? device, PointerDeviceKind? kind})? onDeviceChange;
  @required
  final Widget? child;
  @required
  final Map<PointerDeviceKind?, EditingTool> toolData;
  @required
  final Matrix4? translationMatrix;
  @required
  final double? strokeWidth;
  @required
  final double? eraserWidth;
  @required
  final Color? color;
  @required
  final Function({Offset? coordinates, double? radius})? filterEraser;
  @required
  final Function()? removeLastContent;

  const PointerListener({
    Key? key,
    this.onNewContent,
    this.child,
    this.toolData = const {},
    this.translationMatrix,
    this.onDeviceChange,
    this.strokeWidth,
    this.eraserWidth,
    this.color,
    this.filterEraser,
    this.removeLastContent,
  }) : super(key: key);

  @override
  PointerListenerState createState() => PointerListenerState();
}

class PointerListenerState extends State<PointerListener> {
  static const int _previewChunkPointCount = 24;

  bool drawingEnabled = true;

  List<XppStrokePoint> points = [];
  List<List<XppStrokePoint>> previewChunks = [];
  List<XppStrokePoint> activePreviewPoints = [];

  XppStrokeTool tool = XppStrokeTool.PEN;

  final ValueNotifier<int> _strokeRepaint = ValueNotifier<int>(0);
  final ValueNotifier<Rect?> _activePreviewBounds = ValueNotifier<Rect?>(null);

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
          if (drawingEnabled && isEraser(data)) eraseAt(data);
          if (isLaTeX(data)) {
            XppTexImage.edit(
              context: context,
              topLeft: data.localPosition,
              color: widget.color,
            ).then((value) {
              widget.onNewContent!(value);
            });
          }
          if (isText(data)) {
            XppText(
              offset: data.localPosition,
              color: widget.color,
              size: widget.strokeWidth! * 3,
            );
          }
        },
        onPointerUp: (data) {
          if (!poppedContentForCurrentPointer) saveStroke(tool);
          poppedContentForCurrentPointer = false;
          points.clear();
          resetPreview(rebuild: true);
          _strokeRepaint.value++;
        },
        onPointerCancel: (data) {
          points.clear();
          poppedContentForCurrentPointer = false;
          resetPreview(rebuild: true);
          _strokeRepaint.value++;
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
            ...previewChunks.map((chunk) {
              final bounds = getStrokeBounds(chunk);
              return Positioned.fromRect(
                rect: bounds,
                child: RepaintBoundary(
                  child: CustomPaint(
                    foregroundPainter: XppStrokePainter(
                      points: chunk,
                      color: widget.color,
                      topLeft: bounds.topLeft,
                      smoothPressure: tool == XppStrokeTool.PEN,
                    ),
                  ),
                ),
              );
            }),
            ValueListenableBuilder<Rect?>(
              valueListenable: _activePreviewBounds,
              builder: (context, bounds, child) {
                if (bounds == null || activePreviewPoints.isEmpty) {
                  return SizedBox.shrink();
                }

                return Positioned.fromRect(
                  rect: bounds,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      foregroundPainter: XppStrokePainter(
                        points: activePreviewPoints,
                        color: widget.color,
                        topLeft: bounds.topLeft,
                        smoothPressure: tool == XppStrokeTool.PEN,
                        repaint: _strokeRepaint,
                      ),
                    ),
                  ),
                );
              },
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
    points.clear();
    resetPreview(rebuild: true);
    _strokeRepaint.value++;
  }

  void saveStroke(XppStrokeTool tool) {
    if (points.isNotEmpty) {
      XppStroke stroke = XppStroke.byTool(
        tool: tool,
        points: List.from(points),
        color: widget.color,
      );
      widget.onNewContent!(stroke);
    }
  }

  void eraseAt(PointerEvent data) {
    widget.filterEraser!(
      coordinates: Offset(data.localPosition.dx, data.localPosition.dy),
      radius: widget.eraserWidth,
    );
  }

  void addStrokePoint(PointerEvent data) {
    double? width = (data.pressure == 0
        ? widget.strokeWidth
        : data.pressure * widget.strokeWidth!);

    //A highlighter should not change its width
    if (isHighlighter(data)) width = widget.strokeWidth;

    final point = XppStrokePoint(
      x: data.localPosition.dx,
      y: data.localPosition.dy,
      width: width,
    );
    points.add(point);
    activePreviewPoints.add(point);

    if (activePreviewPoints.length >= _previewChunkPointCount) {
      final lastPoint = activePreviewPoints.last;
      setState(() {
        previewChunks.add(List.from(activePreviewPoints));
        activePreviewPoints = [lastPoint];
        _activePreviewBounds.value = getStrokeBounds(activePreviewPoints);
      });
      return;
    }

    _activePreviewBounds.value = getStrokeBounds(activePreviewPoints);
    _strokeRepaint.value++;
  }

  void resetPreview({bool rebuild = false}) {
    previewChunks.clear();
    activePreviewPoints.clear();
    _activePreviewBounds.value = null;

    if (rebuild) setState(() {});
  }

  Rect getStrokeBounds(List<XppStrokePoint> strokePoints) {
    final firstPoint = strokePoints.first;
    double left = firstPoint.x!;
    double top = firstPoint.y!;
    double right = firstPoint.x!;
    double bottom = firstPoint.y!;
    double maxWidth = firstPoint.width ?? 1;

    for (final point in strokePoints) {
      final x = point.x!;
      final y = point.y!;
      final width = point.width ?? 1;

      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
      if (width > maxWidth) maxWidth = width;
    }

    final padding = (maxWidth / 2) + 2;
    return Rect.fromLTRB(left, top, right, bottom).inflate(padding);
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
    _strokeRepaint.dispose();
    _activePreviewBounds.dispose();
    super.dispose();
  }
}
