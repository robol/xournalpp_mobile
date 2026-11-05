import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:xournalpp/src/globals.dart';

/// Shared by the viewport and all page listeners. Ignored contacts remain
/// rejected until release, even when the cooldown ends or the app loses focus.
class StylusInputPolicy extends ChangeNotifier {
  final Set<int> _styluses = {};
  final Set<int> _touches = {};
  final Set<int> _rejected = {};
  final Set<int> _interrupted = {};
  Timer? _cooldown;
  static const proximityTimeout = Duration(seconds: 2);
  final Map<int, Timer> _proximityTimers = {};
  bool get stylusNearby => _proximityTimers.isNotEmpty;

  bool _isStylus(PointerEvent event) =>
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;

  /// Only an actual hover sample enables proximity. Contact-only devices
  /// retain the existing release cooldown.
  void hover(PointerHoverEvent event) {
    if (!_isStylus(event)) return;
    final wasNearby = stylusNearby;
    final rejectedBefore = _rejected.length;
    _proximityTimers.remove(event.device)?.cancel();
    _proximityTimers[event.device] = Timer(
      proximityTimeout,
      () => _leaveProximity(event.device),
    );
    _cooldown?.cancel();
    _cooldown = null;
    _rejected.addAll(_touches);
    if (!wasNearby || rejectedBefore != _rejected.length) notifyListeners();
  }

  void exitProximity(PointerExitEvent event) {
    if (_isStylus(event)) _leaveProximity(event.device);
  }

  void _leaveProximity(int device) {
    final timer = _proximityTimers.remove(device);
    if (timer == null) return;
    timer.cancel();
    if (!stylusNearby) _startCooldown();
    notifyListeners();
  }

  void _startCooldown() {
    _cooldown?.cancel();
    _cooldown = Timer(stylusTouchCooldown, () {
      _cooldown = null;
      notifyListeners();
    });
  }

  void _clearProximity() {
    for (final timer in _proximityTimers.values) {
      timer.cancel();
    }
    _proximityTimers.clear();
  }

  bool isPrimaryTouch(int pointer) =>
      _touches.where((id) => !rejects(id)).firstOrNull == pointer;

  bool get stylusActive => _styluses.isNotEmpty;
  bool get suppressTouch => stylusActive || stylusNearby || _cooldown != null;
  bool get hasRejectedTouches => _rejected.isNotEmpty;
  bool rejects(int pointer) =>
      _rejected.contains(pointer) || _interrupted.contains(pointer);

  void down(PointerDownEvent event) {
    _interrupted.remove(event.pointer);
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      if (!_styluses.add(event.pointer)) return;
      _cooldown?.cancel();
      _cooldown = null;
      _rejected.addAll(_touches);
      notifyListeners();
    } else if (event.kind == PointerDeviceKind.touch) {
      _touches.add(event.pointer);
      if (suppressTouch && _rejected.add(event.pointer)) notifyListeners();
    }
  }

  void up(PointerEvent event) {
    final stylusEnded = _styluses.remove(event.pointer);
    _touches.remove(event.pointer);
    final rejected = _rejected.remove(event.pointer);
    _interrupted.remove(event.pointer);
    if (stylusEnded) _startCooldown();
    if (stylusEnded || rejected) notifyListeners();
  }

  void interrupt() {
    _interrupted.addAll([..._styluses, ..._touches]);
    _styluses.clear();
    _clearProximity();
    _touches.clear();
    _rejected.clear();
    _cooldown?.cancel();
    _cooldown = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _clearProximity();
    _cooldown?.cancel();
    super.dispose();
  }
}
