import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:xournalpp/src/TransparentImage.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPageContentWidget.dart';

class XppImage extends XppContent {
  Offset? topLeft = Offset(0, 0);
  Offset? bottomRight = Offset(0, 0);

  final Uint8List? data;

  XppImage({this.data, this.topLeft, this.bottomRight});

  static Future<XppImage> open({required Offset topLeft}) async {
    XppPickedFile image = await XppPickedFile.importFromStorage(
      type: XppFilePickType.image,
    );

    /// rendering the [Uint8List] into an image to determinate the height and width
    MemoryImage memoryImage = MemoryImage(image.toUint8List());
    Completer completer = new Completer();
    memoryImage
        .resolve(ImageConfiguration())
        .addListener(
          ImageStreamListener(
            (ImageInfo info, bool _) => completer.complete(info.image),
          ),
        );
    Image renderedImage = await (completer.future as FutureOr<Image>);
    Offset bottomRight = Offset(
      topLeft.dx + renderedImage.width!,
      topLeft.dy + renderedImage.height!,
    );
    return XppImage(
      data: image.toUint8List(),
      topLeft: topLeft,
      bottomRight: bottomRight,
    );
  }

  @override
  XppPageContentWidget render({
    void Function(XppContent newContent)? onReplace,
    void Function(PointerDownEvent event)? onPointerDown,
    bool selectionMode = false,
    bool selected = false,
    VoidCallback? onSelect,
  }) {
    return XppPageContentWidget(
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(),
          FadeInImage(
            image: MemoryImage(data!),
            placeholder: MemoryImage(kTransparentImage),
            width: bottomRight!.dx - topLeft!.dx,
            height: bottomRight!.dy - topLeft!.dy,
          ),
        ],
      ),
      onPointerDown: onPointerDown,
      selectionMode: selectionMode,
      selected: selected,
      onSelect: onSelect,
    );
  }

  @override
  Offset? getOffset() => topLeft;

  @override
  Rect? get selectionBounds {
    if (topLeft == null || bottomRight == null) return null;
    return Rect.fromPoints(topLeft!, bottomRight!);
  }

  @override
  XppContent translatedBy(Offset delta) => XppImage(
    data: data,
    topLeft: topLeft == null ? null : topLeft! + delta,
    bottomRight: bottomRight == null ? null : bottomRight! + delta,
  );

  @override
  XmlElement toXmlElement() => XmlElement(
    XmlName.parts('image'),
    [
      XmlAttribute(XmlName.parts('left'), topLeft!.dx.toString()),
      XmlAttribute(XmlName.parts('right'), bottomRight!.dx.toString()),
      XmlAttribute(XmlName.parts('top'), topLeft!.dy.toString()),
      XmlAttribute(XmlName.parts('bottom'), bottomRight!.dy.toString()),
    ],
    [XmlText(base64Encode(data!))],
  );
}
