import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/widgets/EraserPreviewController.dart';
import 'package:xournalpp/widgets/StrokePointBuffer.dart';
import 'package:xournalpp/widgets/StrokePreviewController.dart';
import 'package:xournalpp/widgets/StrokeSimplifier.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:xournalpp/widgets/ShapeTool.dart';

class PointerListener extends StatefulWidget {
  final Function(XppContent?)? onNewContent;
  final void Function(List<XppContent>)? onNewShape;
  final ShapeSettings shapeSettings;
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
  final bool simplifyStrokes;
  final bool stylusPressureSensitivity;
  final ValueListenable<bool>? canPanViewportListenable;
  final Function({Offset? coordinates, double? radius})? filterEraser;
  final Function({List<Offset>? coordinates, double? radius})? filterEraserPath;
  final Function()? removeLastContent;
  final void Function(Rect? region)? onSelectionRegionChange;
  final VoidCallback? onSelectionClear;
  final VoidCallback? onSelectionMoveCancel;
  final bool Function(Offset position)? shouldMoveSelection;
  final void Function(Offset delta, {bool done})? onSelectionMove;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final VoidCallback? onPointerActivity;
  final void Function(Offset delta)? onPan;
  final void Function(Offset globalFocalPoint)? onPinchZoomStart;
  final void Function({
    required double scaleDelta,
    required Offset globalFocalPoint,
    required Offset globalFocalDelta,
  })?
  onPinchZoomUpdate;
  final VoidCallback? onPinchZoomEnd;
  final bool viewportGesturesExternallyManaged;

  const PointerListener({
    Key? key,
    this.onNewContent,
    this.onNewShape,
    this.shapeSettings = const ShapeSettings(),
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
    this.simplifyStrokes = true,
    this.stylusPressureSensitivity = true,
    this.canPanViewportListenable,
    this.filterEraser,
    this.filterEraserPath,
    this.removeLastContent,
    this.onSelectionRegionChange,
    this.onSelectionClear,
    this.onSelectionMoveCancel,
    this.shouldMoveSelection,
    this.onSelectionMove,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.onPointerActivity,
    this.onPan,
    this.onPinchZoomStart,
    this.onPinchZoomUpdate,
    this.onPinchZoomEnd,
    this.viewportGesturesExternallyManaged = false,
  }) : super(key: key);

  @override
  PointerListenerState createState() => PointerListenerState();
}

class _ShapePreviewPainter extends CustomPainter {
  _ShapePreviewPainter(this.start, this.end, this.settings);
  final Offset start;
  final Offset end;
  final ShapeSettings settings;
  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in shapeStrokes(start, end, settings)) {
      XppStrokePainter(
        points: stroke.points,
        color: stroke.color,
        topLeft: Offset.zero,
        smoothPressure: true,
        fill: stroke.fill,
      ).paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(_ShapePreviewPainter oldDelegate) =>
      start != oldDelegate.start ||
      end != oldDelegate.end ||
      settings != oldDelegate.settings;
}

class PointerListenerState extends State<PointerListener> {
  static const Duration _laserPreviewFadeOutDuration = Duration(seconds: 3);
  static const double _laserWidth = 20;
  static const double _pageSwipeMinDistance = 80;
  static const double _pageSwipeHorizontalBias = 1.5;
  static const int _stylusButtonMask =
      kPrimaryStylusButton | kSecondaryStylusButton;

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
  int _selectionGeneration = 0;
  bool _selectionUpdateScheduled = false;
  Offset? _pageSwipeStart;
  int? _pageSwipePointerDevice;
  Offset? _panLastPosition;
  int? _panPointer;
  bool _twoFingerPanning = false;
  final Set<int> _eraserOverridePointers = {};
  final Map<int, Offset> _touchPositions = {};
  bool _pinchZooming = false;
  double? _lastPinchDistance;
  Offset? _lastPinchFocalPoint;
  final Set<int> _suppressedTouchPointers = {};
  int? _shapePointer;
  Offset? _shapeStart;
  Offset? _shapeEnd;
  ShapeSettings? _gestureShapeSettings;

  void _clearShape() {
    _shapePointer = null;
    _shapeStart = null;
    _shapeEnd = null;
    _gestureShapeSettings = null;
  }

