import 'NotebookCache.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:flutter/material.dart';
import 'package:xournalpp/src/TransparentImage.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppTexImage.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/HexColor.dart';
import 'package:xournalpp/src/PdfBackgroundRenderService.dart';
import 'package:xournalpp/src/PdfImage.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/LoadingFileDialog.dart';

import 'XppLayer.dart';
import 'XppPage.dart';

int _cacheSessionCounter = 0;

class XppFile {
  XppFile({this.title, this.pages, this.previewImage});

  NotebookStorage? storage;
  StoredNotebook? storageNotebook;
  bool openedFromCache = false;
  bool cachedEdits = false;
  int cachedPage = 0;
  final cachedPdfs = <String, Uint8List>{};
  void Function()? onCacheError;
  Future<void>? _cacheWork;
  String _cacheSession =
      '${DateTime.now().microsecondsSinceEpoch}_${_cacheSessionCounter++}';
  final _pendingCachePdfs = <String>{};

  List<String> get pdfReferences =>
      pages
          ?.map((page) => page.background)
          .whereType<XppBackgroundPdf>()
          .map((pdf) => pdf.filename ?? '')
          .toSet()
          .toList() ??
      [];

  Future<void> cacheSnapshot(
    Uint8List bytes, {
    required bool dirty,
    int page = 0,
    bool saved = false,
    int? expectedGeneration,
  }) {
    final notebook = storageNotebook;
    if (notebook == null) return Future.value();
    final references = pdfReferences;
    final generation = expectedGeneration ?? NotebookCache.instance.generation;
    final sourceStorage = storage;
    _cacheWork = (_cacheWork ?? Future<void>.value())
        .then((_) async {
          if (!await NotebookCache.instance.enabled) return;
          await NotebookCache.instance.record(
            notebook: notebook,
            bytes: bytes,
            pdfs: cachedPdfs,
            references: references,
            dirty: dirty,
            page: page,
            expectedGeneration: generation,
            resourceSession: _cacheSession,
          );
          if (saved && generation == NotebookCache.instance.generation)
            await NotebookCache.instance.discardWorking(notebook);
          if (!openedFromCache &&
              generation == NotebookCache.instance.generation) {
            for (final ref in references) {
              if (ref.isEmpty ||
                  cachedPdfs.containsKey(ref) ||
                  !_pendingCachePdfs.add(ref))
                continue;
              unawaited(_cachePdf(sourceStorage, notebook, ref, generation));
            }
          }
        })
        .catchError((Object error) {
          debugPrint('Could not update notebook cache: $error');
          onCacheError?.call();
        });
    return _cacheWork!;
  }

  void useCachedResources(CachedNotebook cached) {
    cachedPdfs.addAll(cached.pdfs);
    _cacheSession = cached.resourceSession ?? _cacheSession;
  }

  void _rememberPdf(String reference, Uint8List bytes) {
    cachedPdfs[reference] = bytes;
    final notebook = storageNotebook;
    if (notebook == null) return;
    unawaited(
      NotebookCache.instance
          .addPdfs(
            notebook,
            {reference: bytes},
            expectedGeneration: NotebookCache.instance.generation,
            resourceSession: _cacheSession,
          )
          .catchError((Object _) {
            onCacheError?.call();
          }),
    );
  }

  Future<void> _cachePdf(
    NotebookStorage? sourceStorage,
    StoredNotebook notebook,
    String ref,
    int generation,
  ) async {
    try {
      final bytes = sourceStorage != null
          ? await sourceStorage
                .readPdf(notebook, ref)
                .timeout(const Duration(seconds: 15))
          : (await XppPickedFile.fromInternalPath(path: ref)).bytes;
      cachedPdfs[ref] = bytes;
      try {
        await NotebookCache.instance.addPdfs(
          notebook,
          {ref: bytes},
          expectedGeneration: generation,
          resourceSession: _cacheSession,
        );
      } catch (_) {
        onCacheError?.call();
      }
    } catch (_) {
      /* The published checkpoint explicitly marks this PDF missing. */
    } finally {
      _pendingCachePdfs.remove(ref);
    }
  }

  Future<void> discardCachedEdits() async {
    await _cacheWork;
    final notebook = storageNotebook;
    if (notebook == null) return;
    try {
      await NotebookCache.instance.discardWorking(notebook);
    } catch (_) {
      onCacheError?.call();
    }
  }

