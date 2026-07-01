import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';

class StrokePreviewController {
  static const int _chunkPointCount = 24;

  final Color? Function() colorProvider;
  final ValueNotifier<int> repaint = ValueNotifier<int>(0);
  final ValueNotifier<Rect?> activeBounds = ValueNotifier<Rect?>(null);

  final List<_PreviewPictureChunk> _chunks = [];
  final List<Picture> _activePictureDependencies = [];
  final List<XppStrokePoint> _activePoints = [];

  Picture? _activePicture;

  StrokePreviewController({required this.colorProvider});

  List<Widget> buildWidgets() {
    return [
      ..._chunks.map((chunk) {
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
        valueListenable: activeBounds,
        builder: (context, bounds, child) {
          if (bounds == null || _activePicture == null) {
            return SizedBox.shrink();
          }

          return Positioned.fromRect(
            rect: bounds,
            child: RepaintBoundary(
              child: CustomPaint(
                foregroundPainter: _PreviewPicturePainter.active(
                  pictureProvider: () => _activePicture,
                  repaint: repaint,
                ),
              ),
            ),
          );
        },
      ),
    ];
  }

  void addPoint(XppStrokePoint point, {required VoidCallback onChunkReady}) {
    _activePoints.add(point);
    _recordActivePoint();

    if (_activePoints.length >= _chunkPointCount) {
      final lastPoint = _activePoints.last;
      onChunkReady();
      final picture = _activePicture;
      final bounds = activeBounds.value;
      if (picture != null && bounds != null) {
        _chunks.add(_PreviewPictureChunk(picture, bounds));
        _activePictureDependencies.remove(picture);
      }
      _activePoints
        ..clear()
        ..add(lastPoint);
      _activePicture = null;
      activeBounds.value = null;
      _recordActivePoint();
      return;
    }

    repaint.value++;
  }

  void reset() {
    for (final chunk in _chunks) {
      chunk.dispose();
    }
    for (final picture in _activePictureDependencies) {
      picture.dispose();
    }
    _chunks.clear();
    _activePictureDependencies.clear();
    _activePoints.clear();
    _activePicture = null;
    activeBounds.value = null;
  }

  void dispose() {
    reset();
    repaint.dispose();
    activeBounds.dispose();
  }

  void _recordActivePoint() {
    if (_activePoints.isEmpty) return;

    final previousPicture = _activePicture;
    final previousBounds = activeBounds.value;
    final bounds = XppStrokeBounds.fromPoints(_activePoints).rect;
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

    final newPoints = _activePoints.length == 1
        ? _activePoints
        : _activePoints.sublist(_activePoints.length - 2);
    XppStrokePainter(
      points: newPoints,
      color: colorProvider(),
      topLeft: bounds.topLeft,
      smoothPressure: false,
    ).paint(canvas, bounds.size);

    _activePicture = recorder.endRecording();
    _activePictureDependencies.add(_activePicture!);
    activeBounds.value = bounds;
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
