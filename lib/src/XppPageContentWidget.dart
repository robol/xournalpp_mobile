import 'package:xournalpp/widgets/ContentTapScope.dart';
import 'package:flutter/material.dart';

class XppPageContentWidget extends StatefulWidget {
  static const Color selectionColor = Color(0xFF1976D2);

  final Widget? child;
  final void Function(BuildContext context)? onSelected;
  final void Function(PointerDownEvent event)? onPointerDown;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelect;

  const XppPageContentWidget({
    Key? key,
    this.child,
    this.onSelected,
    this.onPointerDown,
    this.selectionMode = false,
    this.selected = false,
    this.onSelect,
  }) : super(key: key);

  @override
  _XppPageContentWidgetState createState() => _XppPageContentWidgetState();
}

class _XppPageContentWidgetState extends State<XppPageContentWidget> {
  ContentTapToken? _tapToken;
  int? _tapPointer;
  @override
  Widget build(BuildContext context) {
    final child = widget.selected
        ? DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: XppPageContentWidget.selectionColor,
                width: 1.5,
              ),
            ),
            child: widget.child,
          )
        : widget.child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final token = ContentTapScope.of(context)?.register(event);
        if (_tapPointer == null) {
          _tapPointer = event.pointer;
          _tapToken = token;
        }
        widget.onPointerDown?.call(event);
      },
      child: GestureDetector(
        behavior: widget.selectionMode
            ? HitTestBehavior.translucent
            : HitTestBehavior.deferToChild,
        onTapCancel: () {
          _tapPointer = null;
          _tapToken = null;
        },
        onTap: () {
          final cancelled = _tapToken?.cancelled == true;
          _tapPointer = null;
          _tapToken = null;
          if (cancelled) return;
          if (widget.selectionMode) {
            widget.onSelect?.call();
            return;
          }
          widget.onSelected?.call(context);
        },
        child: child,
      ),
    );
  }
}
