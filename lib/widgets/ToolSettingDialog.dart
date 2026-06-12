import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:xournalpp/generated/l10n.dart';

class ToolSettingDialog extends StatefulWidget {
  double width;
  Function(Color)? onColorChange;
  Function(double newWidth)? onWidthChange;
  Object? S;
  Color color;
  FloatingActionButton? pickerButton;

  ToolSettingDialog({
    Key? key,
    required this.width,
    required this.color,
    this.onColorChange,
    this.onWidthChange,
    this.S,
  }) : super(key: key);

  @override
  _ToolSettingDialogState createState() => _ToolSettingDialogState();
}

class _ToolSettingDialogState extends State<ToolSettingDialog> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: contentBox(context),
    );
  }

  contentBox(context) {
    return Stack(
      children: <Widget>[
        Container(
          padding: EdgeInsets.only(left: 20, top: 40, right: 20, bottom: 20),
          margin: EdgeInsets.only(top: 45),
          decoration: BoxDecoration(
            shape: BoxShape.rectangle,
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black,
                offset: Offset(0, 10),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                child: Text(
                  //todo: limit to one decimal place
                  S.of(context).strokeWidth + ' ${this.widget.width}',
                  style: TextStyle(color: Colors.black),
                ),
              ),
              Container(
                height: 64,
                child: Slider(
                  activeColor: Theme.of(context).colorScheme.secondary,
                  inactiveColor: Theme.of(context).colorScheme.onPrimary,
                  value: this.widget.width,
                  min: 0.1,
                  max: 30,
                  onChanged: (newWidth) {
                    setState(() {
                      this.widget.width = newWidth;
                    });
                    widget.onWidthChange!(newWidth);
                  },
                ),
              ),
              Container(
                child: Text(
                  S.of(context).selectColor,
                  style: TextStyle(color: Colors.black),
                ),
              ),
              Container(
                height: 64,
                margin: EdgeInsets.only(
                  left: 0.0,
                  top: 5.0,
                  right: 0.0,
                  bottom: 0.0,
                ),
                child: ListView(
                  // This next line does the trick.
                  scrollDirection: Axis.horizontal,
                  children: <Widget>[
                    getColorFab("Colorfab1", Colors.black),
                    getColorFab("Colorfab2", Colors.grey),
                    getColorFab("Colorfab3", Color(0xFF336699)),
                    getColorFab("Colorfab4", Colors.white),
                    getColorFab("Colorfab5", Color(0xFFe67300)),
                    getColorFab(
                      "Colorfab6",
                      Color(0xFFB30000),
                    ), //for whatever reason, this is not rgba but argb
                    getColorFab("Colorfab7", Color(0xFF009933)),
                    getColorFab("Colorfab8", Color(0xFF000099)),
                    getColorPicker(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  FloatingActionButton getColorPicker() {
    var picker = FloatingActionButton(
      heroTag: MaterialPicker,
      backgroundColor: widget.color,
      onPressed: () {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(S.of(context).selectColor),
            content: SingleChildScrollView(
              child: MaterialPicker(
                pickerColor: widget.color,
                onColorChanged: (color) {
                  setNewColor(color);
                },
                enableLabel: true, // only on portrait mode
              ),
            ),
          ),
        );
      },
      child: Icon(Icons.color_lens),
      tooltip: S.of(context).color,
      elevation: 6,
      //backgroundColor: widget.color,
    );

    return picker;
  }

  void setNewColor(Color color) {
    widget.onColorChange!(color);
    //widget.pickerButton!.backgroundColor = color;
    widget.color = color;
    Navigator.of(context).pop();
  }

  Container getColorFab(String tag, Color color) {
    return Container(
      margin: EdgeInsets.only(left: 5.0, top: 5.0, right: 5.0, bottom: 5.0),
      child: FloatingActionButton(
        heroTag: tag,
        onPressed: () {
          setNewColor(color);
        },
        elevation: 6,
        backgroundColor: color,
      ),
    );
  }
}
