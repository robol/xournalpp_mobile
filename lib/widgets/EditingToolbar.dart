import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:xournalpp/widgets/ToolSettingDialog.dart';

class EditingToolBar extends StatefulWidget {
  final Function(Map<PointerDeviceKind?, EditingTool>?)? onNewDeviceMap;
  final Function(double newWidth, EditingTool? tool)? onWidthChange;
  final Map<PointerDeviceKind?, EditingTool>? deviceMap;
  final Function(Color color, EditingTool? tool)? onColorChange;
  final Function(EditingTool? tool)? getColor;
  final Function(EditingTool? tool)? getWidth;
  final double Function(EditingTool? tool)? getMinWidth;
  final double Function(EditingTool? tool)? getMaxWidth;
  final int? Function(EditingTool? tool)? getWidthDivisions;
  final VoidCallback? onBackgroundSettings;
  final VoidCallback? onPasteSelection;
  final bool compact;

  const EditingToolBar({
    Key? key,
    this.onNewDeviceMap,
    this.deviceMap,
    this.onWidthChange,
    this.onColorChange,
    this.getColor,
    this.getWidth,
    this.getMinWidth,
    this.getMaxWidth,
    this.getWidthDivisions,
    this.onBackgroundSettings,
    this.onPasteSelection,
    this.compact = false,
  }) : super(key: key);

  @override
  EditingToolBarState createState() => EditingToolBarState();
}

class EditingToolBarState extends State<EditingToolBar> {
  PointerDeviceKind? currentDevice;

  double width = 2.5;

  @override
  Widget build(BuildContext context) {
    initializeTool();
    return Container(
      height: widget.compact ? 48 : 64,
      padding: widget.compact ? EdgeInsets.zero : const EdgeInsets.all(8),
      alignment: Alignment.center,
      child: MouseRegion(
        onHover: (event) {
          if (currentDevice != event.kind) {
            setState(() => currentDevice = event.kind);
          }
        },
        child: _buildToolLayout([
          getInkwellButton(
            EditingTool.STYLUS,
            FaIcon(FontAwesomeIcons.penClip),
            enableSettings: true,
          ),
          getInkwellButton(
            EditingTool.HIGHLIGHT,
            FaIcon(FontAwesomeIcons.highlighter),
            enableSettings: true,
          ),
          getInkwellButton(
            EditingTool.ERASER,
            FaIcon(FontAwesomeIcons.eraser),
            enableSettings: true,
            usePrimaryColor: true,
          ),
          getInkwellButton(EditingTool.LASER, Icon(Icons.adjust)),
          getInkwellButton(
            EditingTool.MOVE,
            Icon(Icons.pan_tool),
            usePrimaryColor: true,
          ),
          getInkwellButton(
            EditingTool.TEXT,
            Icon(Icons.keyboard),
            usePrimaryColor: true,
          ),
          getInkwellButton(
            EditingTool.LATEX,
            Icon(Icons.science),
            usePrimaryColor: true,
          ),
          // TODO: Currently not implemented
          // getInkwellButton(
          //   EditingTool.IMAGE,
          //   Icon(Icons.add_photo_alternate),
          //   usePrimaryColor: true,
          // ),
          getInkwellButton(
            EditingTool.SELECT,
            Icon(Icons.tab_unselected),
            usePrimaryColor: true,
          ),
          if (widget.compact)
            IconButton(
              onPressed: widget.onPasteSelection,
              tooltip: 'Paste copied selection',
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              icon: const Icon(Icons.content_paste),
            )
          else
            FloatingActionButton(
              heroTag: 'PasteSelection',
              onPressed: widget.onPasteSelection,
              tooltip: 'Paste copied selection',
              backgroundColor: Theme.of(context).cardColor,
              child: const Icon(Icons.content_paste),
            ),
          if (widget.compact)
            IconButton(
              onPressed: widget.onBackgroundSettings,
              tooltip: 'Change background',
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              icon: const Icon(Icons.format_paint),
            )
          else
            FloatingActionButton(
              heroTag: 'PageBackground',
              onPressed: widget.onBackgroundSettings,
              tooltip: 'Change background',
              child: Icon(Icons.format_paint),
              backgroundColor: Theme.of(context).cardColor,
            ),
        ]),
      ),
    );
  }

