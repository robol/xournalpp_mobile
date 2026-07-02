import 'package:flutter/material.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

typedef bool IsSelectableCallback(Offset offset);
typedef bool ShouldCatchCallback(Offset offset, EditingTool tool);

class XppPageContentWidget extends StatefulWidget {
  static const Color selectionColor = Color(0xFF1976D2);

  final Widget? child;
  final EditingTool? tool;
  final bool? catchTool;
  final Builder? contextMenuBuilder;
  final void Function(BuildContext context)? onSelected;
  final void Function(PointerDownEvent event)? onPointerDown;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelect;

  const XppPageContentWidget({
    Key? key,
    this.child,
    this.tool,
    this.catchTool,
    this.contextMenuBuilder,
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
      onPointerDown: widget.onPointerDown,
      child: GestureDetector(
        behavior: widget.selectionMode
            ? HitTestBehavior.translucent
            : HitTestBehavior.deferToChild,
        onTap: () {
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