  static Future<XppFile> fromCachedNotebook(
    CachedNotebook cached,
    NotebookStorage? storage,
    FileNotAvailableCallback onUnavailable,
  ) async {
    final file = await fromXppPickedFile(
      XppPickedFile(
        cached.bytes,
        fileName: cached.notebook.name,
        fileExtension: 'xopp',
      ),
      null,
      onUnavailable,
    );
    file.storage = storage;
    file.storageNotebook = cached.notebook;
    file.openedFromCache = true;
    file.cachedEdits = cached.dirty;
    file.cachedPage = cached.page;
    file.useCachedResources(cached);
    return file;
  }

  static Future<XppFile> openStoredNotebook(
    NotebookStorage storage,
    StoredNotebook notebook,
    FileNotAvailableCallback onUnavailable, {
    Future<CachedNotebook?> Function(Object error)? onReadFailure,
    void Function()? onCacheError,
  }) async {
    if (notebook.backendId != storage.id)
      throw ArgumentError('Notebook belongs to a different storage backend');
    late final Uint8List bytes;
    try {
      bytes = await storage.readNotebook(notebook);
    } catch (error) {
      final cached = await onReadFailure?.call(error);
      if (cached != null)
        return fromCachedNotebook(cached, storage, onUnavailable);
      rethrow;
    }
    final file = await fromXppPickedFile(
      XppPickedFile(bytes, fileName: notebook.name, fileExtension: 'xopp'),
      null,
      onUnavailable,
    );
    file.storage = storage;
    file.storageNotebook = notebook;
    file.onCacheError = onCacheError;
    unawaited(file.cacheSnapshot(bytes, dirty: false));
    return file;
  }

  Future<XppPickedFile> readBackgroundPdf(
    BuildContext context,
    XppBackgroundPdf background,
  ) async {
    final filename = background.filename;
    if (openedFromCache) {
      if (cachedPdfs.containsKey(filename)) {
        return XppPickedFile(
          cachedPdfs[filename]!,
          fileName: filename!,
          fileExtension: 'pdf',
        );
      }
      final recovered = await background.onUnavailable(context, filename);
      if (filename != null) _rememberPdf(filename, recovered.bytes);
      return recovered;
    }
    if (storage != null && storageNotebook != null && filename != null) {
      try {
        final bytes = await storage!.readPdf(storageNotebook!, filename);
        _rememberPdf(filename, bytes);
        return XppPickedFile(bytes, fileName: filename, fileExtension: 'pdf');
      } catch (_) {
        if (!context.mounted) rethrow;
        return background.onUnavailable(context, filename);
      }
    }
    if (filename != null && filename.isNotEmpty) {
      try {
        return await XppPickedFile.fromInternalPath(path: filename);
      } catch (_) {}
    }
    if (!context.mounted) throw StateError('PDF recovery owner was disposed.');
    return background.onUnavailable(context, filename);
  }

  // Successful snapshots live with this notebook, not the global renderer.
  // Reopening a notebook resolves fresh bytes. Failed lookups remain retryable.
  final _pdfSources =
      <
        (PdfBackgroundRenderService, Object),
        Future<PdfBackgroundRenderSource>
      >{};

  Future<PdfBackgroundRenderSource>? resolvedPdfSource(
    XppBackgroundPdf background,
    PdfBackgroundRenderService service,
  ) => _pdfSources[(service, background.filename ?? background)];

  Future<PdfBackgroundRenderSource> resolvePdfSource(
    BuildContext context,
    XppBackgroundPdf background, {
    PdfBackgroundRenderService? renderService,
  }) {
    final service = renderService ?? pdfBackgroundRenderService;
    final sourcesInDocument =
        pages
            ?.map((page) => page.background)
            .whereType<XppBackgroundPdf>()
            .map((background) => background.filename ?? background)
            .toSet() ??
        {};
    _pdfSources.removeWhere((key, _) => !sourcesInDocument.contains(key.$2));
    final key = (service, background.filename ?? background);
    return _pdfSources.putIfAbsent(key, () {
      late final Future<PdfBackgroundRenderSource> pending;
      pending = service
          .sourceForPath(
            storage != null || openedFromCache ? null : background.filename,
            fallback: () => storage == null && !openedFromCache
                ? background.onUnavailable(context, background.filename)
                : readBackgroundPdf(context, background),
            isCurrent: () => context.mounted,
          )
          .catchError((Object error, StackTrace stack) {
            if (identical(_pdfSources[key], pending)) _pdfSources.remove(key);
            Error.throwWithStackTrace(error, stack);
          });
      return pending;
    });
  }

