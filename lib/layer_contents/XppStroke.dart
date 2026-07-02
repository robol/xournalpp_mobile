import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/src/HexColor.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPageContentWidget.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

abstract class XppStroke extends XppContent {
  static const int _renderChunkPointCount = 128;

  XppStroke({
    this.tool = XppStrokeTool.PEN,
    this.points,
    this.color,
    this.editingTool,
  });

  XppStrokeTool tool;
  List<XppStrokePoint>? points;
  Color? color;
  EditingTool? editingTool;
  XppStrokeBounds? _cachedBounds;

  @override
  Offset getOffset() {
    if (points!.isEmpty) return Offset(0, 0);
    return _strokeBounds.rect.topLeft;
  }

  Offset get bottomRight {
    if (points!.isEmpty) return Offset(0, 0);
    return _strokeBounds.rect.bottomRight;
  }

  @override
  Rect? get eraseBounds {
    if (points!.isEmpty) return null;
    return _strokeBounds.rect;
  }

  @override
  XppPageContentWidget render({
    void Function(XppContent newContent)? onReplace,
    void Function(PointerDownEvent event)? onPointerDown,
    bool selectionMode = false,
    bool selected = false,
    VoidCallback? onSelect,
  }) {
    if (points!.isEmpty) {
      return XppPageContentWidget(child: (Container()));
    }
    Color? colorToUse = color;
    if (tool == XppStrokeTool.ERASER) colorToUse = Colors.white;
    if (tool == XppStrokeTool.HIGHLIGHTER) {
      colorToUse = color!.withValues(alpha: .5);
    }
    final strokeBounds = _strokeBounds;
    final chunks = _chunkPoints(points!);
    return XppPageContentWidget(
      child: SizedBox(
        width: strokeBounds.rect.width,
        height: strokeBounds.rect.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: chunks.map((chunk) {
            final bounds = XppStrokeBounds.fromPoints(chunk);
            final localRect = bounds.rect.shift(-strokeBounds.rect.topLeft);
            return Positioned.fromRect(
              rect: localRect,
              child: RepaintBoundary(
                child: CustomPaint(
                  foregroundPainter: XppStrokePainter(
                    points: chunk,
                    color: colorToUse,
                    topLeft: bounds.rect.topLeft,
                    smoothPressure: tool == XppStrokeTool.PEN,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      onPointerDown: onPointerDown,
      selectionMode: selectionMode,
      selected: selected,
      onSelect: onSelect,
      tool: EditingTool.STYLUS,
    );
  }

  List<List<XppStrokePoint>> _chunkPoints(List<XppStrokePoint> points) {
    if (points.length <= _renderChunkPointCount) return [points];

    final chunks = <List<XppStrokePoint>>[];
    for (
      int start = 0;
      start < points.length;
      start += _renderChunkPointCount
    ) {
      final end = (start + _renderChunkPointCount).clamp(0, points.length);
      final chunkStart = start == 0 ? start : start - 1;
      chunks.add(points.sublist(chunkStart, end));
    }
    return chunks;
  }

  @override
  XmlElement toXmlElement() {
    late String toolString;
    switch (tool) {
      case XppStrokeTool.PEN:
        toolString = 'pen';
        break;
      case XppStrokeTool.HIGHLIGHTER:
        toolString = 'highlighter';
        break;
      case XppStrokeTool.ERASER:
        toolString = 'eraser';
        break;
    }
    XmlElement node = XmlElement(
      XmlName('stroke'),
      [
        XmlAttribute(XmlName('tool'), toolString),
        XmlAttribute(XmlName('color'), color!.toHexTriplet()),
        XmlAttribute(
          XmlName('width'),
          points!.map((e) => e.width.toString()).join(' '),
        ),
      ],
      [
        XmlText(
          points!.map((e) => e.x.toString() + ' ' + e.y.toString()).join(' '),
        ),
      ],
    );
    return node;
  }

  @override
  XppContentEraseData eraseWhere({Offset? coordinates, double? radius}) {
    if (coordinates == null || radius == null || points!.isEmpty) {
      return XppContentEraseData();
    }
    if (!_mightErase(coordinates: coordinates, radius: radius)) {
      return XppContentEraseData();
    }

    List<XppStroke> newStrokes = [];
    List<XppStrokePoint> currentSegment = [];
    bool removedAnyPoint = false;

    for (final point in points!) {
      if (_shouldRemovePoint(point, coordinates, radius)) {
        removedAnyPoint = true;
        if (currentSegment.isNotEmpty) {
          newStrokes.add(newStroke(color: color, points: currentSegment));
          currentSegment = [];
        }
        continue;
      }

      currentSegment.add(point);
    }

    if (!removedAnyPoint) return XppContentEraseData();

    if (currentSegment.isNotEmpty) {
      newStrokes.add(newStroke(color: color, points: currentSegment));
    }

    return XppContentEraseData(
      affected: true,
      delete: newStrokes.isEmpty,
      newContent: newStrokes,
    );
  }

  @override
  bool inRegion({Offset? topLeft, Offset? bottomRight}) {
    // TODO: implement shouldSelectAt
    throw UnimplementedError();
  }

  @override
  bool shouldSelectAt({Offset? coordinates, EditingTool? tool}) {
    // TODO: implement shouldSelectAt
    throw UnimplementedError();
  }

  XppStroke newStroke({Color? color, List<XppStrokePoint>? points});

  @override
  XppContent translatedBy(Offset delta) => newStroke(
    color: color,
    points: points
        ?.map(
          (point) => XppStrokePoint(
            x: point.x == null ? null : point.x! + delta.dx,
            y: point.y == null ? null : point.y! + delta.dy,
            width: point.width,
          ),
        )
        .toList(),
  );

  XppStrokeBounds get _strokeBounds {
    return _cachedBounds ??= XppStrokeBounds.fromPoints(points!);
  }

  bool _mightErase({required Offset coordinates, required double radius}) {
    return _strokeBounds.rect.inflate(radius / 2).contains(coordinates);
  }

  bool _shouldRemovePoint(
    XppStrokePoint element,
    Offset coordinates,
    double radius,
  ) {
    return ((element.x! - coordinates.dx).abs() <
            (element.width! + radius) / 2 &&
        (element.y! - coordinates.dy).abs() < (element.width! + radius) / 2);
  }

  static XppStroke byTool({
    required XppStrokeTool tool,
    List<XppStrokePoint>? points,
    Color? color,
  }) {
    XppStroke? stroke;
    switch (tool) {
      case XppStrokeTool.PEN:
        stroke = XppStrokePen(color: color, points: points);
        break;
      case XppStrokeTool.HIGHLIGHTER:
        stroke = XppStrokeHighlight(color: color, points: points);
        break;
      case XppStrokeTool.ERASER:
        stroke = XppStrokeEraser(color: color, points: points);
        break;
    }
    return stroke;
  }
}

class XppStrokePen extends XppStroke {
  XppStrokeTool tool = XppStrokeTool.PEN;
  List<XppStrokePoint>? points;
  Color? color;

  EditingTool? editingTool;
  XppStrokePen({this.points, this.color})
    : super(
        points: points,
        color: color,
        tool: XppStrokeTool.PEN,
        editingTool: EditingTool.STYLUS,
      );

  @override
  XppStroke newStroke({Color? color, List<XppStrokePoint>? points}) {
    return XppStrokePen(points: points, color: color);
  }
}

class XppStrokeEraser extends XppStroke {
  XppStrokeTool tool = XppStrokeTool.ERASER;
  List<XppStrokePoint>? points;
  Color? color;

  EditingTool? editingTool;
  XppStrokeEraser({this.points, this.color})
    : super(
        points: points,
        color: color,
        tool: XppStrokeTool.ERASER,
        editingTool: EditingTool.ERASER,
      );

  @override
  XppStroke newStroke({Color? color, List<XppStrokePoint>? points}) {
    return XppStrokeEraser(points: points, color: color);
  }
}

class XppStrokeHighlight extends XppStroke {
  XppStrokeTool tool = XppStrokeTool.HIGHLIGHTER;
  List<XppStrokePoint>? points;
  Color? color;

  EditingTool? editingTool;
  XppStrokeHighlight({this.points, this.color})
    : super(
        points: points,
        color: color,
        tool: XppStrokeTool.HIGHLIGHTER,
        editingTool: EditingTool.HIGHLIGHT,
      );

  @override
  XppStroke newStroke({Color? color, List<XppStrokePoint>? points}) {
    return XppStrokeHighlight(points: points, color: color);
  }
}

class XppStrokePainter extends CustomPainter {
  final List<XppStrokePoint>? points;
  final Color? color;
  final Offset? topLeft;
  final bool? smoothPressure;

  XppStrokePainter({
    this.points,
    this.color,
    this.topLeft,
    this.smoothPressure,
    Listenable? repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (points!.isEmpty) return;
    if (points!.length == 1) {
      var paint = Paint()
        ..color = color!
        ..strokeWidth = points![0].width ?? 5
        ..style = PaintingStyle.fill
        ..strokeCap = StrokeCap.round;

      Offset offset = points![0].offset;
      canvas.drawCircle(
        Offset(offset.dx - topLeft!.dx, offset.dy - topLeft!.dy),
        paint.strokeWidth / 2,
        paint,
      );
    }
    if (smoothPressure!) {
      for (int i = 1; i < points!.length; i++) {
        var paint = Paint()
          ..color = color!
          ..strokeWidth = points![i].width ?? 5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        final start = points![i - 1].offset;
        final end = points![i].offset;
        canvas.drawLine(
          Offset(start.dx - topLeft!.dx, start.dy - topLeft!.dy),
          Offset(end.dx - topLeft!.dx, end.dy - topLeft!.dy),
          paint,
        );
      }
    } else {
      double width = 0;

      var path = Path();
      path.moveTo(
        points![0].offset.dx - topLeft!.dx,
        points![0].offset.dy - topLeft!.dy,
      );
      for (int i = 1; i < points!.length; i++) {
        Offset offset = points![i].offset;
        path.lineTo(offset.dx - topLeft!.dx, offset.dy - topLeft!.dy);
        width += points![i].width!;
      }
      width /= points!.length;
      var paint = Paint()
        ..color = color!
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant XppStrokePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.color != color ||
        oldDelegate.topLeft != topLeft ||
        oldDelegate.smoothPressure != smoothPressure;
  }
}

enum XppStrokeTool { PEN, HIGHLIGHTER, ERASER }

class XppStrokePoint {
  final double? x;
  final double? y;
  final double? width;

  XppStrokePoint({this.x, this.y, this.width});

  Offset get offset => Offset(x!, y!);
}

class XppStrokeBounds {
  final Rect rect;

  XppStrokeBounds._(this.rect);

  factory XppStrokeBounds.fromPoints(List<XppStrokePoint> points) {
    final firstPoint = points.first;
    double left = firstPoint.x!;
    double top = firstPoint.y!;
    double right = firstPoint.x!;
    double bottom = firstPoint.y!;
    double maxWidth = firstPoint.width ?? 1;

    for (final point in points) {
      final x = point.x!;
      final y = point.y!;
      final width = point.width ?? 1;

      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
      if (width > maxWidth) maxWidth = width;
    }

    final padding = (maxWidth / 2) + 2;
    return XppStrokeBounds._(
      Rect.fromLTRB(left, top, right, bottom).inflate(padding),
    );
  }
}
