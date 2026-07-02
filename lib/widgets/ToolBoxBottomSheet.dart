import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppPage.dart';

class ToolBoxBottomSheet extends StatefulWidget {
  final EditingTool? tool;
  final Function(EditingTool)? onToolChange;
  final Function(XppBackground)? onBackgroundChange;

  const ToolBoxBottomSheet({
    Key? key,
    this.tool,
    this.onToolChange,
    this.onBackgroundChange,
  }) : super(key: key);

  @override
  _ToolBoxBottomSheetState createState() => _ToolBoxBottomSheetState();
}

class _ToolBoxBottomSheetState extends State<ToolBoxBottomSheet> {
  double _height = 320;

  @override
  Widget build(BuildContext context) {
    return BottomSheet(
      onClosing: () {
        Navigator.of(context).pop();
      },
      elevation: 16,
      //        backgroundColor: Theme.of(context).backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (context) => Container(
        height: _height,
        child: ListView(
          padding: const EdgeInsets.all(8),
          shrinkWrap: true,
          children: [
            Text(
              S.of(context).pageBackground,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Container(
              height: 128,
              child: ListView(
                shrinkWrap: true,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: GestureDetector(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Card(
                            child: SizedBox(
                              width: 96,
                              height: 96,
                              child: XppBackground.none.render(),
                            ),
                          ),
                          Text('None'),
                        ],
                      ),
                      onTap: () =>
                          widget.onBackgroundChange!(XppBackground.none),
                    ),
                  ),
                  AspectRatio(
                    aspectRatio: 1,
                    child: GestureDetector(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Card(
                            child: XppBackgroundSolidPlain(
                              size: XppPageSize(width: 96, height: 96),
                              color: Theme.of(context).colorScheme.secondary,
                            ).render(),
                          ),
                          Text(S.of(context).color),
                        ],
                      ),
                      onTap: () async => _changeBackgroundWithColor(
                        (color) => XppBackgroundSolidPlain(color: color),
                      ),
                    ),
                  ),
                  AspectRatio(
                    aspectRatio: 1,
                    child: GestureDetector(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Card(
                            child: XppBackgroundSolidLined(
                              size: XppPageSize(width: 96, height: 96),
                            ).render(),
                          ),
                          Text(S.of(context).lined),
                        ],
                      ),
                      onTap: () async => _changeBackgroundWithColor(
                        (color) => XppBackgroundSolidLined(color: color),
                      ),
                    ),
                  ),
                  AspectRatio(
                    aspectRatio: 1,
                    child: GestureDetector(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Card(
                            child: XppBackgroundSolidRuled(
                              size: XppPageSize(width: 96, height: 96),
                            ).render(),
                          ),
                          Text(S.of(context).ruled),
                        ],
                      ),
                      onTap: () async => _changeBackgroundWithColor(
                        (color) => XppBackgroundSolidRuled(color: color),
                      ),
                    ),
                  ),
                  AspectRatio(
                    aspectRatio: 1,
                    child: GestureDetector(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Card(
                            child: XppBackgroundSolidGraph(
                              size: XppPageSize(width: 96, height: 96),
                            ).render(),
                          ),
                          Text(S.of(context).graph),
                        ],
                      ),
                      onTap: () async => _changeBackgroundWithColor(
                        (color) => XppBackgroundSolidGraph(color: color),
                      ),
                    ),
                  ),
                  AspectRatio(
                    aspectRatio: 1,
                    child: GestureDetector(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Card(
                            child: XppBackgroundSolidDot(
                              size: XppPageSize(width: 96, height: 96),
                            ).render(),
                          ),
                          Text(S.of(context).dotted),
                        ],
                      ),
                      onTap: () async => _changeBackgroundWithColor(
                        (color) => XppBackgroundSolidDot(color: color),
                      ),
                    ),
                  ),
                  AspectRatio(
                    aspectRatio: 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Card(child: XppBackground.none.render()),
                        Text(S.of(context).pdf + S.of(context).notImplemented),
                      ],
                    ),
                  ),
                  AspectRatio(
                    aspectRatio: 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Card(child: XppBackground.none.render()),
                        Text(
                          S.of(context).image + S.of(context).notImplemented,
                        ),
                      ],
                    ),
                  ),
                ],
                scrollDirection: Axis.horizontal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Color?> pickBackgroundColor() async => await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      content: MaterialPicker(
        pickerColor: Colors.white,
        onColorChanged: (newColor) => Navigator.of(context).pop(newColor),
      ),
    ),
  );

  Future<void> _changeBackgroundWithColor(
    XppBackground Function(Color color) createBackground,
  ) async {
    final color = await pickBackgroundColor();
    if (color == null) return;
    widget.onBackgroundChange!(createBackground(color));
  }
}

enum EditingTool {
  STYLUS,
  HIGHLIGHT,
  TEXT,
  LATEX,
  LASER,
  IMAGE,
  MOVE,
  SELECT,
  ERASER,
  WHITEOUT,
}
