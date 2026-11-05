import 'dart:ui';

/// Distances are global logical pixels, independent of document zoom.
class PinchIntent {
  static const minimumSeparation = 24.0;
  static const movementThreshold = 8.0;
  double _initialDistance = 0;
  Offset _initialFocal = Offset.zero;

  void begin(double distance, Offset focal) {
    _initialDistance = distance;
    _initialFocal = focal;
  }

  bool accepts(double distance, Offset focal) =>
      _initialDistance >= minimumSeparation &&
      distance >= minimumSeparation &&
      ((distance - _initialDistance).abs() >= movementThreshold ||
          (focal - _initialFocal).distance >= movementThreshold);
}
