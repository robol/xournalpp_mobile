# Scalability and real-device regression plan

Run the opt-in synthetic benchmark on a development machine:

```sh
flutter test --dart-define=RUN_SCALABILITY_BENCHMARKS=true test/scalability_benchmark_test.dart -r expanded
```

The output includes JSON records prefixed with `BENCHMARK_JSON` for 10, 100,
and 500 pages with 1,000 and 10,000 vector strokes. Compare serialization
and PDF export latency, output size, and process RSS on the same hardware and
build configuration between revisions. RSS samples are **not** peak memory.
This synthetic test is disabled by default because timing assertions are not
reliable in shared CI runners.

For release candidates, supplement this with physical-device measurements:

| Scenario | Device measurement | Pass criterion |
| --- | --- | --- |
| 20 MB and 200 MB background PDF | PDF open time, peak app RSS, page scroll p95/p99 frame time | No out-of-memory crash or missing pages; compare to previous release |
| 500 pages with 10k strokes | Canvas first-frame latency, gesture frame p95/p99, peak RSS | No ANR; stable response to pan/zoom |
| 10 minutes of rapid inking | Recovery write duration, jank %, cache growth | Recover all edits after force-stop; no unbounded growth |
| Android SAF write interrupted mid-stream | Original `.xopp` integrity or exact recovery draft | No unrecoverable notebook loss; recovery UI identifies draft |
| Android SAF picker cancellation | Number of picker dialogs and success notifications | One picker; no false success |
| Same cloud notebook edited on two devices | Conflicting save and retained versions | Conflict warning; never silently overwrite tested interleaving |
| Offline rename and cross-provider move | Source/copy identities, resource availability | No deletion if source version changed or copy incomplete |
| Screen reader, 200% text scale, touch-only | Focus order, clipped controls, 48dp hit targets | Controls accessible without a stylus |

Record device model, OS, available RAM, app build SHA, test fixture hash,
sample count, p50/p95/p99 frame times, max RSS, and observed failure. Repeat
tests after cache is warm and cold. Browser/desktop and Android SAF behavior
cannot be inferred from widget tests alone.

Keep compatibility fixtures separately labelled by their desktop Xournal++
origin/version and license, especially notebooks with pixmap/attached PDF
backgrounds, Unicode, text entities, transparent images and nested layers.
