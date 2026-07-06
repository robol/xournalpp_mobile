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
  final bool drawWithStylusOnly;
  final Function({Offset? coordinates, double? radius})? filterEraser;
  final Function({List<Offset>? coordinates, double? radius})? filterEraserPath;
  final Function()? removeLastContent;
  final void Function(Rect? region)? onSelectionRegionChange;
  final VoidCallback? onSelectionClear;
  final bool Function(Offset position)? shouldMoveSelection;
  final void Function(Offset delta, {bool done})? onSelectionMove;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final VoidCallback? onPointerActivity;
  final void Function(Offset delta)? onPan;

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
    this.drawWithStylusOnly = false,
    this.filterEraser,
    this.filterEraserPath,
    this.removeLastContent,
    this.onSelectionRegionChange,
    this.onSelectionClear,
    this.shouldMoveSelection,
    this.onSelectionMove,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.onPointerActivity,
    this.onPan,
  }) : super(key: key);

  @override
  PointerListenerState createState() => PointerListenerState();
}

class PointerListenerState extends State<PointerListener> {
  static const Duration _laserPreviewFadeOutDuration = Duration(seconds: 3);
  static const double _laserWidth = 20;
  static const double _pageSwipeMinDistance = 80;
  static const double _pageSwipeHorizontalBias = 1.5;

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
  Offset? _selectionMoveLastPosition;
  bool _movingSelection = false;
  Offset? _pageSwipeStart;
  int? _pageSwipePointerDevice;
  Offset? _panLastPosition;
  int? _panPointer;
  bool _twoFingerPanning = false;

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
          widget.onPointerActivity?.call();
          if (_updatePan(data)) return;
          if (_detectTwoFingerGesture(data)) return;
          _updatePageSwipe(data);
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
          widget.onPointerActivity?.call();
          if (_detectTwoFingerGesture(data, shouldPop: true)) {
            _startPan(data, twoFinger: true);
            return;
          }

          setState(() {
            activeEditingTool = getEditingToolFromPointer(data);
            tool = getToolFromPointer(data);
          });
          if (activeEditingTool == EditingTool.MOVE) {
            _startPan(data);
            notifyDeviceChange(data);
            return;
          }
          _startPageSwipe(data);
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
          if (_finishPan(data)) {
            poppedContentForCurrentPointer = true;
          }
          final changedPage = _finishPageSwipe(data);
          if (changedPage) {
            poppedContentForCurrentPointer = true;
          } else if (activeEditingTool == EditingTool.SELECT) {
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
          _finishPan(data);
          _cancelPageSwipe(data);
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
          if (data is PointerScrollEvent) {
            widget.onPointerActivity?.call();
            widget.onPan?.call(-data.scrollDelta);
            notifyDeviceChange(data);
            return;
          }
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

  void _startPan(PointerEvent data, {bool twoFinger = false}) {
    _panLastPosition = data.position;
    _panPointer = data.pointer;
    _twoFingerPanning = twoFinger;
  }

  bool _updatePan(PointerMoveEvent data) {
    if (_panLastPosition == null) return false;
    if (_panPointer != data.pointer) return _twoFingerPanning;
    final delta = data.position - _panLastPosition!;
    _panLastPosition = data.position;
    widget.onPan?.call(delta);
    return true;
  }

  bool _finishPan(PointerEvent data) {
    if (_panPointer != null && _panPointer != data.pointer) {
      pointerTimestamps.remove(data.pointer);
      return false;
    }
    final wasPanning = _panLastPosition != null || _twoFingerPanning;
    _panLastPosition = null;
    _panPointer = null;
    _twoFingerPanning = false;
    pointerTimestamps.remove(data.pointer);
    return wasPanning;
  }

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
    _selectionMoveLastPosition = data.localPosition;
    _movingSelection =
        widget.shouldMoveSelection?.call(data.localPosition) ?? false;
  }

  void _updateSelectionRegion(PointerMoveEvent data) {
    if (_selectionStart == null) return;
    if (_movingSelection) {
      final lastPosition = _selectionMoveLastPosition;
      _selectionMoveLastPosition = data.localPosition;
      if (lastPosition == null) return;
      widget.onSelectionMove?.call(data.localPosition - lastPosition);
      return;
    }

    _selectionCurrent = data.localPosition;
    final distance = (_selectionCurrent! - _selectionStart!).distance;
    if (!_dragSelecting && distance < 4) return;

    _dragSelecting = true;
    widget.onSelectionRegionChange?.call(_selectionRect);
    setState(() {});
  }

