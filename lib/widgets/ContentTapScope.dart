import 'package:flutter/material.dart';

class ContentTapToken {
  bool cancelled = false;
}

/// Lets content recognizers honor cancellation performed by raw canvas input.
class ContentTapScope extends InheritedWidget {
  const ContentTapScope({
    super.key,
    required this.register,
    required super.child,
  });
  final ContentTapToken Function(PointerDownEvent) register;
  static ContentTapScope? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ContentTapScope>();
  @override
  bool updateShouldNotify(ContentTapScope oldWidget) => false;
}
