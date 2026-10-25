# AGENTS.md

## Scope

These instructions apply to the entire repository.

## Project overview

Xournal++ Mobile is an experimental Flutter companion for opening, viewing, annotating, editing, saving, and exporting Xournal++ `.xopp` notebooks. It targets Android, iOS, web, Linux, macOS, and Windows, although Android, iOS, and web are the main product targets. Treat document compatibility and preservation of user work as higher priorities than broad refactors or cosmetic cleanup.

This repository is a revived fork of the original 2020-2022 Xournal++ Mobile project. The 2026 work modernized it for Dart 3/current Flutter and added substantial input, scrolling/zooming, Android document-provider, PDF background, and PDF export behavior. The code therefore mixes older nullable/domain patterns with newer Flutter APIs. Preserve local conventions unless the task explicitly includes a migration.

The package name is `xournalpp`, the application is currently versioned in `pubspec.yaml`, and Dart must satisfy `>=3.10.0 <4.0.0`.

## Repository map

- `lib/main.dart`: application entry point, theme, localization delegates, and `XournalppMobile`.
- `lib/main_desktop.dart`: desktop entry point forwarding to the main application.
- `lib/pages/OpenPage.dart`: launcher, recent files, file/PDF opening, Android/iOS sharing intents, and missing-PDF recovery.
- `lib/pages/CanvasPage.dart`: the main editor coordinator. It owns page layout, continuous scrolling, zoom, tool state, selection, undo, erasing, dirty state, save/share/export, and PDF prefetching. This is deliberately large and changes here usually need focused widget tests.
- `lib/src/XppFile.dart`, `XppPage.dart`, `XppLayer.dart`: `.xopp` document model plus gzip/XML parsing and serialization.
- `lib/layer_contents/`: concrete page content (`XppStroke`, `XppImage`, `XppText`, and `XppTexImage`) with rendering, selection/erasing, translation, and XML serialization.
- `lib/src/XppBackground.dart`: solid, ruled, graph, image, and PDF backgrounds, including raster caches.
- `lib/src/PdfBackgroundRenderService.dart`: queued PDF raster rendering with request deduplication, active/prefetch priority, source-session reuse, memory/disk caches, and DPI buckets.
- `lib/src/PdfExporter.dart`: PDF export. It either writes a generated document or incrementally updates a source PDF with vector/image/text overlays.
- `lib/src/PdfImage.dart`: `pdfrx` page opening, sizing, rasterization, and image encoding.
- `lib/src/XppPickedFile.dart` and `lib/src/conditional/`: cross-platform file abstraction and IO/web implementations.
- `lib/widgets/PointerListener.dart`: raw mouse, touch, and stylus gesture state machine.
- `lib/widgets/XppPageStack.dart`: page/background/layer composition, selection UI, stroke-run rasterization, and PNG capture.
- `lib/widgets/`: editor controls, previews, page browser/list, drawer, loading UI, and web drop target.
- `lib/l10n/*.arb`: localization sources. `lib/generated/` is generated localization code.
- `test/`: unit and widget regression tests. There is currently no separate integration-test suite or checked-in notebook fixture directory.
- `android/app/src/main/kotlin/it/robol/xournal/mobile/MainActivity.kt`: Android storage and open-intent method channels plus stylus-button event handling.
- `.github/workflows/flutter-release.yml`: tag/manual multi-platform release builds; Android APK/AAB release and Play internal publishing are handled there.
- `debian/`, `snap/`, and platform directories: packaging and Flutter runner projects.

## Runtime and document flow

1. `main()` initializes Flutter and `pdfrx`, then opens `OpenPage`.
2. `OpenPage`, `MainDrawer`, drag/drop, or a platform intent produces an `XppPickedFile`.
3. A `.xopp` file is decoded as gzip-compressed UTF-8 XML by `XppFile.fromXppPickedFile`. The in-memory hierarchy is `XppFile -> XppPage -> XppLayer -> XppContent`.
4. `CanvasPage` lays pages out in one continuous scroll view. `XppPageStack` renders backgrounds and ordered layers; `PointerListener` converts pointer events into drawing, erasing, selection, panning, swiping, or pinch zoom.
5. Saving follows the reverse path: content/background objects emit XML, `XppFile` builds the document, and the result is gzip encoded and written through `XppPickedFile`.
6. Importing a PDF creates notebook pages whose backgrounds reference one PDF. Backgrounds are rasterized asynchronously for display. PDF export retains compatible source pages and adds notebook content as overlays where possible.

## Document-model invariants

- `.xopp` compatibility is a core boundary. Preserve gzip encoding, XML names/attributes, page and layer order, and content order. The parser assigns temporary counters specifically to reconstruct mixed XML child order.
- Page and content geometry is stored in Xournal page coordinates/points. Display zoom and device pixel ratio belong in widget/raster calculations; do not write screen-space coordinates back into the model.
- PDF background page numbers are one-based. A missing `filename` on a later PDF background inherits the last PDF filename while parsing, matching Xournal++ files.
- New content currently goes to the last layer. Do not silently flatten layers or move content between layers.
- Stroke XML contains coordinate pairs and either one width or per-point widths. Preserve pressure-derived widths, highlighter semantics, render padding, cached bounds, and eraser splitting behavior.
- Every `XppContent` implementation must keep rendering, XML serialization, translation, selection bounds, region selection, and erasing behavior consistent. Some legacy content types still have incomplete selection TODOs; do not claim support without implementing and testing it.
- Some model fields are nullable for historical reasons, but rendering and serialization generally expect a valid loaded document to have page sizes, backgrounds, layers, and content. Validate at file boundaries rather than spreading new forced-null assumptions through the renderer.
- Saving and exporting are high-risk operations. Avoid lossy fallback behavior and never overwrite a user's original merely to simplify a code path.

