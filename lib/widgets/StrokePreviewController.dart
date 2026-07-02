import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';

class StrokePreviewController {
  static const int _chunkPointCount = 24;
  static const Duration _fadeTickDuration = Duration(milliseconds: 50);

  final Color? Function() colorProvider;
  final ValueNotifier<int> repaint = ValueNotifier<int>(0);
  final ValueNotifier<Rect?> activeBounds = ValueNotifier<Rect?>(null);

  final List<_PreviewPictureChunk> _chunks = [];
  final List<Picture> _activePictureDependencies = [];
  final List<XppStrokePoint> _activePoints = [];

  Picture? _activePicture;
  Timer? _fadeTimer;

  StrokePreviewController({required this.colorProvider});

  List<Widget> buildWidgets() {
    return [
      ..._chunks.map((chunk) {
        return Positioned.fromRect(
          rect: chunk.bounds,
          child: ValueListenableBuilder<int>(
            valueListenable: repaint,
            builder: (context, value, child) {
              return Opacity(opacity: chunk.opacity, child: child);
            },
            child: RepaintBoundary(
              child: CustomPaint(
                foregroundPainter: _PreviewPicturePainter(chunk.picture),
              ),
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

  void addPoint(
    XppStrokePoint point, {
    required VoidCallback onChunkReady,
    Duration? fadeOutDuration,
    bool showSinglePoint = false,
  }) {
    _activePoints.add(point);
    _recordActivePoint(showSinglePoint: showSinglePoint);

    if (_activePoints.length >= _chunkPointCount) {
      final lastPoint = _activePoints.last;
      onChunkReady();
      final picture = _activePicture;
      final bounds = activeBounds.value;
      if (picture != null && bounds != null) {
        _addChunk(picture, bounds, fadeOutDuration: fadeOutDuration);
        _activePictureDependencies.remove(picture);
      }
      _activePoints
        ..clear()
        ..add(lastPoint);
      _activePicture = null;
      activeBounds.value = null;
      _recordActivePoint(showSinglePoint: showSinglePoint);
      return;
    }

    repaint.value++;
  }

  void reset() {
    _reset(clearFading: false);
  }

  void finish({Duration? fadeOutDuration}) {
    final picture = _activePicture;
    final bounds = activeBounds.value;
    if (picture != null && bounds != null) {
      _addChunk(picture, bounds, fadeOutDuration: fadeOutDuration);
      _activePictureDependencies.remove(picture);
    }
    _activePoints.clear();
    _activePicture = null;
    activeBounds.value = null;
    repaint.value++;
  }

  void _reset({required bool clearFading}) {
    for (final chunk in _chunks) {
      if (clearFading || !chunk.isFading) {
        chunk.dispose();
      }
    }
    for (final picture in _activePictureDependencies) {
      picture.dispose();
    }
    _chunks.removeWhere((chunk) => clearFading || !chunk.isFading);
    _activePictureDependencies.clear();
    _activePoints.clear();
    _activePicture = null;
    activeBounds.value = null;
    _updateFadeTimer();
  }

  void dispose() {
    _fadeTimer?.cancel();
    _reset(clearFading: true);
    repaint.dispose();
    activeBounds.dispose();
  }

  void _addChunk(Picture picture, Rect bounds, {Duration? fadeOutDuration}) {
    _chunks.add(
      _PreviewPictureChunk(picture, bounds, fadeOutDuration: fadeOutDuration),
    );
    _updateFadeTimer();
  }

  void _updateFadeTimer() {
    final hasFadingChunks = _chunks.any((chunk) => chunk.isFading);
    if (!hasFadingChunks) {
      _fadeTimer?.cancel();
      _fadeTimer = null;
      return;
    }

    _fadeTimer ??= Timer.periodic(_fadeTickDuration, (_) {
      _removeExpiredFadingChunks();
      repaint.value++;
    });
  }

  void _removeExpiredFadingChunks() {
    _chunks.removeWhere((chunk) {
      if (!chunk.isExpired) return false;
      chunk.dispose();
      return true;
    });
    _updateFadeTimer();
  }

  void _recordActivePoint({required bool showSinglePoint}) {
    if (_activePoints.isEmpty) return;
    if (_activePoints.length == 1 && !showSinglePoint) return;

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
  final DateTime? fadeStartedAt;
  final Duration? fadeOutDuration;

  _PreviewPictureChunk(this.picture, this.bounds, {this.fadeOutDuration})
    : fadeStartedAt = fadeOutDuration == null ? null : DateTime.now();

  bool get isFading => fadeStartedAt != null && fadeOutDuration != null;

  bool get isExpired => isFading && _fadeProgress >= 1;

  double get opacity {
    if (!isFading) return 1;
    return (1 - _fadeProgress).clamp(0, 1).toDouble();
  }

  double get _fadeProgress {
    if (!isFading) return 0;
    final elapsed = DateTime.now().difference(fadeStartedAt!);
    return elapsed.inMilliseconds / fadeOutDuration!.inMilliseconds;
  }

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
