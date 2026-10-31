import 'package:flutter/widgets.dart';

/// Defer ink until the editor's incoming route transition has completed.
/// Once opened, remain open during subsequent transitions (including exit).
class StrokeOpeningGate extends StatefulWidget {
  const StrokeOpeningGate({super.key, required this.child});

  final Widget child;

  @override
  State<StrokeOpeningGate> createState() => _StrokeOpeningGateState();
}

class _StrokeOpeningGateState extends State<StrokeOpeningGate> {
  Animation<double>? _animation;
  ModalRoute<dynamic>? _route;
  bool _open = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_open) return;
    _route = ModalRoute.of(context);
    final animation = _route?.animation;
    if (!identical(animation, _animation)) {
      _animation?.removeStatusListener(_onStatus);
      _animation = animation;
      _animation?.addStatusListener(_onStatus);
    }
    if (animation == null) {
      _open = true;
      _animation?.removeStatusListener(_onStatus);
    } else {
      _onStatus(animation.status);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted || _open) return;
    // Hero measurement temporarily exposes an always-completed route proxy
    // while the destination is offstage. Recheck after the frame rather than
    // mistaking that measurement pass for the end of the entrance animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _open ||
          (_route?.offstage ?? false) ||
          _animation?.status != AnimationStatus.completed)
        return;
      _animation?.removeStatusListener(_onStatus);
      setState(() => _open = true);
    });
  }

  @override
  Widget build(BuildContext context) =>
      StrokeOpeningScope(open: _open, child: widget.child);

  @override
  void dispose() {
    _animation?.removeStatusListener(_onStatus);
    super.dispose();
  }
}

class StrokeOpeningScope extends InheritedWidget {
  const StrokeOpeningScope({
    super.key,
    required this.open,
    required super.child,
  });

  final bool open;

  static bool isOpen(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StrokeOpeningScope>()?.open ??
      true;

  @override
  bool updateShouldNotify(StrokeOpeningScope oldWidget) =>
      open != oldWidget.open;
}
