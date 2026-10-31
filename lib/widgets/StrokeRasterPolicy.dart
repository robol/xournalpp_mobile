import 'dart:async';

import 'package:flutter/widgets.dart';

/// Editor-local eligibility for speculative stroke raster work.
class StrokeRasterPolicy extends ChangeNotifier {
  StrokeRasterPolicy({required this.viewport}) {
    noteActivity();
  }

  final Rect? Function() viewport;
  Timer? _idleTimer;
  bool backgroundAllowed = false;
  bool Function()? interactionActive;
  final _workListeners = <VoidCallback, int>{};

  // Many stroke runs share a queue. Wake it once per policy update, not once
  // per run (which would repeatedly scan a dense page's entire job list).
  void addWorkListener(VoidCallback listener) {
    final count = _workListeners[listener] ?? 0;
    _workListeners[listener] = count + 1;
    if (count == 0) addListener(listener);
  }

  void removeWorkListener(VoidCallback listener) {
    final count = _workListeners[listener];
    if (count == null) return;
    if (count == 1) {
      _workListeners.remove(listener);
      removeListener(listener);
    } else {
      _workListeners[listener] = count - 1;
    }
  }

  void noteActivity() {
    backgroundAllowed = false;
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(milliseconds: 500), () {
      if (interactionActive?.call() ?? false) {
        noteActivity();
        return;
      }
      backgroundAllowed = true;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Called after layout so queued work sees the new viewport immediately.
  void viewportChanged() => notifyListeners();

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }
}

class StrokeRasterScope extends InheritedWidget {
  const StrokeRasterScope({
    super.key,
    required this.policy,
    required super.child,
  });

  final StrokeRasterPolicy policy;

  static StrokeRasterPolicy? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StrokeRasterScope>()?.policy;

  @override
  bool updateShouldNotify(StrokeRasterScope oldWidget) =>
      policy != oldWidget.policy;
}
