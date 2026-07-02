import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

import 'XppPageContentWidget.dart';

class XppLayer {
  XppLayer({this.content});

  List<XppContent?>? content;

  static XppLayer empty() => XppLayer(content: []);

  XmlElement toXmlElement() => XmlElement(
    XmlName('layer'),
    const [],
    content!.map((e) => e!.toXmlElement()),
  );
}

abstract class XppContent {
  Offset? getOffset();

  Rect? get eraseBounds => null;

  Rect? get selectionBounds => eraseBounds;

  XppPageContentWidget render({
    void Function(XppContent newContent)? onReplace,
    void Function(PointerDownEvent event)? onPointerDown,
    bool selectionMode = false,
    bool selected = false,
    VoidCallback? onSelect,
  });

  XmlElement toXmlElement();

  bool shouldSelectAt({Offset? coordinates, EditingTool? tool});

  bool inRegion({Offset? topLeft, Offset? bottomRight});

  /// return [true] in case it should be fully deleted
  XppContentEraseData eraseWhere({Offset? coordinates, double? radius}) =>
      XppContentEraseData();
}

class XppContentEraseData {
  final bool affected;
  final bool delete;
  final List<XppContent> newContent;

  XppContentEraseData({
    this.affected = false,
    this.delete = false,
    this.newContent = const [],
  });
}