  /// Called synchronously when the canvas starts a pinch, including across pages.
  void cancelForViewportGesture() {
    _clearShape();
    _suppressedTouchPointers.addAll(_touchPositions.keys);
    strokePoints.clear();
    eraserPreview.reset();
    _panLastPosition = null;
    _panPointer = null;
    _twoFingerPanning = false;
    _pageSwipeStart = null;
    _pageSwipePointerDevice = null;
    _cancelSelectionRegion();
    resetPreview(rebuild: true);
  }

  @override
  Widget build(BuildContext context) {
    final panListenable = widget.canPanViewportListenable;
    if (panListenable != null) {
      return ValueListenableBuilder<bool>(
        valueListenable: panListenable,
        builder: (context, canPanViewport, child) {
          drawingEnabled = !canPanViewport;
          return _buildPointerTree(child!);
        },
        child: widget.child,
      );
    }
    return _buildPointerTree(widget.child!);
  }

  Widget _buildPointerTree(Widget child) {
    return MouseRegion(
      onHover: (event) {
        notifyDeviceChange(event);
      },
      opaque: false,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerMove: (data) {
          if (!mounted) return;
          if (_suppressedTouchPointers.contains(data.pointer)) return;
          widget.onPointerActivity?.call();
          if (_updatePinchZoom(data)) return;
          if (_updatePan(data)) return;
          if (_detectTwoFingerGesture(data)) return;
          _updatePageSwipe(data);
          notifyDeviceChange(data);
          if (!drawingEnabled) return;
          if (_shapePointer == data.pointer) {
            _setStateIfMounted(() => _shapeEnd = data.localPosition);
            return;
          }
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
          if (!mounted) return;
          if (widget.viewportGesturesExternallyManaged &&
              data.kind == PointerDeviceKind.touch) {
            _touchPositions[data.pointer] = data.position;
          }
          widget.onPointerActivity?.call();
          if (_startPinchZoomIfNeeded(data)) return;
          if (_detectTwoFingerGesture(data, shouldPop: true)) {
            _startPan(data, twoFinger: true);
            return;
          }

          _setStateIfMounted(() {
            activeEditingTool = getEditingToolFromPointer(data);
            tool = getToolFromPointer(data);
          });
          if (activeEditingTool == EditingTool.MOVE) {
            if (!widget.viewportGesturesExternallyManaged ||
                data.kind != PointerDeviceKind.touch) {
              _startPan(data);
            }
            notifyDeviceChange(data);
            return;
          }
          _startPageSwipe(data);
          notifyDeviceChange(data);
          if (drawingEnabled &&
              activeEditingTool == EditingTool.SHAPE &&
              _shapePointer == null) {
            _setStateIfMounted(() {
              _shapePointer = data.pointer;
              _shapeStart = data.localPosition;
              _shapeEnd = data.localPosition;
              _gestureShapeSettings = widget.shapeSettings;
            });
            return;
          }
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
          if (isText(data)) {
            _insertText(data);
          }
        },
        onPointerUp: (data) {
          if (!mounted) return;
          if (_suppressedTouchPointers.remove(data.pointer)) {
            _touchPositions.remove(data.pointer);
            return;
          }
          if (_finishPinchZoom(data)) {
            poppedContentForCurrentPointer = true;
          }
          if (_finishPan(data)) {
            poppedContentForCurrentPointer = true;
          }
          final changedPage = _finishPageSwipe(data);
          if (_shapePointer == data.pointer) {
            final shapes = shapeStrokes(
              _shapeStart!,
              data.localPosition,
              _gestureShapeSettings!,
            );
            if (!changedPage && !poppedContentForCurrentPointer)
              widget.onNewShape?.call(shapes);
            _clearShape();
          }
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
          _eraserOverridePointers.remove(data.pointer);
          if (activeEditingTool != EditingTool.LASER) {
            resetPreview(rebuild: true);
          }
        },
        onPointerCancel: (data) {
          if (!mounted) return;
          if (_shapePointer == data.pointer) _clearShape();
          _suppressedTouchPointers.remove(data.pointer);
          _finishPinchZoom(data);
          _finishPan(data);
          _cancelPageSwipe(data);
          if (activeEditingTool == EditingTool.LASER) {
            finishLaserPreview();
          }
          _cancelSelectionRegion();
          strokePoints.clear();
          _eraserOverridePointers.remove(data.pointer);
          poppedContentForCurrentPointer = false;
          eraserPreview.reset();
          if (activeEditingTool != EditingTool.LASER) {
            resetPreview(rebuild: true);
          }
        },
        onPointerSignal: (data) {
          if (!mounted) return;
          if (data is PointerScrollEvent) {
            GestureBinding.instance.pointerSignalResolver.register(data, (_) {
              widget.onPan?.call(-data.scrollDelta);
            });
            notifyDeviceChange(data);
            return;
          }
          _setStateIfMounted(() {
            activeEditingTool = getEditingToolFromPointer(data);
            tool = getToolFromPointer(data);
          });
          notifyDeviceChange(data);
        },
        child: Stack(
          children: [
            child,
            ...strokePreview.buildWidgets(),
            if (_shapeStart != null && _shapeEnd != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ShapePreviewPainter(
                      _shapeStart!,
                      _shapeEnd!,
                      _gestureShapeSettings!,
                    ),
                  ),
                ),
              ),
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
                      previewPath: eraserPreview.previewPath,
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
    _clearShape();
    strokePoints.clear();
    eraserPreview.reset();
    _eraserOverridePointers.clear();
    _touchPositions.clear();
    _pinchZooming = false;
    _lastPinchDistance = null;
    _lastPinchFocalPoint = null;
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

  bool _startPinchZoomIfNeeded(PointerDownEvent data) {
    if (widget.viewportGesturesExternallyManaged) return false;
    if (data.kind != PointerDeviceKind.touch) return false;
    _touchPositions[data.pointer] = data.position;

    if (_pinchZooming) return true;
    if (_touchPositions.length != 2) return false;

    _cancelPageSwipe(data);
    _cancelSelectionRegion();
    _clearShape();
    _panLastPosition = null;
    _panPointer = null;
    _twoFingerPanning = false;
    strokePoints.clear();
    eraserPreview.reset();
    resetPreview(rebuild: true);
    poppedContentForCurrentPointer = true;

    final metrics = _currentPinchMetrics();
    if (metrics == null) return false;
    _pinchZooming = true;
    _lastPinchDistance = metrics.distance;
    _lastPinchFocalPoint = metrics.focalPoint;
    widget.onPinchZoomStart?.call(metrics.focalPoint);
    return true;
  }

  bool _updatePinchZoom(PointerMoveEvent data) {
    if (widget.viewportGesturesExternallyManaged) return false;
    if (data.kind == PointerDeviceKind.touch) {
      _touchPositions[data.pointer] = data.position;
    }
    if (!_pinchZooming) return false;

    final metrics = _currentPinchMetrics();
    final previousDistance = _lastPinchDistance;
    final previousFocalPoint = _lastPinchFocalPoint;
    if (metrics == null ||
        previousDistance == null ||
        previousDistance <= 0 ||
        previousFocalPoint == null) {
      return true;
    }

    _lastPinchDistance = metrics.distance;
    _lastPinchFocalPoint = metrics.focalPoint;
    widget.onPinchZoomUpdate?.call(
      scaleDelta: metrics.distance / previousDistance,
      globalFocalPoint: metrics.focalPoint,
      globalFocalDelta: metrics.focalPoint - previousFocalPoint,
    );
    return true;
  }

  bool _finishPinchZoom(PointerEvent data) {
    if (data.kind == PointerDeviceKind.touch) {
      _touchPositions.remove(data.pointer);
    }

    if (!_pinchZooming) return false;
    if (_touchPositions.length >= 2) {
      final metrics = _currentPinchMetrics();
      _lastPinchDistance = metrics?.distance;
      _lastPinchFocalPoint = metrics?.focalPoint;
      return true;
    }

    _pinchZooming = false;
    _lastPinchDistance = null;
    _lastPinchFocalPoint = null;
    widget.onPinchZoomEnd?.call();
    return true;
  }

  _PinchMetrics? _currentPinchMetrics() {
    if (_touchPositions.length < 2) return null;
    final points = _touchPositions.values.take(2).toList();
    final focalPoint = Offset(
      (points[0].dx + points[1].dx) / 2,
      (points[0].dy + points[1].dy) / 2,
    );
    return _PinchMetrics(
      focalPoint: focalPoint,
      distance: (points[1] - points[0]).distance,
    );
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
    if (!_selectionUpdateScheduled) {
      _selectionUpdateScheduled = true;
      final generation = _selectionGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _selectionGeneration) return;
        _selectionUpdateScheduled = false;
        if (_dragSelecting)
          widget.onSelectionRegionChange?.call(_selectionRect);
      });
    }
    _setStateIfMounted(() {});
  }

  void _finishSelectionRegion() {
    _selectionGeneration++;
    _selectionUpdateScheduled = false;
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
    _movingSelection = false;
    _selectionPointerDevice = null;
    _selectionStart = null;
    _selectionCurrent = null;
    _dragSelecting = false;
    _selectionMoveLastPosition = null;
    _movingSelection = false;
    _setStateIfMounted(() {});
  }

  void _cancelSelectionRegion() {
    _selectionGeneration++;
    _selectionUpdateScheduled = false;
    if (_movingSelection) widget.onSelectionMoveCancel?.call();
    _movingSelection = false;
    if (_selectionStart == null && !_dragSelecting) return;
    _selectionStart = null;
    _selectionCurrent = null;
    _selectionPointerDevice = null;
    _dragSelecting = false;
    _selectionMoveLastPosition = null;
    _movingSelection = false;
    _setStateIfMounted(() {});
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

  void _insertText(PointerDownEvent data) {
    final offset = data.localPosition;
    final color = _activeStrokeColor;
    final size = widget.strokeWidth! * 3;
    Future<void>.delayed(Duration.zero, () {
      if (!mounted || _consumeContentPointerDown(data)) return;
      XppText.edit(context: context, offset: offset, color: color, size: size)
          .then((value) {
            if (mounted) widget.onNewContent?.call(value);
          })
          .catchError((_) {});
    });
  }

  void saveStroke(XppStrokeTool tool) {
    final smoothedPoints = strokePoints.smoothedPoints();
    if (smoothedPoints.isNotEmpty) {
      XppStroke stroke = XppStroke.byTool(
        tool: tool,
        points: widget.simplifyStrokes
            ? simplifyStrokePoints(smoothedPoints)
            : smoothedPoints,
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
    _setStateIfMounted(() {});
  }

  void addStrokePoint(PointerEvent data) {
    activeEditingTool = getEditingToolFromPointer(data);
    tool = getToolFromPointer(data);

    double? width = widget.strokeWidth;
    final isStylus =
        data.kind == PointerDeviceKind.stylus ||
        data.kind == PointerDeviceKind.invertedStylus;
    final min = data.pressureMin;
    final max = data.pressureMax;
    if (widget.stylusPressureSensitivity &&
        isStylus &&
        !isHighlighter(data) &&
        !isLaser(data) &&
        width != null &&
        data.pressure.isFinite &&
        min.isFinite &&
        max.isFinite &&
        max > min &&
        (max - min).isFinite) {
      // Keep light contact visible; full pressure uses the selected width.
      final pressure = ((data.pressure - min) / (max - min)).clamp(0.1, 1.0);
      width *= pressure;
    }

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
      onChunkReady: () => _setStateIfMounted(() {}),
    );
  }

  void resetPreview({bool rebuild = false}) {
    strokePreview.reset();

    if (rebuild) _setStateIfMounted(() {});
  }

  void _setStateIfMounted(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
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

    if (_usesStylusButtonEraser(data, tool)) {
      _eraserOverridePointers.add(data.pointer);
      return EditingTool.ERASER;
    }

    if (_eraserOverridePointers.contains(data.pointer)) {
      return EditingTool.ERASER;
    }

    return tool;
  }

  bool _usesStylusButtonEraser(PointerEvent data, EditingTool? tool) {
    if (data.kind != PointerDeviceKind.stylus) return false;
    if (tool != EditingTool.STYLUS && tool != EditingTool.HIGHLIGHT) {
      return false;
    }
    return data.buttons & _stylusButtonMask != 0;
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
    if (widget.viewportGesturesExternallyManaged) return false;
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

class _PinchMetrics {
  final Offset focalPoint;
  final double distance;

  const _PinchMetrics({required this.focalPoint, required this.distance});
}
