import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;

/// Owns one image handle per entry. Callers own their cloned handles, so an
/// eviction never invalidates an image still displayed by a mounted widget.
class RasterImageCache<K> {
  RasterImageCache({required this.maxBytes, this.maxEntries = 64});

  final int maxBytes;
  final int maxEntries;
  final _images = LinkedHashMap<K, ui.Image>();
  int _bytes = 0;
  final _pending = <K, _PendingRaster>{};

  int get bytes => _bytes;
  int get length => _images.length;

  ui.Image? get(K key) {
    final image = _images.remove(key);
    if (image == null) return null;
    _images[key] = image;
    return image.clone();
  }

  /// Deduplicate concurrent loads, giving each waiter its own image handle.
  Future<ui.Image> load(K key, Future<ui.Image> Function() render) async {
    final cached = get(key);
    if (cached != null) return cached;
    final pending = _pending.putIfAbsent(key, () => _PendingRaster(render()));
    pending.users++;
    ui.Image? image;
    try {
      image = await pending.future;
      if (!pending.stored) {
        put(key, image);
        pending.stored = true;
      }
      return image.clone();
    } finally {
      if (--pending.users == 0) {
        _pending.remove(key);
        image?.dispose();
      }
    }
  }

  void put(K key, ui.Image image) {
    final previous = _images.remove(key);
    if (previous != null) {
      _bytes -= previous.width * previous.height * 4;
      previous.dispose();
    }
    final bytes = image.width * image.height * 4;
    if (bytes > maxBytes) return;
    _images[key] = image.clone();
    _bytes += bytes;
    while (_bytes > maxBytes || _images.length > maxEntries) {
      final oldest = _images.remove(_images.keys.first)!;
      _bytes -= oldest.width * oldest.height * 4;
      oldest.dispose();
    }
  }

  void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _bytes = 0;
  }
}

/// Bound both texture dimensions and RGBA allocation (16 MiB per image).
ui.Size boundedRasterSize(double width, double height) {
  final scale = min(
    1.0,
    min(4096 / max(width, height), sqrt(4 * 1024 * 1024 / (width * height))),
  );
  return ui.Size(
    max(1, (width * scale).floor()).toDouble(),
    max(1, (height * scale).floor()).toDouble(),
  );
}

class _PendingRaster {
  _PendingRaster(this.future);
  final Future<ui.Image> future;
  int users = 0;
  bool stored = false;
}
