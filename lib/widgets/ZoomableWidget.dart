import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3, Vector4;

class ZoomableWidget extends StatefulWidget {
  @required
  final Widget? child;
  @required
  final TransformationController? controller;
  @required
  final GestureScaleUpdateCallback? onInteractionUpdate;
  final GestureScaleStartCallback? onInteractionStart;
  final VoidCallback? onTransformationChanged;

  const ZoomableWidget({
    Key? key,
    this.child,
    this.controller,
    this.onInteractionUpdate,
    this.onInteractionStart,
    this.onTransformationChanged,
  }) : super(key: key);

  @override
  ZoomableWidgetState createState() => ZoomableWidgetState();
}

class ZoomableWidgetState extends State<ZoomableWidget> {
  bool enabled = false;
  final Set<int> _touchPointers = <int>{};

  bool get _panEnabled => enabled || _touchPointers.length >= 2;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerUp,
      onPointerSignal: _handlePointerSignal,
      child: InteractiveViewer(
        boundaryMargin: const EdgeInsets.all(16),
        onInteractionStart: widget.onInteractionStart,
        onInteractionUpdate: widget.onInteractionUpdate,
        panEnabled: _panEnabled,
        scaleEnabled: true,
        trackpadScrollCausesScale: false,
        scaleFactor: double.infinity,
        transformationController: widget.controller,
        minScale: 0.1,
        maxScale: 5,
        child: widget.child!,
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    setState(() {
      _touchPointers.add(event.pointer);
    });
  }

  void _handlePointerUp(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    setState(() {
      _touchPointers.remove(event.pointer);
    });
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || widget.controller == null) return;

    if (HardwareKeyboard.instance.isControlPressed) {
      _zoomByScroll(event);
      return;
    }

    final matrix = widget.controller!.value.clone();
    matrix.setTranslation(
      Vector3(
        matrix.entry(0, 3) - event.scrollDelta.dx,
        matrix.entry(1, 3) - event.scrollDelta.dy,
        0,
      ),
    );
    widget.controller!.value = matrix;
    widget.onTransformationChanged?.call();
  }

  void _zoomByScroll(PointerScrollEvent event) {
    final matrix = widget.controller!.value;
    final currentScale = matrix.getMaxScaleOnAxis();
    if (currentScale <= 0) return;

    final scaleDelta = pow(1.0015, -event.scrollDelta.dy).toDouble();
    final targetScale = max(0.1, min(5.0, currentScale * scaleDelta));
    final scaleRatio = targetScale / currentScale;
    final focalPoint = event.localPosition;
    final currentX = matrix.entry(0, 3);
    final currentY = matrix.entry(1, 3);

    final updatedMatrix = Matrix4.identity()
      ..setDiagonal(Vector4(targetScale, targetScale, 1, 1))
      ..setTranslation(
        Vector3(
          focalPoint.dx - (focalPoint.dx - currentX) * scaleRatio,
          focalPoint.dy - (focalPoint.dy - currentY) * scaleRatio,
          0,
        ),
      );
    widget.controller!.value = updatedMatrix;
    widget.onTransformationChanged?.call();
  }
}
