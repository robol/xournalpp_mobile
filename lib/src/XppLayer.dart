import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import 'XppPageContentWidget.dart';

class XppLayer {
  XppLayer({List<XppContent?>? content}) {
    this.content = content;
  }

  int _revision = 0;
  int get revision => _revision;
  List<XppContent?>? _content;
  List<XppContent?>? get content => _content;
  set content(List<XppContent?>? value) {
    _content = value == null ? null : _LayerContents(value, () => _revision++);
    _revision++;
  }

  static XppLayer empty() => XppLayer(content: []);

  XmlElement toXmlElement() => XmlElement(
    XmlName.parts('layer'),
    const [],
    content!.map((e) => e!.toXmlElement()),
  );
}

abstract class XppContent {
  Offset? getOffset();

  Rect? get eraseBounds => null;

  Rect? get selectionBounds => eraseBounds;

  XppContent translatedBy(Offset delta);

  XppPageContentWidget render({
    void Function(XppContent newContent)? onReplace,
    void Function(PointerDownEvent event)? onPointerDown,
    bool selectionMode = false,
    bool selected = false,
    VoidCallback? onSelect,
  });

  XmlElement toXmlElement();

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

// Own the list so mutations through an external alias cannot bypass revision
// tracking. Content geometry is immutable by convention: replace edited items.
class _LayerContents extends ListBase<XppContent?> {
  _LayerContents(List<XppContent?> values, this.changed)
    : _values = List<XppContent?>.of(values);
  final List<XppContent?> _values;
  final VoidCallback changed;
  @override
  int get length => _values.length;
  @override
  set length(int value) {
    if (value == length) return;
    _values.length = value;
    changed();
  }

  @override
  XppContent? operator [](int index) => _values[index];
  @override
  void operator []=(int index, XppContent? value) {
    if (identical(_values[index], value)) return;
    _values[index] = value;
    changed();
  }
}
