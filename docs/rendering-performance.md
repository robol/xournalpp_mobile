# Rendering performance validation

## Dense pen mitigation (October 31, 2026)

This follow-up supersedes the historical recording-slice/vector-fallback notes
below. The experimental limit is 2,048 pen commands per native raster request,
in addition to the existing 64-stroke and output-pixel limits. A single-point
pen counts as one command. A render-only cursor resumes inside a stroke without
changing points, pressure, serialization, or hit testing. Every pass records a
previous-prefix image plus new commands, awaits its own `toImage`, publishes the
prefix, then rejoins the existing priority queue. This is not a GPU fence.

Incomplete prefixes are never put in the completed-run cache. Dense cold/tail
vectors are withheld behind a determinate progress indicator; small vector
groups remain available. A valid completed image survives scale changes until
the first new prefix is ready. Destructive edits invalidate its display.
PNG capture rejects a partial page rather than silently exporting missing ink.
Input plus output admission is conservative, and errors/admission failures retry
on a subsequent update, not in an automatic allocation retry loop. A working
set that cannot fit may therefore remain pending; this is not a universal
low-memory recovery solution.

Timeline `stroke raster pass` events include command/prefix counts, dimensions,
recording/native durations, active/cache/output byte estimates and obsolete
generation cancellation. Image-handle byte estimates are not physical GPU
memory measurements. Prefix copies add bandwidth and intermediate alpha
rounding: synthetic comparisons allow at most 2/255 per RGBA channel at 1x and
2x, covering tiny/variable widths, translucent overlap, dots, fills and adjacent
highlighters. Visual device review is still required. Non-pen and filled paths
remain ordered atomic operations and may be arbitrarily complex; this patch
does not claim a universal draw/geometry bound.

Automated checks cover separate native requests, no dense vector bypass,
prefix reuse on append/remount, scale rebuilding, obsolete-result disposal,
source XML invariants and the existing lifecycle/queue/viewport regressions.
The synthetic 179-command fixture uses six requests at budget 32; this validates
the mechanism, not a hardware-safe budget or performance improvement.

Device acceptance remains outstanding. A moto g85 5G / Android 16 is connected;
no app installation, document opening, or GPU profiling was performed. Build
environment: Flutter 3.47.8, framework 737ba8f885, engine cf636b1dfb,
Dart 3.13.7. Impeller settings, dependencies and release version are unchanged.

For acceptance, build profile and release variants, preserve the owner's app
data, and use unchanged notebook bytes. Capture effective renderer startup
evidence rather than inferring Vulkan/OpenGLES from configuration. Open the
notebook 20 times, visit all five pages each time, then spend 10 minutes scrolling,
pinching, drawing, erasing, undoing and reopening. Include cold/warm caches and
mixed content. Record first-ink/full-visible-ink latency, raster p95/p99 and slow
frames, crash logs and process/graphics memory over repeated cycles. Compare
against the unmodified Impeller revision where it completes. Sweep budgets only
with measured latency/memory/stability trade-offs; 2,048 is not known-safe.
No device speedup or crash resolution is claimed.

Release validation for 4.2.36+77: `flutter analyze` passed with no issues;
all 220 tests passed. Android profile compilation was started locally but
had not completed when release preparation began; device acceptance above
remains outstanding. The release retains the existing Impeller configuration.

The initial implementation had no connected Android device. Widget tests verify
correctness and structural limits, not Android frame times. Do not interpret
those tests as evidence of a measured speedup on a device. The follow-up audit
also checks device availability; any device results must be recorded separately
from the automated correctness checks.

## Reproducible profile

Run on the same physical Android device, refresh rate, orientation, and Flutter
version for each revision:

```sh
ORG_GRADLE_PROJECT_renderingBenchmark=true flutter run --profile -d DEVICE_ID -t tool/rendering_benchmark.dart
ORG_GRADLE_PROJECT_renderingBenchmark=true flutter run --profile -d DEVICE_ID -t tool/rendering_benchmark.dart --dart-define=PROFILE_MIXED=true
ORG_GRADLE_PROJECT_renderingBenchmark=true flutter run --profile -d DEVICE_ID -t tool/rendering_benchmark.dart --dart-define=PROFILE_PAGES=500 --dart-define=PROFILE_STROKES=20
```

On Android, the Gradle property above installs the profile build under a
separate `.benchmark` application ID, preserving the installed app and its
data. It does not change release builds.

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

## Follow-up audit of the eight-point plan

| Item | Implementation and remaining validation |
| --- | --- |
| 1. Embedded-image animation | Loaded/error states have no persistent loading animation; idle-frame regression covered. |
| 2. First paint and scheduling | Shared serial queue, visibility priority, obsolete-job cancellation, bounded recording batches, and a 2 ms cooperative recording slice. Lazy page creation limits nearby preparation. Cold vector painting rejects clipped strokes; retained pictures/tiles still need comparative profiling. A single highlighter batch can exceed the slice. |
| 3. Smaller invalidation units | Ordered groups of at most 64 strokes, cropped padded regions, unchanged-prefix reuse, retained/active image budgets. Raster timeline events expose estimated in-flight output bytes and cache lookup hits/misses. Native intermediates still require platform memory measurements. |
| 4. Selection and rebuilds | Transient transforms, one release mutation, coalesced region queries, spatial hit testing, targeted page refreshes. Mutation-tracked layer revisions now reuse unchanged compositions, including grouped stroke lists and selection indexes. Edited content must still be replaced, not mutated in place. |
| 5. Live strokes | Separate settled/tail painting, bounded widget count, picture consolidation, frame-synchronized fade, incremental smoothing with exact-output regression. |
| 6. Erasing | Incremental preview path, nearby candidate samples, single-pass splitting. Large operations now yield during path indexing and stroke processing, stage all layers, and commit once. Further edits are temporarily blocked with progress feedback; save, export, and navigation wait for completion. Small operations retain immediate commit behavior. |
| 7. Page geometry | Cached cumulative extents and binary search; mixed-size/zoom and existing viewport regressions. |
| 8. Images/PDF/lifetime | Image disposal, decode-size hints, removal of redundant pixel copy, byte-bounded PDF cache. Direct native PDF display remains conditional on measured encode/decode costs. |

The slice and eraser batch limits are cooperative scheduling limits, not a
hard real-time frame guarantee. Candidate-index queries, one highlighter path,
and the final atomic list publication can still exceed a frame budget on
pathological inputs. Cache counters are lifetime lookup counts, not a count of
unique jobs; deduplicated waiters can each count as misses. Active and cached
image handles may share backing pixels, so their byte estimates must not be
summed as measured physical memory.
