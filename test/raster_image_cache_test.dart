import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:xournalpp/src/RasterImageCache.dart';

void main() {
  test('raster sizes bound area and dimensions while preserving aspect', () {
    for (final size in [const ui.Size(4463, 6315), const ui.Size(100000, 10)]) {
      final result = boundedRasterSize(size.width, size.height);
      expect(result.width * result.height, lessThanOrEqualTo(4 * 1024 * 1024));
      expect(result.longestSide, lessThanOrEqualTo(4096));
    }
    expect(boundedRasterSize(1080, 1920), const ui.Size(1080, 1920));
  });

  testWidgets('concurrent loads share rendering and own independent handles', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final picture = recorder.endRecording();
    final source = (await tester.runAsync(() => picture.toImage(2, 2)))!;
    picture.dispose();
    final cache = RasterImageCache<int>(maxBytes: 16);
    final ready = Completer<ui.Image>();
    var calls = 0;
    Future<ui.Image> render() {
      calls++;
      return ready.future;
    }

    final first = cache.load(1, render);
    final second = cache.load(1, render);
    ready.complete(source);
    final clients = await Future.wait([first, second]);
    expect(calls, 1);
    expect(source.debugDisposed, isTrue);
    cache.clear();
    clients.first.dispose();
    expect(clients.last.debugDisposed, isFalse);
    clients.last.dispose();
  });

  testWidgets('LRU eviction releases cache ownership but keeps clients valid', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final picture = recorder.endRecording();
    final image = (await tester.runAsync(() => picture.toImage(2, 2)))!;
    picture.dispose();
    final cache = RasterImageCache<int>(maxBytes: 32);
    cache.put(1, image);
    cache.put(2, image);
    final client = cache.get(1)!;
    cache.put(3, image);
    expect(cache.get(2), isNull);
    expect(cache.bytes, 32);
    expect(cache.length, 2);
    cache.clear();
    expect(cache.bytes, 0);
    expect(client.debugDisposed, isFalse);
    final copy = client.clone();
    copy.dispose();
    client.dispose();
    image.dispose();
  });
}
