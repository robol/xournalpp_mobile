# Rendering performance validation

No Android device was connected during this implementation. Widget tests verify
correctness and structural limits, not Android frame times. Do not interpret
those tests as evidence of a measured speedup on a device.

## Reproducible profile

Run on the same physical Android device, refresh rate, orientation, and Flutter
version for each revision:

```sh
flutter run --profile -d DEVICE_ID -t tool/rendering_benchmark.dart
flutter run --profile -d DEVICE_ID -t tool/rendering_benchmark.dart --dart-define=PROFILE_MIXED=true
flutter run --profile -d DEVICE_ID -t tool/rendering_benchmark.dart --dart-define=PROFILE_PAGES=500 --dart-define=PROFILE_STROKES=20
```

The harness creates an unsaved deterministic notebook and reports build/raster
p95/p99 and over-budget frames in batches of 120 frames. It uses the display's
refresh rate for the budget. Use DevTools Performance for individual frames and
Memory for Dart/native allocations; frame timing alone does not measure input
latency or all GPU memory. Fixture creation happens before frame collection.

Record separate traces for:

1. Cold scrolling through pages 1–10, then warm scrolling back and forth.
2. Repeated pinch zooms and page jumps near the end of the long notebook.
3. A 20-second pen stroke, release, then several short strokes.
4. A long eraser path spanning dense and empty regions, then undo.
5. Selecting hundreds of strokes, dragging, canceling, committing, and undoing.
6. An actual PDF notebook with embedded large images, cold and warm; the
   synthetic harness deliberately excludes source-file IO and PDF rendering.

Capture input-to-visible-response latency using trace input events or high-speed
video, along with peak memory and allocation/GC bursts. Compare cold and warm
results separately. Success means lower p95/p99 and fewer over-budget frames
without changed pixels, missing content, shifted zoom anchors, or undo/save
regressions. A 60 Hz display has a 16.7 ms budget; 120 Hz has 8.3 ms.

## Implemented bounds and remaining decisions

- Stroke jobs are serialized, prioritize screen-visible regions, and can run
  during animations. Recording yields between bounded pen batches.
- Runs are partitioned into ordered groups of at most 64 strokes and cropped to
  padded ink bounds. A small append affects the last group. Mixed-content and
  highlighter ordering are preserved; this is not spatial tiling.
- Retained stroke/solid image cache limits remain 48/16 MiB. Mounted stroke
  image handles have a conservative 64 MiB limit; offscreen handles are evicted
  first and exact vector painting remains available when admission fails. The
  serialized raster queue bounds native stroke work to one image at a time.
  Stroke model data, framework decoded images, and native intermediates are
  additional memory. PDF encoded-cache bytes are capped separately at 32 MiB.
- Selection movement is transient until release. Long-stroke smoothing is
  incremental and preserves the batch algorithm's point coordinates/widths.
- Cold vector painting is still synchronous, with clip-based stroke rejection.
  A single very long highlighter remains indivisible to preserve alpha joins.

Use the profile to decide whether cold vector rendering needs a deeper retained
picture/tile design, and whether PDF encode/decode should be replaced by a direct
native-image display path. Neither change should be made on assumptions about
engine/backend costs. Preserve original image bytes and notebook geometry in
any later display-only optimization.
