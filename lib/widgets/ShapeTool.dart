import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';

enum ShapeKind { line, circle, square }

class ShapeSettings {
  const ShapeSettings({
    this.kind = ShapeKind.line,
    this.outline = Colors.black,
    this.width = 2,
  });
  final ShapeKind kind;
  final Color outline;
  final double width;

  ShapeSettings copyWith({ShapeKind? kind, Color? outline, double? width}) =>
      ShapeSettings(
        kind: kind ?? this.kind,
        outline: outline ?? this.outline,
        width: width ?? this.width,
      );
}

List<XppStroke> shapeStrokes(Offset start, Offset end, ShapeSettings settings) {
  final delta = end - start;
  if (delta.distance < 2) return [];
  final List<Offset> offsets;
  if (settings.kind == ShapeKind.line) {
    offsets = [start, end];
  } else {
    final side = math.min(delta.dx.abs(), delta.dy.abs());
    if (side < 2) return [];
    final other = start + Offset(delta.dx.sign * side, delta.dy.sign * side);
    final rect = Rect.fromPoints(start, other);
    if (settings.kind == ShapeKind.square) {
      offsets = [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
        rect.topLeft,
      ];
    } else {
      offsets = List.generate(65, (i) {
        final angle = 2 * math.pi * i / 64;
        return rect.center +
            Offset(math.cos(angle) * side / 2, math.sin(angle) * side / 2);
      });
    }
  }
  // Densely sample straight segments so the existing point-based eraser works.
  final sampled = <Offset>[offsets.first];
  for (var i = 1; i < offsets.length; i++) {
    final a = offsets[i - 1], b = offsets[i];
    final count = math.max(1, ((b - a).distance / 2).ceil()).clamp(1, 4096);
    for (var j = 1; j <= count; j++) sampled.add(Offset.lerp(a, b, j / count)!);
  }
  List<XppStrokePoint> points(double width) => sampled
      .map((p) => XppStrokePoint(x: p.dx, y: p.dy, width: width))
      .toList();
  return [
    XppStrokePen(points: points(settings.width), color: settings.outline),
  ];
}

class ShapeSettingsDialog extends StatefulWidget {
  const ShapeSettingsDialog({
    super.key,
    required this.settings,
    required this.onChanged,
  });
  final ShapeSettings settings;
  final ValueChanged<ShapeSettings> onChanged;
  @override
  State<ShapeSettingsDialog> createState() => _ShapeSettingsDialogState();
}

class _ShapeSettingsDialogState extends State<ShapeSettingsDialog> {
  late ShapeSettings settings = widget.settings;
  void update(ShapeSettings value) {
    setState(() => settings = value);
    widget.onChanged(value);
  }

  Future<void> pickColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).shapeOutlineColor),
        content: SingleChildScrollView(
          child: MaterialPicker(
            pickerColor: settings.outline,
            onColorChanged: (color) => Navigator.pop(context, color),
          ),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    update(settings.copyWith(outline: picked));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.shapes),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<ShapeKind>(
              segments: [
                ButtonSegment(value: ShapeKind.line, label: Text(s.shapeLine)),
                ButtonSegment(
                  value: ShapeKind.circle,
                  label: Text(s.shapeCircle),
                ),
                ButtonSegment(
                  value: ShapeKind.square,
                  label: Text(s.shapeSquare),
                ),
              ],
              selected: {settings.kind},
              onSelectionChanged: (value) =>
                  update(settings.copyWith(kind: value.first)),
            ),
            Text(s.strokeWidth + settings.width.toStringAsFixed(1)),
            Slider(
              value: settings.width,
              min: 0.5,
              max: 10,
              onChanged: (v) => update(settings.copyWith(width: v)),
            ),
            ListTile(
              title: Text(s.shapeOutlineColor),
              trailing: CircleAvatar(backgroundColor: settings.outline),
              onTap: pickColor,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.close),
        ),
      ],
    );
  }
}