  Widget _buildToolLayout(List<Widget> tools) {
    if (widget.compact) {
      return Row(mainAxisSize: MainAxisSize.min, children: tools);
    }
    return ListView(
      shrinkWrap: true,
      scrollDirection: Axis.horizontal,
      children: tools,
    );
  }

  void saveDeviceTable() => widget.onNewDeviceMap!(widget.deviceMap);

  void showCustomDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierLabel: "Barrier",
      barrierDismissible: true,
      pageBuilder: (_, __, ___) {
        return ToolSettingDialog(
          width: widget.getWidth!(getTool()),
          minWidth: widget.getMinWidth!(getTool()),
          maxWidth: widget.getMaxWidth!(getTool()),
          widthDivisions: widget.getWidthDivisions!(getTool()),
          color: widget.getColor!(getTool()),
          onColorChange: (newColor) =>
              widget.onColorChange!(newColor, getTool()),
          onWidthChange: (newWidth) =>
              widget.onWidthChange!(newWidth, getTool()),
          enableColor: getTool() != EditingTool.ERASER,
        );
      },
    );
  }

  Widget getInkwellButton(
    EditingTool tool,
    Widget icon, {
    bool enableSettings = false,
    bool usePrimaryColor = false,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = getTool() == tool;
    final selectedBackground = usePrimaryColor
        ? theme.floatingActionButtonTheme.backgroundColor ??
              (theme.useMaterial3 ? colors.primaryContainer : colors.secondary)
        : widget.getColor!(tool) as Color;
    final selectedForeground =
        theme.floatingActionButtonTheme.foregroundColor ??
        (theme.useMaterial3 ? colors.onPrimaryContainer : colors.onSecondary);

    void selectTool() {
      if (enableSettings && getTool() == tool) {
        showCustomDialog(context);
      } else {
        setState(() => setTool(tool));
        saveDeviceTable();
      }
    }

    if (widget.compact) {
      final foreground = selected ? selectedForeground : colors.onSurface;
      return Material(
        color: selected ? selectedBackground : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? colors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: IconButton(
          onPressed: selectTool,
          tooltip: switch (tool) {
            EditingTool.STYLUS => S.of(context).pen,
            EditingTool.HIGHLIGHT => S.of(context).highlighter,
            EditingTool.ERASER => S.of(context).eraser,
            EditingTool.MOVE => S.of(context).move,
            _ => tool.name[0] + tool.name.substring(1).toLowerCase(),
          },
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          color: foreground,
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: foreground,
          ),
          isSelected: selected,
          icon: icon,
        ),
      );
    }
    return InkWell(
      onLongPress: () {},
      child: FloatingActionButton(
        heroTag: tool,
        onPressed: selectTool,
        child: icon,
        elevation: 6,
        backgroundColor: selected ? selectedBackground : theme.cardColor,
      ),
    );
  }

  void initializeTool() {
    if (getTool() == null) {
      setTool(EditingTool.STYLUS);
    }
  }

  void setTool(EditingTool tool) {
    PointerDeviceKind? device = currentDevice;
    if (_usesUnifiedTouchTool) {
      widget.deviceMap![PointerDeviceKind.touch] = tool;
      widget.deviceMap![PointerDeviceKind.stylus] = tool;
      return;
    }
    widget.deviceMap![device] = tool;
  }

  EditingTool? getTool() {
    PointerDeviceKind? device = currentDevice;
    if (_usesUnifiedTouchTool) {
      device = PointerDeviceKind.stylus;
    }
    return widget.deviceMap![device];
  }

  bool get _usesUnifiedTouchTool {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
