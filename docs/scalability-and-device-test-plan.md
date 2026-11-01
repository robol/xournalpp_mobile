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

### Android SAF overwrite safety

SAF document providers offer no portable transactional replace operation. An
existing URI may truncate immediately on `rwt`, and a successful close does not
prove that a provider has durably committed its remote server's copy. We retain
both the previous notebook bytes and pending bytes as app-private recovery drafts
before opening the write descriptor. Each draft is flushed and fsynced, renamed,
and its directory fsynced before truncation is allowed. If backup/read access is
unavailable, the original is not opened for writing. Writes run serially off the
UI thread. Exact readback verification is required before reporting success and
removing recovery copies. We do not attempt an automatic rollback through another
potentially failing stream.

After failure or process death, reopen the app. Recovery offers separately labelled
"before the interrupted save" and "pending save" copies; both recover without an
original destination so that saving uses Save As. External PDF resources are still
references, not embedded by this backup. Recovery copies are private app data: do
not uninstall or clear app data before recovering. A provider may misrepresent a
successful write/readback or lose server data later; this is not a cross-provider
transaction or a guarantee of remote durability.

Run `tool/test_saf_overwrite.sh` with JDK 17+ for fault injection at the native
coordinator boundary. These tests do **not** substitute for device tests. On a
physical Android device or emulator, install a fault-injecting DocumentsProvider
that can truncate on open and independently configure:

- Short writes with a successful close, partial writes followed by an exception,
  failure on open, and failure on readback.
- Revocation of read permission before backup, write permission after backup,
  and read permission after writing.
- A pause immediately after truncation or halfway through writing; force-stop the
  app while paused, then restart it without modifying app data.
- App-private storage exhaustion during either backup and read-only sources.

For each case compare SHA-256 hashes of source, previous bytes, pending bytes, and
recovered exports. No truncation may occur when either durable backup fails.
Every post-truncation failure must retain both exact versions after restart, show
no save success, and allow Save As after source permissions are lost. Also test
normal writes, cancelled recovery, duplicate retries, large notebooks, and cleanup
failure. Record provider/OS/build SHA and repeat with the system file provider and
a cloud-backed provider. Physical-device verification remains required before
claiming provider-specific power-loss durability.
