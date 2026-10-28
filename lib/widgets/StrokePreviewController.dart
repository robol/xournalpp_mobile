import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';

class StrokePreviewController {
  static const int _chunkPointCount = 24;

  final Color? Function() colorProvider;
  final ValueNotifier<int> repaint = ValueNotifier<int>(0);
  final ValueNotifier<Rect?> activeBounds = ValueNotifier<Rect?>(null);

  final List<_PreviewPictureChunk> _chunks = [];
  final ValueNotifier<int> settledRepaint = ValueNotifier<int>(0);
  final List<XppStrokePoint> _activePoints = [];

  Picture? _activePicture;
  Duration _fadeTime = Duration.zero;
  Duration _lastTick = Duration.zero;
  late final Ticker _fadeTicker = Ticker((elapsed) {
    _fadeTime += elapsed - _lastTick;
    _lastTick = elapsed;
    _removeExpiredFadingChunks();
    settledRepaint.value++;
  });

  StrokePreviewController({required this.colorProvider});

  List<Widget> buildWidgets() {
    return [
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _SettledPreviewPainter(() => _chunks, settledRepaint),
            ),
          ),
        ),
      ),
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
    _activePicture?.dispose();
    _chunks.removeWhere((chunk) => clearFading || !chunk.isFading);
    settledRepaint.value++;
    _activePoints.clear();
    _activePicture = null;
    activeBounds.value = null;
    _updateFadeTimer();
  }

  void dispose() {
    _fadeTicker.stop();
    _reset(clearFading: true);
    _fadeTicker.dispose();
    settledRepaint.dispose();
    repaint.dispose();
    activeBounds.dispose();
  }

  void _addChunk(Picture picture, Rect bounds, {Duration? fadeOutDuration}) {
    _chunks.add(
      _PreviewPictureChunk(
        picture,
        bounds,
        clock: () => _fadeTime,
        fadeOutDuration: fadeOutDuration,
      ),
    );
    _compactSettledChunks();
    settledRepaint.value++;
    _updateFadeTimer();
  }

  void _compactSettledChunks() {
    // Keep widget and picture-handle counts bounded during long pen gestures.
    if (_chunks.length <= 32 || _chunks.take(16).any((c) => c.isFading)) return;
    final batch = _chunks.take(16).toList();
    final bounds = batch
        .map((c) => c.bounds)
        .reduce((a, b) => a.expandToInclude(b));
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder)..translate(-bounds.left, -bounds.top);
    for (final chunk in batch) {
      canvas.save();
      canvas.translate(chunk.bounds.left, chunk.bounds.top);
      canvas.drawPicture(chunk.picture);
      canvas.restore();
    }
    final picture = recorder.endRecording();
    for (final chunk in batch) {
      chunk.dispose();
    }
    _chunks.replaceRange(0, 16, [
      _PreviewPictureChunk(picture, bounds, clock: () => _fadeTime),
    ]);
  }

  void _updateFadeTimer() {
    final hasFadingChunks = _chunks.any((chunk) => chunk.isFading);
    if (!hasFadingChunks) {
      _fadeTicker.stop();
      _lastTick = Duration.zero;
    } else if (!_fadeTicker.isActive) {
      _fadeTicker.start();
    }
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
    previousPicture?.dispose();
    activeBounds.value = bounds;
  }
}

class _PreviewPictureChunk {
  final Picture picture;
  final Rect bounds;
  final Duration? fadeStartedAt;
  final Duration Function() clock;
  final Duration? fadeOutDuration;

  _PreviewPictureChunk(
    this.picture,
    this.bounds, {
    required this.clock,
    this.fadeOutDuration,
  }) : fadeStartedAt = fadeOutDuration == null ? null : clock();

  bool get isFading => fadeStartedAt != null && fadeOutDuration != null;

  bool get isExpired => isFading && _fadeProgress >= 1;

  double get opacity {
    if (!isFading) return 1;
    return (1 - _fadeProgress).clamp(0, 1).toDouble();
  }

  double get _fadeProgress {
    if (!isFading) return 0;
    final elapsed = (clock() - fadeStartedAt!);
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

class _SettledPreviewPainter extends CustomPainter {
  _SettledPreviewPainter(this.chunks, Listenable repaint)
    : super(repaint: repaint);
  final List<_PreviewPictureChunk> Function() chunks;
  @override
  void paint(Canvas canvas, Size size) {
    for (final chunk in chunks()) {
      canvas.save();
      if (chunk.isFading)
        canvas.saveLayer(
          chunk.bounds,
          Paint()..color = Colors.white.withValues(alpha: chunk.opacity),
        );
      canvas.translate(chunk.bounds.left, chunk.bounds.top);
      canvas.drawPicture(chunk.picture);
      if (chunk.isFading) canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SettledPreviewPainter oldDelegate) => true;
}
