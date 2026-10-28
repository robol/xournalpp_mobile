import 'dart:async';
import 'package:flutter/scheduler.dart';

/// Serializes native stroke rasters across pages. Animation priority permits
/// progress during flings; recording itself must yield in small batches.
class RasterWorkQueue {
  final _jobs = <_RasterJob>[];
  bool _running = false;

  void schedule({
    required Future<void> Function() run,
    required bool Function() isCurrent,
    bool Function()? isVisible,
  }) {
    _jobs.removeWhere((job) => !job.isCurrent());
    _jobs.add(_RasterJob(run, isCurrent, isVisible ?? () => false));
    _drain();
  }

  void _drain() {
    if (_running) return;
    _jobs.removeWhere((job) => !job.isCurrent());
    if (_jobs.isEmpty) return;
    _running = true;
    SchedulerBinding.instance.scheduleTask(
      () async {
        try {
          _jobs.removeWhere((job) => !job.isCurrent());
          if (_jobs.isEmpty) return;
          final index = _jobs.indexWhere((job) => job.isVisible());
          final job = _jobs.removeAt(index < 0 ? 0 : index);
          if (job.isCurrent()) await job.run();
        } finally {
          _running = false;
          _drain();
        }
      },
      Priority.animation,
      debugLabel: 'stroke raster',
    );
  }
}

class _RasterJob {
  _RasterJob(this.run, this.isCurrent, this.isVisible);
  final Future<void> Function() run;
  final bool Function() isCurrent;
  final bool Function() isVisible;
}
