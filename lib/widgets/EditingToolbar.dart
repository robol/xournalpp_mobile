import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
      height: 64,
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      child: MouseRegion(
        onHover: (event) {
          currentDevice = event.kind;
        },
        child: ListView(
          children: [
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
            getInkwellButton(
              EditingTool.IMAGE,
              Icon(Icons.add_photo_alternate),
              usePrimaryColor: true,
            ),
            getInkwellButton(
              EditingTool.SELECT,
              Icon(Icons.tab_unselected),
              usePrimaryColor: true,
            ),
          ],
          shrinkWrap: true,
          scrollDirection: Axis.horizontal,
        ),
      ),
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

  InkWell getInkwellButton(
    EditingTool tool,
    Widget icon, {
    bool enableSettings = false,
    bool usePrimaryColor = false,
  }) {
    return InkWell(
      onLongPress: () {},
      child: FloatingActionButton(
        heroTag: tool,
        onPressed: () {
          // if tool is selected, then show the settings
          if (enableSettings && getTool() == tool) {
            showCustomDialog(context);
          } else {
            setState(() => setTool(tool));
            saveDeviceTable();
          }
        },
        child: icon,
        elevation: 6,
        backgroundColor: getTool() == tool
            ? (!usePrimaryColor ? widget.getColor!(tool) : null)
            : Theme.of(context).cardColor,
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
