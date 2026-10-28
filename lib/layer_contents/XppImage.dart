import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:xournalpp/src/RasterImageCache.dart';
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

    final buffer = await ui.ImmutableBuffer.fromUint8List(image.toUint8List());
    late Offset bottomRight;
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        bottomRight =
            topLeft +
            Offset(descriptor.width.toDouble(), descriptor.height.toDouble());
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
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
      child: Builder(
        builder: (context) {
          final width = bottomRight!.dx - topLeft!.dx;
          final height = bottomRight!.dy - topLeft!.dy;
          // The page supplies its committed display scale, not each pinch tick.
          final scale = ImageRasterScale.of(context);
          final target = boundedRasterSize(width * scale, height * scale);
          return Image(
            image: ResizeImage(
              MemoryImage(data!),
              width: target.width.toInt(),
              height: target.height.toInt(),
              policy: ResizeImagePolicy.fit,
            ),
            width: width,
            height: height,
            fit: BoxFit.contain,
            frameBuilder: (context, child, frame, synchronous) =>
                synchronous || frame != null
                ? child
                : SizedBox(width: width, height: height),
            errorBuilder: (context, error, stack) => SizedBox(
              width: width,
              height: height,
              child: const Icon(Icons.broken_image),
            ),
          );
        },
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

/// Pixel density committed by the editor, kept stable during a pinch.
class ImageRasterScale extends InheritedWidget {
  const ImageRasterScale({
    super.key,
    required this.scale,
    required super.child,
  });
  final double scale;
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ImageRasterScale>()?.scale ??
      MediaQuery.devicePixelRatioOf(context);
  @override
  bool updateShouldNotify(ImageRasterScale oldWidget) =>
      scale != oldWidget.scale;
}
