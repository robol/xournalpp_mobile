import 'dart:ui';
import 'XppLayer.dart';

/// Page-coordinate broad phase, preserving document order in callers. Very
/// large bounds use a separate list instead of filling unbounded grid cells.
class ContentSpatialIndex {
  static const _cellSize = 96.0;
  final _cells = <(int, int), Set<XppContent>>{};
  final _large = <XppContent>{};
  final _bounds = <XppContent, Rect>{};
  ContentSpatialIndex(Iterable<XppContent?> contents) {
    for (final content in contents) {
      final bounds = content?.selectionBounds;
      if (content == null || bounds == null || bounds.isEmpty) continue;
      _bounds[content] = bounds;
      final cells = _range(bounds);
      if ((cells.$3 - cells.$1 + 1) * (cells.$4 - cells.$2 + 1) > 256) {
        _large.add(content);
      } else {
        for (var x = cells.$1; x <= cells.$3; x++) {
          for (var y = cells.$2; y <= cells.$4; y++) {
            (_cells[(x, y)] ??= {}).add(content);
          }
        }
      }
    }
  }
  Set<XppContent> query(Rect rect) {
    final range = _range(rect);
    final candidates = <XppContent>{..._large};
    if ((range.$3 - range.$1 + 1) * (range.$4 - range.$2 + 1) > 1024) {
      candidates.addAll(_bounds.keys);
    } else {
      for (var x = range.$1; x <= range.$3; x++) {
        for (var y = range.$2; y <= range.$4; y++) {
          candidates.addAll(_cells[(x, y)] ?? const {});
        }
      }
    }
    return candidates
        .where(
          (c) =>
              _bounds[c]!.overlaps(rect) || rect.contains(_bounds[c]!.center),
        )
        .toSet();
  }

  (int, int, int, int) _range(Rect rect) => (
    (rect.left / _cellSize).floor(),
    (rect.top / _cellSize).floor(),
    (rect.right / _cellSize).floor(),
    (rect.bottom / _cellSize).floor(),
  );
}