  /// create an empty [XppFile]
  static XppFile empty({
    String? title,
    XppPageSize? pageSize,
    Color? background,
  }) {
    return XppFile(
      title: title,
      pages: [XppPage.empty(background: background)],
    );
  }

  /// creates an [XppFile] from a PDF document opened in a [XppPickedFile]
  static Future<XppFile> importPdf({required XppPickedFile pdf}) async {
    final pageSizes = await pdfPageSizes(pdf);
    final pdfPath = pdf.path ?? await pdf.saveToTemporaryPath();
    XppFile file = XppFile.empty(title: pdf.fileName)..pages!.clear();
    for (int i = 0; i < pageSizes.length; i++) {
      final size = pageSizes[i];
      file.pages!.add(
        XppPage.empty()
          ..pageSize = size
          ..background = XppBackgroundPdf(
            onUnavailable: (context, String? p) async =>
                throw ("$p is not available even though just imported"),
            page: i + 1,
            filename: pdfPath,
          ),
      );
    }
    return file;
  }

  Future<void> prepareForOpening(
    BuildContext context, {
    int currentPage = 0,
    int thumbnailCount = 0,
    PdfBackgroundRenderService? renderService,
  }) async {
    if (pages == null || pages!.isEmpty) return;

    final selectedPage = pages![currentPage.clamp(0, pages!.length - 1)];
    final selectedBackground = selectedPage.background;
    if (selectedBackground is XppBackgroundPdf) {
      final source = await resolvePdfSource(
        context,
        selectedBackground,
        renderService: renderService,
      );
      await (renderService ?? pdfBackgroundRenderService).request(
        source,
        selectedBackground.page,
        PdfBackgroundRenderVariant.full,
        targetWidth: selectedPage.pageSize?.width,
        targetHeight: selectedPage.pageSize?.height,
        pageWidthPoints: selectedPage.pageSize?.width,
        pageHeightPoints: selectedPage.pageSize?.height,
        priority: PdfBackgroundRenderPriority.active,
      );
    }

    final visibleCount = pages!.length < thumbnailCount
        ? pages!.length
        : thumbnailCount;
    for (var i = 0; i < visibleCount; i++) {
      final page = pages![i];
      final background = page.background;
      if (background is! XppBackgroundPdf) continue;
      unawaited(
        resolvePdfSource(context, background, renderService: renderService)
            .then(
              (source) => (renderService ?? pdfBackgroundRenderService).request(
                source,
                background.page,
                PdfBackgroundRenderVariant.full,
                targetWidth: page.pageSize?.width,
                targetHeight: page.pageSize?.height,
                pageWidthPoints: page.pageSize?.width,
                pageHeightPoints: page.pageSize?.height,
                priority: PdfBackgroundRenderPriority.prefetch,
              ),
            )
            .catchError((Object _) => Uint8List(0)),
      );
    }
  }

