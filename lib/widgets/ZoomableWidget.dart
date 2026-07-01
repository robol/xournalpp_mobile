import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

class ZoomableWidget extends StatefulWidget {
  @required
  final Widget? child;
  @required
  final TransformationController? controller;
  @required
  final GestureScaleUpdateCallback? onInteractionUpdate;
  final GestureScaleStartCallback? onInteractionStart;

  const ZoomableWidget({
    Key? key,
    this.child,
    this.controller,
    this.onInteractionUpdate,
    this.onInteractionStart,
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
      child: InteractiveViewer(
        boundaryMargin: const EdgeInsets.all(16),
        onInteractionStart: widget.onInteractionStart,
        onInteractionUpdate: widget.onInteractionUpdate,
        panEnabled: _panEnabled,
        scaleEnabled: true,
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
}
