import 'package:flutter/material.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

typedef bool IsSelectableCallback(Offset offset);
typedef bool ShouldCatchCallback(Offset offset, EditingTool tool);

class XppPageContentWidget extends StatefulWidget {
  final Widget? child;
  final EditingTool? tool;
  final bool? catchTool;
  final Builder? contextMenuBuilder;
  final void Function(BuildContext context)? onSelected;
  final void Function(PointerDownEvent event)? onPointerDown;

  const XppPageContentWidget({
    Key? key,
    this.child,
    this.tool,
    this.catchTool,
    this.contextMenuBuilder,
    this.onSelected,
    this.onPointerDown,
  }) : super(key: key);

  @override
  _XppPageContentWidgetState createState() => _XppPageContentWidgetState();
}

class _XppPageContentWidgetState extends State<XppPageContentWidget> {
  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: widget.onPointerDown,
      child: GestureDetector(
        onTap: () => widget.onSelected?.call(context),
        child: widget.child,
      ),
    );
  }
}