  void _finishSelectionRegion() {
    if (_movingSelection) {
      widget.onSelectionMove?.call(Offset.zero, done: true);
    } else if (_dragSelecting) {
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
    _selectionMoveLastPosition = null;
    _movingSelection = false;
    setState(() {});
  }

  void _cancelSelectionRegion() {
    if (_selectionStart == null && !_dragSelecting) return;
    _selectionStart = null;
    _selectionCurrent = null;
    _selectionPointerDevice = null;
    _dragSelecting = false;
    _selectionMoveLastPosition = null;
    _movingSelection = false;
    setState(() {});
  }

  void _startPageSwipe(PointerDownEvent data) {
    if (!_isPageSwipePointer(data)) return;
    _pageSwipeStart = data.localPosition;
    _pageSwipePointerDevice = data.device;
  }

  void _updatePageSwipe(PointerMoveEvent data) {
    if (_pageSwipePointerDevice != data.device || _pageSwipeStart == null) {
      return;
    }

    final delta = data.localPosition - _pageSwipeStart!;
    if (delta.dy.abs() > delta.dx.abs() * _pageSwipeHorizontalBias) {
      _pageSwipeStart = null;
      _pageSwipePointerDevice = null;
    }
  }

  bool _finishPageSwipe(PointerUpEvent data) {
    if (_pageSwipePointerDevice != data.device || _pageSwipeStart == null) {
      return false;
    }

    final delta = data.localPosition - _pageSwipeStart!;
    _pageSwipeStart = null;
    _pageSwipePointerDevice = null;

    if (delta.dx.abs() < _pageSwipeMinDistance) return false;
    if (delta.dx.abs() < delta.dy.abs() * _pageSwipeHorizontalBias) {
      return false;
    }

    if (delta.dx < 0) {
      widget.onSwipeLeft?.call();
    } else {
      widget.onSwipeRight?.call();
    }
    return true;
  }

  void _cancelPageSwipe(PointerEvent data) {
    if (_pageSwipePointerDevice != data.device) return;
    _pageSwipeStart = null;
    _pageSwipePointerDevice = null;
  }

  bool _isPageSwipePointer(PointerDownEvent data) {
    return data.kind == PointerDeviceKind.touch &&
        getEditingToolFromPointer(data) == EditingTool.MOVE;
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
    if (widget.onDeviceChange == null) return;
    final deviceToolKnown = widget.toolData.keys.contains(data.kind);
    if (_lastNotifiedDeviceKind == data.kind && deviceToolKnown) return;

    _lastNotifiedDeviceKind = data.kind;
    widget.onDeviceChange?.call(device: data.device, kind: data.kind);
  }

  bool isPen(PointerEvent data) {
    return getEditingToolFromPointer(data) == EditingTool.STYLUS;
  }

  bool isHighlighter(PointerEvent data) {
    return getEditingToolFromPointer(data) == EditingTool.HIGHLIGHT;
  }

  bool isLaser(PointerEvent data) {
    return getEditingToolFromPointer(data) == EditingTool.LASER;
  }

  bool isEraser(PointerEvent data) {
    return getEditingToolFromPointer(data) == EditingTool.ERASER;
  }

  bool isText(PointerEvent data) {
    return getEditingToolFromPointer(data) == EditingTool.TEXT;
  }

  bool isLaTeX(PointerEvent data) {
    return getEditingToolFromPointer(data) == EditingTool.LATEX;
  }

  bool isSelect(PointerEvent data) {
    return getEditingToolFromPointer(data) == EditingTool.SELECT;
  }

  EditingTool? getEditingToolFromPointer(PointerEvent data) {
    EditingTool? tool;
    if (widget.toolData.keys.contains(data.kind)) {
      tool = widget.toolData[data.kind];
    } else if (data.kind == PointerDeviceKind.stylus) {
      tool = EditingTool.STYLUS;
    } else if (data.kind == PointerDeviceKind.invertedStylus) {
      tool = EditingTool.ERASER;
    }

    if (widget.drawWithStylusOnly && _isNonStylusPointer(data)) {
      return EditingTool.MOVE;
    }

    return tool;
  }

  bool _isNonStylusPointer(PointerEvent data) {
    return data.kind != PointerDeviceKind.stylus &&
        data.kind != PointerDeviceKind.invertedStylus;
  }

  bool _canPanWithPointer(PointerEvent data) {
    return getEditingToolFromPointer(data) == EditingTool.MOVE;
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
    if (!_canPanWithPointer(data)) return false;

    // detecting two-finger gestures
    final timestamp = DateTime.now();
    bool foundCloseOffset = false;
    pointerTimestamps.remove(data.pointer);
    pointerTimestamps.forEach((key, value) {
      if (value.difference(timestamp).inMilliseconds.abs() < 100) {
        foundCloseOffset = true;
      }
    });
    if (shouldPop && foundCloseOffset && !poppedContentForCurrentPointer) {
      poppedContentForCurrentPointer = true;
    }
    pointerTimestamps[data.pointer] = timestamp;
    return foundCloseOffset;
  }

  @override
  void dispose() {
    strokePreview.dispose();
    eraserPreview.dispose();
    super.dispose();
  }
}