  /// showing a [open] dialog and pushes a [CanvasPage] to the provided [BuildContext]'s [Navigator]
  static void openAndEdit({required BuildContext context}) async {
    XppFile file;
    late XppPickedFile rawFile;
    int initialPage = 0;
    try {
      file = await runWithLoadingFileDialog(context, () async {
        rawFile = await XppPickedFile.importFromStorage(
          type: XppFilePickType.custom,
          fileExtension: 'xopp',
        );
        initialPage = await lastOpenedPageForPath(rawFile.path);
        return await fromXppPickedFile(
          rawFile,
          (percentage) => null,
          showMissingFileDialog,
          onCacheError: () {
            if (context.mounted)
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(content: Text(S.of(context).cacheUpdateFailed)),
              );
          },
        );
      });

      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => CanvasPage(
            file: file,
            filePath: rawFile.path,
            initialPage: initialPage,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(S.of(context).noFileSelected),
          content: Text(S.of(context).youDidNotSelectAnyFile + e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).close),
            ),
          ],
        ),
      );
    }
  }

  /// showing a file picker, decoding and parsing to [XppFile]
  static Future<XppFile> open(
    Function(double) percentageCallback,
    FileNotAvailableCallback onUnavailable, {
    void Function(String?)? onPath,
  }) async {
    /// showing a [XppPickedFile]
    XppPickedFile rawFile = await XppPickedFile.importFromStorage(
      type: XppFilePickType.custom,
      fileExtension: 'xopp',
    );
    onPath?.call(rawFile.path);

    /// decoding by [fromXppPickedFile]
    XppFile file = await fromXppPickedFile(
      rawFile,
      percentageCallback,
      onUnavailable,
    );

    return file;
  }

  /// decoding and parsing a [XppPickedFile] to [XppFile]
  static Future<XppFile> fromXppPickedFile(
    XppPickedFile rawFile,
    Function(double)? percentageCallback,
    FileNotAvailableCallback onUnavailable, {
    void Function()? onCacheError,
  }) async {
    final file = await compute(
      _parseNotebook,
      rawFile,
      debugLabel: 'parse xopp',
    );
    for (final page in file.pages ?? <XppPage>[]) {
      final background = page.background;
      if (background is XppBackgroundPdf) {
        page.background = XppBackgroundPdf(
          onUnavailable: onUnavailable,
          filename: background.filename,
          page: background.page,
          domain: background.domain,
        );
      }
    }
    file.onCacheError = onCacheError;
    if (rawFile.path != null) {
      file.storage = localNotebookStorage;
      file.storageNotebook = StoredNotebook(
        backendId: 'local',
        id: rawFile.path!,
        name: rawFile.fileName ?? file.title ?? 'Untitled',
      );
      unawaited(file.cacheSnapshot(rawFile.bytes, dirty: false));
    }
    try {
      percentageCallback?.call(1.0);
    } catch (_) {}
    return file;
  }

  static Future<XppPickedFile> _unusedPdfRecovery(
    BuildContext context,
    String? path,
  ) => throw StateError('PDF recovery is unavailable during parsing');

  static XppFile _parseNotebook(XppPickedFile rawFile) {
    /// extracting the document title
    final rawTitle = _decodePathForFileName(
      rawFile.fileName ?? rawFile.path ?? 'Untitled',
    ).split(RegExp(r'[/\\]')).last;
    final extensionStart = rawTitle.lastIndexOf('.');
    final title = extensionStart > 0
        ? rawTitle.substring(0, extensionStart)
        : rawTitle;

    /// decoding file bytes from GZip to a UTF-8 [Uint8List]
    List<int> bytes = GZipDecoder().decodeBytes(rawFile.toUint8List());

    /// decoding the [Uint8List] to a [String]
    String fileText = utf8.decode(bytes);
    //Clipboard.setData(ClipboardData(text: fileText));

    /// parsing the [String] to a [XmlDocument]
    XmlElement documentTree = XmlDocument.parse(
      fileText,
    ).findElements('xournal').toList()[0];

    /// decoding the preview image from base64 [String] to [Uint8List] of bytes
    Uint8List previewImage;
    try {
      previewImage = base64Decode(
        documentTree.findElements('preview').toList()[0].innerText,
      );
    } catch (e) {
      previewImage = kTransparentImage;
    }

    List<XppPage> pages = [];
    String? lastPdfBackgroundFilename;
    Iterable<XmlElement> pageElements = documentTree.findElements('page');
    pageElements.forEach((XmlElement pageElement) {
      XppPageSize pageSize = XppPageSize(
        width: double.parse(pageElement.getAttribute('width')!),
        height: double.parse(pageElement.getAttribute('height')!),
      );
      XppBackground? background;
      if (pageElement.findElements('background').isNotEmpty) {
        XmlElement backgroundElement = pageElement
            .findElements('background')
            .toList()[0];
        switch (backgroundElement.getAttribute('type')) {
          case "pixmap":
            background = XppBackgroundImage(
              filename: backgroundElement.getAttribute('filename'),
            );
            break;
          case "pdf":
            final filename =
                backgroundElement.getAttribute('filename') ??
                lastPdfBackgroundFilename;
            lastPdfBackgroundFilename = filename;
            background = XppBackgroundPdf(
              onUnavailable: _unusedPdfRecovery,
              filename: filename,
              page: int.parse(backgroundElement.getAttribute('pageno')!),
            );
            break;
          case "solid":
            switch (backgroundElement.getAttribute('style')) {
              case 'lined':
                background = XppBackgroundSolidLined(
                  size: pageSize,
                  color: parseColor(backgroundElement.getAttribute('color')),
                );
                break;
              case 'ruled':
                background = XppBackgroundSolidRuled(
                  size: pageSize,
                  color: parseColor(backgroundElement.getAttribute('color')),
                );
                break;
              case 'graph':
                background = XppBackgroundSolidGraph(
                  size: pageSize,
                  color: parseColor(backgroundElement.getAttribute('color')),
                );
                break;
              case 'plain':
                background = XppBackgroundSolidPlain(
                  size: pageSize,
                  color: parseColor(backgroundElement.getAttribute('color')),
                );
                break;
              default:
                background = XppBackground.none;
            }
            break;
          default:
            background = XppBackground.none;
            break;
        }
      }
      List<XppLayer> layers = [];
      Iterable<XmlElement> layerElements = pageElement.findElements('layer');
      layerElements.forEach((XmlElement layer) {
        Map<int, XppContent?> content = {};
        for (final child in layer.children.whereType<XmlElement>()) {
          if (!{
            'image',
            'text',
            'teximage',
            'stroke',
          }.contains(child.name.local)) {
            throw UnsupportedError(
              'Unsupported Xournal content: ${child.name.local}',
            );
          }
        }

        /// unfortunately, it's not possible to forEach threw all child **elements**, but only threw
        /// all **nodes** (including text nodes etc.). Let's workaround...

        /// cleaning nodes and numbering them
        int index = 0;
        layer.children.forEach((XmlNode node) {
          if (node.nodeType == XmlNodeType.TEXT) {
            if (node.innerText.trim().isNotEmpty)
              print('Skipping text \'${node.value}\'');
            return;
          }
          if (node.nodeType != XmlNodeType.ELEMENT) {
            print(
              'Unexpected XmlNodeType. Expected XmlNodeType.ELEMENT, got ' +
                  node.nodeType.toString() +
                  '. Removing.',
            );
            return;
          }
          node.setAttribute('counter', index.toString());
          index++;
        });

        /// processing all images first
        layer.findElements('image').forEach((imageElement) {
          content[int.parse(imageElement.getAttribute('counter')!)] = XppImage(
            data: base64Decode(imageElement.innerText.trim()),
            topLeft: Offset(
              double.parse(imageElement.getAttribute('left')!),
              double.parse(imageElement.getAttribute('top')!),
            ),
            bottomRight: Offset(
              double.parse(imageElement.getAttribute('right')!),
              double.parse(imageElement.getAttribute('bottom')!),
            ),
          );
        });

        /// processing all texts
        layer.findElements('text').forEach((textElement) {
          Color color = parseColor(textElement.getAttribute('color'));
          content[int.parse(textElement.getAttribute('counter')!)] = XppText(
            color: color,
            // note: not trimming
            text: textElement.innerText.replaceAllMapped(
              RegExp(r'(&amp;|&lt;|&gt;)'),
              (Match subtext) {
                switch (subtext.group(0)) {
                  case '&amp;':
                    return '&';
                  case '&lt;':
                    return '<';
                  case '&gt;':
                    return '>';
                }
                return subtext.group(0)!;
              },
            ),
            size: double.parse(textElement.getAttribute('size')!),
            fontFamily: textElement.getAttribute('font'),
            offset: Offset(
              double.parse(textElement.getAttribute('x')!),
              double.parse(textElement.getAttribute('y')!),
            ),
          );
        });

        /// processing all lateximages
        layer.findElements('teximage').forEach((texElement) {
          content[int.parse(texElement.getAttribute('counter')!)] = XppTexImage(
            text: texElement.getAttribute('text')!.trim(),
            color: parseColor(texElement.getAttribute('color')!.trim()),
            topLeft: Offset(
              double.parse(texElement.getAttribute('left')!),
              double.parse(texElement.getAttribute('top')!),
            ),
            bottomRight: Offset(
              double.parse(texElement.getAttribute('right')!),
              double.parse(texElement.getAttribute('bottom')!),
            ),
          );
        });

        /// processing all strokes
        layer.findElements('stroke').forEach((strokeElement) {
          late XppStrokeTool tool;
          switch (strokeElement.getAttribute('tool')) {
            case "pen":
              tool = XppStrokeTool.PEN;
              break;
            case "eraser":
              tool = XppStrokeTool.ERASER;
              break;
            case "highlighter":
              tool = XppStrokeTool.HIGHLIGHTER;
              break;
            default:
              throw UnsupportedError(
                'Unsupported Xournal stroke tool: ${strokeElement.getAttribute('tool')}',
              );
          }
          Color color = parseColor(strokeElement.getAttribute('color'));
          List<XppStrokePoint> points = [];
          List<String> rawWidth = strokeElement
              .getAttribute('width')!
              .trim()
              .split(RegExp(r'\s+'));
          List<String> rawPoints = strokeElement.innerText.trim().split(
            RegExp(r'\s+'),
          );
          for (int i = 0; i < rawPoints.length / 2; i++) {
            points.add(
              XppStrokePoint(
                width: double.parse(
                  (rawWidth.length > i) ? rawWidth[i] : rawWidth[0],
                ),
                x: double.parse(rawPoints[i * 2]),
                y: double.parse(rawPoints[i * 2 + 1]),
              ),
            );
          }
          if (points.isEmpty) throw FormatException('Stroke has no points.');
          final fillAttribute = strokeElement.getAttribute('fill');
          final fill = fillAttribute == null ? null : int.parse(fillAttribute);
          if (fill != null && (fill < -1 || fill > 255)) {
            throw FormatException('Invalid stroke fill: $fill');
          }
          content[int.parse(strokeElement.getAttribute('counter')!)] =
              XppStroke.byTool(tool: tool, color: color, points: points)
                ..fill = fill == -1 ? null : fill;
        });

        layers.add(
          XppLayer(
            content:
                (content.entries.toList()
                      ..sort((a, b) => a.key.compareTo(b.key)))
                    .map((entry) => entry.value)
                    .toList(),
          ),
        );
      });
      pages.add(
        XppPage(background: background, layers: layers, pageSize: pageSize),
      );
    });

    XppFile file = XppFile(
      title: title,
      previewImage: previewImage,
      pages: pages,
    );

    /*/// starting async task to save recent files list
    SharedPreferences.getInstance().then((prefs) {
      String jsonData = prefs.getString(PreferencesKeys.kRecentFiles) ?? '[]';
      Set files = (jsonDecode(jsonData) as Iterable).toSet();
      if (files.where((element) => element['path'] == rawFile.path).length < 1)
        files.add({
          'preview': base64Encode(file.previewImage),
          'name': file.title,
          'path': rawFile.path
        });
      jsonData = jsonEncode(files.toList());
      prefs.setString(PreferencesKeys.kRecentFiles, jsonData);
    });*/

    return file;
  }

  static Future<int> lastOpenedPageForPath(String? path) async {
    if (path == null || path.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    final jsonData = prefs.getString(PreferencesKeys.kRecentFiles);
    if (jsonData == null || jsonData.isEmpty) return 0;

    try {
      final files = jsonDecode(jsonData);
      if (files is! Iterable) return 0;
      for (final fileInfo in files) {
        if (fileInfo is! Map || fileInfo['path'] != path) continue;
        final currentPage = fileInfo['currentPage'];
        if (currentPage is int) return currentPage < 0 ? 0 : currentPage;
        return int.tryParse(currentPage?.toString() ?? '') ?? 0;
      }
    } catch (_) {
      return 0;
    }

    return 0;
  }

  /// thumbnail image data
  Uint8List? previewImage;

  /// [List] of [XppPages] inside the document
  List<XppPage>? pages;

  /// the main title of the document. usually the [String] between the last `/` and the last `.`.
  String? title;

  /// encoding the document to a [XmlDocument]
  XmlDocument toXmlDocument() {
    return XmlDocument([
      XmlElement(
        XmlName.parts('xournal'),
        [
          XmlAttribute(XmlName.parts('creator'), 'Xournal++ Mobile'),
          XmlAttribute(XmlName.parts('fileversion'), '4'),
        ],
        [
          XmlElement(XmlName.parts('title'), const [], [
            XmlText(
              'Xournal document - see http://math.mit.edu/~auroux/software/xournal/',
            ),
          ]),
          XmlElement(XmlName.parts('preview'), const [], [
            XmlText(base64Encode(previewImage!)),
          ]),
        ]..addAll(pages!.map((e) => e.toXmlElement())),
      ),
    ]);
  }

  String toXmlString() {
    return '<?xml version="1.0" standalone="no"?>' +
        toXmlDocument().toXmlString();
  }

  /// creating the XML-encoded, utf8-encoded and gzipped [Uint8List] to be used in a .xopp file
  Uint8List? toUint8List() {
    return GZipEncoder().encode(utf8.encode(toXmlString())) as Uint8List?;
  }

  /// Serialize a detached snapshot without sending renderer state or callbacks.
  Future<Uint8List> toUint8ListAsync() {
    final snapshot = XppFile(
      previewImage: previewImage == null
          ? kTransparentImage
          : Uint8List.fromList(previewImage!),
      pages: pages?.map((page) {
        final background = page.background;
        return XppPage(
          pageSize: page.pageSize,
          background: switch (background) {
            XppBackgroundPdf b => XppBackgroundPdf(
              onUnavailable: _unusedPdfRecovery,
              filename: b.filename,
              page: b.page,
              domain: b.domain,
            ),
            XppBackgroundSolidLined b => XppBackgroundSolidLined(
              color: b.color,
              size: b.size,
            ),
            XppBackgroundSolidRuled b => XppBackgroundSolidRuled(
              color: b.color,
              size: b.size,
            ),
            XppBackgroundSolidGraph b => XppBackgroundSolidGraph(
              color: b.color,
              size: b.size,
            ),
            XppBackgroundSolidDot b => XppBackgroundSolidDot(
              color: b.color,
              size: b.size,
            ),
            XppBackgroundSolidPlain b => XppBackgroundSolidPlain(
              color: b.color,
              size: b.size,
            ),
            _ => background,
          },
          layers: page.layers
              ?.map(
                (layer) => XppLayer(
                  content: layer.content?.map((content) {
                    if (content is XppStroke) {
                      return content.newStroke(
                        color: content.color,
                        points: content.points == null
                            ? null
                            : List.of(content.points!),
                      )..fill = content.fill;
                    }
                    if (content is XppImage) {
                      return XppImage(
                        data: content.data == null
                            ? null
                            : Uint8List.fromList(content.data!),
                        topLeft: content.topLeft,
                        bottomRight: content.bottomRight,
                      );
                    }
                    if (content is XppTexImage) {
                      return XppTexImage(
                        text: content.text,
                        topLeft: content.topLeft,
                        bottomRight: content.bottomRight,
                        color: content.color,
                      );
                    }
                    return content;
                  }).toList(),
                ),
              )
              .toList(),
        );
      }).toList(),
    );
    return compute(_encodeNotebook, snapshot, debugLabel: 'save xopp');
  }

  static Uint8List _encodeNotebook(XppFile file) => file.toUint8List()!;

  /// creating a [XppPickedFile] from the [toUint8List]
  XppPickedFile toXppPickedFile({String? filePath}) {
    Uint8List bytes = toUint8List()!;
    return XppPickedFile(bytes, fileExtension: 'xopp', path: filePath);
  }

  static String _decodePathForFileName(String path) {
    try {
      return Uri.decodeFull(path);
    } on FormatException {
      return path;
    }
  }
}

Color parseColor(String? colorString) {
  Color color = Colors.black;
  if (colorString != null) {
    switch (colorString) {
      case "black":
        break;
      case "blue":
        color = Colors.blue;
        break;
      case "red":
        color = Colors.red;
        break;
      case "green":
        color = Colors.green;
        break;
      case "gray":
      case "grey":
        color = Colors.grey;
        break;
      case "lightblue":
        color = Colors.lightBlue;
        break;
      case "lightgreen":
        color = Colors.lightGreen;
        break;
      case "magenta":
        color = Colors.purpleAccent;
        break;
      case "orange":
        color = Colors.orange;
        break;
      case "yellow":
        color = Colors.yellow;
        break;
      case "white":
        color = Colors.white;
        break;
      default:
        color = HexColor(colorString);
        break;
    }
  }
  return color;
}
