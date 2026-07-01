import 'dart:math';
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
  final Function({List<Offset>? coordinates, double? radius})? filterEraserPath;
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
    this.filterEraserPath,
    this.removeLastContent,
  }) : super(key: key);

  @override
  PointerListenerState createState() => PointerListenerState();
}

class PointerListenerState extends State<PointerListener> {
  static const int _previewChunkPointCount = 24;
  static const double _maxStrokePointSpacing = 1.5;
  static const int _maxInterpolatedPointsPerEvent = 32;
  static const int _smoothingIterations = 1;

  bool drawingEnabled = true;

  List<XppStrokePoint> points = [];
  List<XppStrokePoint> rawPoints = [];
  List<_PreviewPictureChunk> previewChunks = [];
  List<XppStrokePoint> activePreviewPoints = [];
  List<Offset> eraserPreviewPoints = [];

  XppStrokeTool tool = XppStrokeTool.PEN;

  final ValueNotifier<int> _strokeRepaint = ValueNotifier<int>(0);
  final ValueNotifier<int> _eraserRepaint = ValueNotifier<int>(0);
  final ValueNotifier<Rect?> _activePreviewBounds = ValueNotifier<Rect?>(null);
  final List<Picture> _activePreviewPictureDependencies = [];
  Picture? _activePreviewPicture;

  Map<int, DateTime> pointerTimestamps = Map();