## Rendering, input, and async invariants

- Continuous-scroll position, current page, horizontal offset, and zoom are coupled in `CanvasPage`. When changing page extents or scale calculations, preserve the same document point at the top/focal position and add a regression test.
- Do not trigger expensive PDF or stroke rerasterization for every pinch update. The current design defers background raster updates until pinch end and separates display scale from committed raster scale.
- PDF render cache keys depend on the source, page, variant, and bucketed output size. Maintain request deduplication, active-over-prefetch priority, bounded caches, source-session reuse, and disposal behavior.
- Page widgets use keep-alive and targeted `GlobalKey` refreshes. Avoid rebuilding every page or eagerly prefetching all thumbnails/backgrounds; large notebooks are already memory-sensitive.
- Pointer handling is a state machine spanning multiple events and devices. Preserve distinctions among mouse, touch, stylus, inverted stylus, stylus buttons, and the “draw with stylus only” preference. A pinch must cancel an in-progress stroke and must not save one on pointer-up.
- Android consumes raw stylus button press/release events in `MainActivity.kt` so Flutter continues receiving usable pointer behavior. Changes to Dart button masks may require corresponding Android changes and tests.
- Keep transient stroke and eraser previews out of the persistent model until the gesture is committed. Route editor mutations through the existing add/replace/erase/undo helpers so dirty state, selection, spatial eraser indexes, and page refreshes stay coherent.
- Guard UI work after `await` with `mounted`/`context.mounted`. Cancel timers/listeners and dispose controllers/services owned by a widget.

## Files and platform behavior

- Keep platform-neutral callers on `XppPickedFile` and the conditional storage/open-file libraries. Do not import `dart:io` into web-reachable files.
- Android paths may be `content://` document URIs rather than filesystem paths. Reads, writes, create-document flows, and persisted URI permissions are bridged through `it.robol.xournal.mobile/storage`; open intents use `it.robol.xournal.mobile/intent`.
- Missing external PDF backgrounds are resolved through a callback and remembered in `SharedPreferences`. A failed/cancelled selection must not be cached.
- Web storage stubs intentionally lack arbitrary local-path IO. Test platform-specific changes on the affected target or keep them behind existing conditional boundaries.
- PDF export intentionally rejects unsupported cases such as encrypted PDFs, rotated source pages, duplicated source pages, and notebooks backed by multiple source PDFs. Add explicit tests before widening those constraints.

## UI, localization, and style

- Use Material widgets and the existing theme from `main.dart`. Keep page content readable independently of app light/dark theme; `XppPageStack` supplies a white page base and page-local text/icon colors.
- User-facing localized strings belong in all applicable `lib/l10n/intl_*.arb` files. Regenerate the tracked `lib/generated/` localization outputs using the repository's configured Flutter Intl workflow; do not hand-edit generated files.
- Preserve the legacy UpperCamelCase Dart filenames and nearby naming/style unless a task explicitly calls for a repository-wide rename. New private implementation details should still follow normal Dart conventions.
- Run `dart format` only on Dart files you changed. Do not format the entire legacy tree as incidental cleanup.
- Keep changes focused. Do not edit generated Flutter registrants, platform ephemeral files, build output, release metadata, or package locks unless the task actually changes those inputs.

## Tests and validation

Choose the smallest relevant test during iteration, then run the full checks for a completed code change:

```sh
flutter analyze
flutter test
```

Run a focused test with, for example:

```sh
flutter test test/pointer_listener_test.dart
flutter test test/pdf_exporter_test.dart
```

Format changed Dart files explicitly:

```sh
dart format path/to/changed_file.dart test/path/to/changed_test.dart
```

Test ownership is roughly:

- `pointer_listener_test.dart`: desktop wheel pan, page jumps, zoom anchoring, pinch lifecycle, stylus buttons, and no accidental stroke commits.
- `xpp_page_stack_test.dart` and `background_raster_cache_test.dart`: page/background invalidation and raster cache sizing.
- `pdf_background_render_service_test.dart`: queueing, priorities, cache timing/failures, DPI buckets, source reuse, and missing-file fallback.
- `pdf_exporter_test.dart`: source-PDF parsing, xref variants, graphics-state isolation, overlays, generated/mixed pages, and rejected inputs.
- `xpp_stroke_eraser_test.dart`: stroke splitting, bounds, offsets, and background serialization.
- `widget_test.dart`: launcher and platform-dependent canvas menu behavior.

Add or update tests whenever changing parsing/serialization, coordinate transforms, page extents, zoom/pan behavior, pointer transitions, cache keys, save/export behavior, or platform feature gates. Prefer deterministic in-memory fakes and small synthetic PDF/XML data over device IO in unit tests.

For dependency changes, run `flutter pub get` and commit `pubspec.lock`. For platform-channel changes, also compile or manually exercise the affected platform when available. Release builds are tag-driven (`v*`); do not bump versions or edit release configuration unless requested.

## Working-tree hygiene

- Check `git status` before and after work. Preserve unrelated user changes and untracked files.
- Do not commit build products such as `.dart_tool/`, `build/`, or platform `ephemeral/` directories.
- When behavior is historically delicate, consult `git log -- <path>` and the nearby tests before simplifying it. Recent history is especially relevant for `CanvasPage`, `PointerListener`, `XppPageStack`, `PdfBackgroundRenderService`, `PdfExporter`, `OpenPage`, and the Android activity.
