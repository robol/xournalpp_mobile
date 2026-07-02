import 'package:flutter/material.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

typedef bool IsSelectableCallback(Offset offset);
typedef bool ShouldCatchCallback(Offset offset, EditingTool tool);

class XppPageContentWidget extends StatefulWidget {
  final Widget? child;
  final EditingTool? tool;
  final bool? catchTool;
  final Builder? contextMenuBuilder;
  final Function? onSelected;

  const XppPageContentWidget({
    Key? key,
    this.child,
    this.tool,
    this.catchTool,
    this.contextMenuBuilder,
    this.onSelected,
  }) : super(key: key);

  @override
  _XppPageContentWidgetState createState() => _XppPageContentWidgetState();
}

class _XppPageContentWidgetState extends State<XppPageContentWidget> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: widget.child,
    );
  }
}
