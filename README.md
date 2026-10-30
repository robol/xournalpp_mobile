# <img src="assets/xournalpp.png" width="64" style="height: auto;"/> Xournal++ Mobile

[![Current version](https://img.shields.io/badge/dynamic/yaml?label=Current%20version&query=version&url=https%3A%2F%2Fraw.githubusercontent.com%2Frobol%2Fxournalpp_mobile%2Fmaster%2Fpubspec.yaml&style=for-the-badge&logo=flutter&logoColor=white)](https://github.com/robol/xournalpp_mobile)
[![License: EUPL-1.2](https://img.shields.io/badge/License-EUPL--1.2-blue?style=for-the-badge)](LICENSE)

Xournal++ Mobile is a Flutter companion for opening, editing, and annotating [Xournal++](https://github.com/xournalpp/xournalpp) `.xopp` notebooks on mobile devices and other platforms.

> **Status: beta.** The app is usable in practice for working with notebooks, but compatibility and platform behavior are still being improved. Keep backups of important documents.

This repository is a revived and modernized fork of the original **Xournal++ Mobile** by [TheOneWithTheBraid](https://github.com/TheOneWithTheBraid), later mirrored by [xournalpp/xournalpp_mobile](https://github.com/xournalpp/xournalpp_mobile). This fork builds on the original application's document support and editor, with significant changes to its code and design as well as an updated Flutter toolchain.

## Features

- Open, create, edit, and save `.xopp` notebooks, including pages, layers, strokes, highlights, images, text, and LaTeX content.
- Draw with pen and highlighter tools, erase, select and move content, and undo edits. Shape tools include lines, circles, ellipses, squares, and rectangles.
- Use touch, mouse, or stylus input, with optional stylus pressure sensitivity where available. Navigate documents with continuous scrolling, zoom, and a page browser.
- Import PDFs as notebook backgrounds, annotate them, and export notebooks to PDF. Missing background PDFs can be located again when opening a notebook.
- Open recent documents, remember the current page, and recover unsaved work from a recovery draft.
- Open documents through platform file and sharing integrations, including Android document providers and open intents.

Available integrations and behavior vary by platform. The app is a companion to the desktop application, and not every Xournal++ feature or document is supported identically.

## Platforms and downloads

Android, iOS, and web are the main targets. The repository also contains Linux, macOS, and Windows Flutter runners; support and testing vary across platforms.

See the [GitHub releases](https://github.com/robol/xournalpp_mobile/releases) for available builds. The release workflow builds Android APK and AAB packages and Linux, Debian, Windows, and macOS artifacts; Android Play publishing is configured for internal testing. Artifact availability depends on the release build.

## Getting started

Install a current stable [Flutter SDK](https://docs.flutter.dev/get-started/install) and the dependencies for your target platform. The project requires Dart `>=3.10.0 <4.0.0`; use `flutter doctor` to check your setup.

```sh
git clone https://github.com/robol/xournalpp_mobile.git
cd xournalpp_mobile
flutter pub get
flutter run
```

To run in Chrome or build an Android APK:

```sh
flutter run -d chrome
flutter build apk
```

Android builds require the Android SDK and a compatible JDK. Other targets require their platform-specific Flutter build dependencies.

## Development and tests

Run the analyzer and test suite with:

```sh
flutter analyze
flutter test
```

The tests cover document parsing, drawing and input, PDF export and rendering, saving and recovery, and editor behavior. See [AGENTS.md](AGENTS.md) for the project map, development conventions, and focused test commands.

## Known limitations

- Some `.xopp` documents may not render or behave exactly as they do in desktop Xournal++.
- Large notebooks and PDF backgrounds can consume significant memory and may affect performance.
- PDF export does not support every source PDF or notebook configuration, including encrypted or rotated source pages, repeated source pages, and notebooks backed by multiple source PDFs.
- Some editing features and platform integrations remain incomplete or differ between platforms.

## Contributing

Contributions are welcome, especially for compatibility, reliability, performance, accessibility, platform integrations, tests, and documentation. Before making large changes, please open an issue or discussion so the direction can be coordinated.

## Origins and license

The original project, created by [TheOneWithTheBraid](https://github.com/TheOneWithTheBraid), provided the foundation for `.xopp` rendering and editing in this fork. Its original locations are [GitLab](https://gitlab.com/TheOneWithTheBraid/xournalpp_mobile) and the archived [GitHub mirror](https://github.com/xournalpp/xournalpp_mobile). Credit for that original work goes to its author and contributors.

Xournal++ Mobile is licensed under the **European Union Public Licence v1.2**. See [LICENSE](LICENSE).