  bool poppedContentForCurrentPointer = false;
  Offset? _lastErasePosition;

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
            _lastErasePosition = null;
            resetEraserPreview();
            eraseAt(data);
          }
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
          if (tool == XppStrokeTool.ERASER) {
            applyEraserPath();
          } else if (!poppedContentForCurrentPointer) {
            saveStroke(tool);
          }
          poppedContentForCurrentPointer = false;
          _lastErasePosition = null;
          resetEraserPreview();
          rawPoints.clear();
          points.clear();
          resetPreview(rebuild: true);
          _strokeRepaint.value++;
        },
        onPointerCancel: (data) {
          rawPoints.clear();
          points.clear();
          poppedContentForCurrentPointer = false;
          _lastErasePosition = null;
          resetEraserPreview();
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
              return Positioned.fromRect(
                rect: chunk.bounds,
                child: RepaintBoundary(
                  child: CustomPaint(
                    foregroundPainter: _PreviewPicturePainter(chunk.picture),
                  ),
                ),
              );
            }),
            ValueListenableBuilder<Rect?>(
              valueListenable: _activePreviewBounds,
              builder: (context, bounds, child) {
                if (bounds == null || _activePreviewPicture == null) {
                  return SizedBox.shrink();
                }

                return Positioned.fromRect(
                  rect: bounds,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      foregroundPainter: _PreviewPicturePainter.active(
                        pictureProvider: () => _activePreviewPicture,
                        repaint: _strokeRepaint,
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    foregroundPainter: _EraserPreviewPainter(
                      pointsProvider: () => eraserPreviewPoints,
                      radiusProvider: () => widget.eraserWidth ?? 1,
                      repaint: _eraserRepaint,
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
    rawPoints.clear();
    points.clear();
    resetEraserPreview();
    resetPreview(rebuild: true);
    _strokeRepaint.value++;
  }

  void saveStroke(XppStrokeTool tool) {
    final strokePoints = _smoothedStrokePoints();
    if (strokePoints.isNotEmpty) {
      XppStroke stroke = XppStroke.byTool(
        tool: tool,
        points: strokePoints,
        color: widget.color,
      );
      widget.onNewContent!(stroke);
    }
  }

  void eraseAt(PointerEvent data) {
    final position = Offset(data.localPosition.dx, data.localPosition.dy);
    final minDistance = max(1.0, (widget.eraserWidth ?? 1) * 0.25);
    final previousPosition = _lastErasePosition;
    if (previousPosition != null &&
        (position - previousPosition).distance < minDistance) {
      return;
    }

    _lastErasePosition = position;
    eraserPreviewPoints.add(position);
    _eraserRepaint.value++;
  }

  void applyEraserPath() {
    if (eraserPreviewPoints.isEmpty) return;

    final coordinates = List<Offset>.from(eraserPreviewPoints);
    final erasePath = widget.filterEraserPath;
    if (erasePath != null) {
      erasePath(coordinates: coordinates, radius: widget.eraserWidth);
      return;
    }

    for (final coordinate in coordinates) {
      widget.filterEraser!(coordinates: coordinate, radius: widget.eraserWidth);
    }
  }

  void resetEraserPreview() {
    if (eraserPreviewPoints.isEmpty) return;
    eraserPreviewPoints.clear();
    _eraserRepaint.value++;
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
    rawPoints.add(point);

    if (points.isEmpty) {
      _appendStrokePoint(point);
      return;
    }

    _appendInterpolatedStrokePoints(points.last, point);
  }

  void _appendInterpolatedStrokePoints(
    XppStrokePoint start,
    XppStrokePoint end,
  ) {
    final distance = (end.offset - start.offset).distance;
    final steps = min(
      _maxInterpolatedPointsPerEvent,
      max(1, (distance / _maxStrokePointSpacing).ceil()),
    );

    for (var i = 1; i <= steps; i++) {
      _appendStrokePoint(_lerpStrokePoint(start, end, i / steps));
    }
  }

  void _appendStrokePoint(XppStrokePoint point) {
    points.add(point);
    activePreviewPoints.add(point);
    _recordActivePreviewPoint();

    if (activePreviewPoints.length >= _previewChunkPointCount) {
      final lastPoint = activePreviewPoints.last;
      setState(() {
        final picture = _activePreviewPicture;
        final bounds = _activePreviewBounds.value;
        if (picture != null && bounds != null) {
          previewChunks.add(_PreviewPictureChunk(picture, bounds));
          _activePreviewPictureDependencies.remove(picture);
        }
        activePreviewPoints = [lastPoint];
        _activePreviewPicture = null;
        _activePreviewBounds.value = null;
        _recordActivePreviewPoint();
      });
      return;
    }

    _strokeRepaint.value++;
  }

  List<XppStrokePoint> _smoothedStrokePoints() {
    if (rawPoints.length < 3) return List<XppStrokePoint>.from(points);

    var smoothed = List<XppStrokePoint>.from(rawPoints);
    for (var i = 0; i < _smoothingIterations; i++) {
      smoothed = _chaikinSmooth(smoothed);
    }

    return _densifyStrokePoints(smoothed);
  }

  List<XppStrokePoint> _chaikinSmooth(List<XppStrokePoint> source) {
    if (source.length < 3) return source;

    final smoothed = <XppStrokePoint>[source.first];
    for (var i = 0; i < source.length - 1; i++) {
      final start = source[i];
      final end = source[i + 1];
      smoothed.add(_lerpStrokePoint(start, end, 0.25));
      smoothed.add(_lerpStrokePoint(start, end, 0.75));
    }
    smoothed.add(source.last);
    return smoothed;
  }

  List<XppStrokePoint> _densifyStrokePoints(List<XppStrokePoint> source) {
    if (source.length < 2) return source;

    final dense = <XppStrokePoint>[source.first];
    for (var i = 1; i < source.length; i++) {
      final start = dense.last;
      final end = source[i];
      final distance = (end.offset - start.offset).distance;
      final steps = max(1, (distance / _maxStrokePointSpacing).ceil());
      for (var step = 1; step <= steps; step++) {
        dense.add(_lerpStrokePoint(start, end, step / steps));
      }
    }
    return dense;
  }

  XppStrokePoint _lerpStrokePoint(
    XppStrokePoint start,
    XppStrokePoint end,
    double t,
  ) {
    return XppStrokePoint(
      x: lerpDouble(start.x!, end.x!, t),
      y: lerpDouble(start.y!, end.y!, t),
      width: lerpDouble(start.width!, end.width!, t),
    );
  }

  void resetPreview({bool rebuild = false}) {
    for (final chunk in previewChunks) {
      chunk.dispose();
    }
    for (final picture in _activePreviewPictureDependencies) {
      picture.dispose();
    }
    previewChunks.clear();
    _activePreviewPictureDependencies.clear();
    activePreviewPoints.clear();
    _activePreviewPicture = null;
    _activePreviewBounds.value = null;

    if (rebuild) setState(() {});
  }

  void _recordActivePreviewPoint() {
    if (activePreviewPoints.isEmpty) return;

    final previousPicture = _activePreviewPicture;
    final previousBounds = _activePreviewBounds.value;
    final bounds = XppStrokeBounds.fromPoints(activePreviewPoints).rect;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    if (previousPicture != null && previousBounds != null) {
      canvas.save();
      canvas.translate(
        previousBounds.left - bounds.left,
        previousBounds.top - bounds.top,
      );
      canvas.drawPicture(previousPicture);
      canvas.restore();
    }

    final newPoints = activePreviewPoints.length == 1
        ? activePreviewPoints
        : activePreviewPoints.sublist(activePreviewPoints.length - 2);
    XppStrokePainter(
      points: newPoints,
      color: widget.color,
      topLeft: bounds.topLeft,
      smoothPressure: false,
    ).paint(canvas, bounds.size);

    _activePreviewPicture = recorder.endRecording();
    _activePreviewPictureDependencies.add(_activePreviewPicture!);
    _activePreviewBounds.value = bounds;
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
    resetPreview();
    _strokeRepaint.dispose();
    _eraserRepaint.dispose();
    _activePreviewBounds.dispose();
    super.dispose();
  }
}

class _PreviewPictureChunk {
  final Picture picture;
  final Rect bounds;

  _PreviewPictureChunk(this.picture, this.bounds);

  void dispose() => picture.dispose();
}

class _PreviewPicturePainter extends CustomPainter {
  final Picture? picture;
  final Picture? Function()? pictureProvider;

  _PreviewPicturePainter(this.picture, {Listenable? repaint})
    : pictureProvider = null,
      super(repaint: repaint);

  _PreviewPicturePainter.active({
    required this.pictureProvider,
    Listenable? repaint,
  }) : picture = null,
       super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final currentPicture = pictureProvider?.call() ?? picture;
    if (currentPicture == null) return;
    canvas.drawPicture(currentPicture);
  }

  @override
  bool shouldRepaint(covariant _PreviewPicturePainter oldDelegate) {
    return oldDelegate.picture != picture ||
        oldDelegate.pictureProvider != pictureProvider;
  }
}

class _EraserPreviewPainter extends CustomPainter {
  final List<Offset> Function() pointsProvider;
  final double Function() radiusProvider;

  _EraserPreviewPainter({
    required this.pointsProvider,
    required this.radiusProvider,
    Listenable? repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final points = pointsProvider();
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.28)
      ..strokeWidth = radiusProvider()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (points.length == 1) {
      canvas.drawCircle(points.first, paint.strokeWidth / 2, paint);
      return;
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _EraserPreviewPainter oldDelegate) {
    return oldDelegate.pointsProvider != pointsProvider ||
        oldDelegate.radiusProvider != radiusProvider;
  }
}
