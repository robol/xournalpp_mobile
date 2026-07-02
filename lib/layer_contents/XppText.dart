import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/src/HexColor.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPageContentWidget.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

class XppText extends XppContent {
  static const String _defaultFontFamily = 'Sans';
  static const double _defaultSize = 18;

  final Color? color;
  final double? size;
  final String? text;
  final Offset? offset;
  final String? fontFamily;

  XppText({this.size, this.offset, this.fontFamily, this.color, this.text});

  static Future<XppText> edit({
    required BuildContext context,
    String text = '',
    Offset? offset,
    Color? color,
    double? size,
    String? fontFamily,
  }) async {
    final textController = TextEditingController(text: text);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enter text'),
        content: TextField(
          controller: textController,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Text',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Okay'),
          ),
        ],
      ),
    );
    final enteredText = textController.text;
    textController.dispose();
    if (result != true) throw UnsupportedError('Aborted.');
    return XppText(
      text: enteredText,
      offset: offset,
      color: color,
      size: size ?? _defaultSize,
      fontFamily: fontFamily ?? _defaultFontFamily,
    );
  }

  @override
  Offset? getOffset() => offset;

  @override
  XppPageContentWidget render({
    void Function(XppContent newContent)? onReplace,
    void Function(PointerDownEvent event)? onPointerDown,
  }) {
    return XppPageContentWidget(
      child: Text(
        text ?? '',
        style: TextStyle(
          color: color ?? Colors.black,
          fontSize: size ?? _defaultSize,
          fontFamily: fontFamily,
        ),
      ),
      onSelected: (context) {
        if (onReplace == null) return;
        XppText.edit(
          context: context,
          text: text ?? '',
          offset: offset,
          color: color,
          size: size,
          fontFamily: fontFamily,
        ).then(onReplace).catchError((_) {});
      },
      onPointerDown: onPointerDown,
      tool: EditingTool.TEXT,
    );
  }

  @override
  XmlElement toXmlElement() => XmlElement(
    XmlName('text'),
    [
      XmlAttribute(XmlName('font'), fontFamily ?? _defaultFontFamily),
      XmlAttribute(XmlName('size'), size.toString()),
      XmlAttribute(XmlName('x'), offset!.dx.toString()),
      XmlAttribute(XmlName('y'), offset!.dy.toString()),
      XmlAttribute(XmlName('color'), (color ?? Colors.black).toHexTriplet()),
    ],
    [XmlText(encodeText(text ?? ''))],
  );

  static String encodeText(String text) {
    return text
        .replaceAll(r'&', r'&amp;')
        .replaceAll(r'<', r'&lt;')
        .replaceAll(r'>', r'&gt;');
  }

  @override
  bool inRegion({Offset? topLeft, Offset? bottomRight}) {
    // TODO: implement inRegion
    throw UnimplementedError();
  }

  @override
  bool shouldSelectAt({Offset? coordinates, EditingTool? tool}) {
    // TODO: implement shouldSelectAt
    throw UnimplementedError();
  }
}
