import 'dart:async';
import 'package:flutter/scheduler.dart';

/// Visible work can progress during flings; speculative work only runs idle.
class RasterWorkQueue {
  final _jobs = <_RasterJob>[];
  bool _running = false;
  bool _visibleScheduled = false;
  bool _idleScheduled = false;

  bool get hasVisibleWork =>
      _jobs.any((job) => job.isCurrent() && job.isVisible());

  void prioritiesChanged() => _drain();

  void schedule({
    required Future<void> Function() run,
    required bool Function() isCurrent,
    bool Function()? isVisible,
    bool Function()? backgroundAllowed,
  }) {
    _jobs.removeWhere((job) => !job.isCurrent());
    _jobs.add(
      _RasterJob(
        run,
        isCurrent,
        isVisible ?? () => true,
        backgroundAllowed ?? () => true,
      ),
    );
    _drain();
  }

  void _drain() {
    if (_running) return;
    _jobs.removeWhere((job) => !job.isCurrent());
    if (_jobs.isEmpty) return;
    if (hasVisibleWork) {
      if (!_visibleScheduled) _schedule(visible: true);
    } else if (_jobs.any((job) => job.backgroundAllowed())) {
      if (!_idleScheduled) _schedule(visible: false);
    }
  }

  void _schedule({required bool visible}) {
    if (visible) {
      _visibleScheduled = true;
    } else {
      _idleScheduled = true;
    }
    SchedulerBinding.instance.scheduleTask(
      () async {
        if (visible) {
          _visibleScheduled = false;
        } else {
          _idleScheduled = false;
        }
        if (_running) return;
        try {
          _jobs.removeWhere((job) => !job.isCurrent());
          if (_jobs.isEmpty) return;
          final index = _jobs.indexWhere(
            (job) => visible
                ? job.isVisible()
                : !job.isVisible() && job.backgroundAllowed(),
          );
          if (index < 0 || (!visible && hasVisibleWork)) return;
          final job = _jobs.removeAt(index);
          _running = true;
          if (job.isCurrent()) await job.run();
        } finally {
          _running = false;
          _drain();
        }
      },
      visible ? Priority.animation : Priority.idle,
      debugLabel: 'stroke raster',
    );
  }
}

class _RasterJob {
  _RasterJob(this.run, this.isCurrent, this.isVisible, this.backgroundAllowed);
  final Future<void> Function() run;
  final bool Function() isCurrent;
  final bool Function() isVisible;
  final bool Function() backgroundAllowed;
}
