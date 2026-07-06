import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:xournalpp/layer_contents/XppImage.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/layer_contents/XppTexImage.dart';
import 'package:xournalpp/layer_contents/XppText.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/XppPickedFile.dart';

class PdfExportException implements Exception {
  final String message;

  const PdfExportException(this.message);

  @override
  String toString() => message;
}

typedef PdfSourceResolver =
    Future<XppPickedFile> Function(XppBackgroundPdf background);

Future<Uint8List> exportPdfDocument(
  XppFile file, {
  PdfSourceResolver? pdfResolver,
}) async {
  final source = _pdfSourceFor(file);
  if (source == null) {
    throw const PdfExportException(
      'PDF export currently requires all pages to come from the same PDF.',
    );
  }

  final pickedPdf = pdfResolver == null
      ? await XppPickedFile.fromInternalPath(path: source.filename)
      : await pdfResolver(source.background);
  final writer = _IncrementalPdfWriter(pickedPdf.toUint8List());
  return writer.export(file: file, source: source);
}

_PdfSource? _pdfSourceFor(XppFile file) {
  final pages = file.pages;
  if (pages == null || pages.isEmpty) return null;

  String? filename;
  XppBackgroundPdf? sourceBackground;
  final pageNumbers = <int>[];
  for (final page in pages) {
    final background = page.background;
    if (background is! XppBackgroundPdf) return null;
    if (background.filename == null || background.page == null) return null;
    filename ??= background.filename;
    sourceBackground ??= background;
    if (filename != background.filename) return null;
    pageNumbers.add(background.page!);
  }

  return _PdfSource(
    filename: filename!,
    background: sourceBackground!,
    pageNumbers: pageNumbers,
  );
}

class _PdfSource {
  final String filename;
  final XppBackgroundPdf background;
  final List<int> pageNumbers;

  const _PdfSource({
    required this.filename,
    required this.background,
    required this.pageNumbers,
  });
}

class _IncrementalPdfWriter {
  final Uint8List _bytes;
  late final String _text;
  late final Map<int, int> _offsets;
  late final Map<int, _CompressedObjectRef> _compressedObjectRefs;
  late final Map<String, String> _trailer;
  late final int _previousXrefOffset;
  late final int _maxObjectNumber;
  late final int _rootObject;
  late final List<_PdfPageInfo> _pages;
  final Map<int, _PdfObject> _objectCache = {};

  _IncrementalPdfWriter(this._bytes) {
    _text = latin1.decode(_bytes);
    _parseXref();
    if (_trailer.containsKey('Encrypt')) {
      throw const PdfExportException('Encrypted PDFs are not supported.');
    }
    _rootObject = _refNumber(_trailer['Root']);
    _pages = _loadPages();
  }

  Uint8List export({required XppFile file, required _PdfSource source}) {
    final pages = file.pages ?? <XppPage>[];
    final builder = StringBuffer();
    final newOffsets = <int, int>{};
    var nextObject = _maxObjectNumber + 1;

    int addObject(String body) {
      final objectNumber = nextObject++;
      newOffsets[objectNumber] =
          _bytes.length + latin1.encode(builder.toString()).length;
      builder.write('$objectNumber 0 obj\n$body\nendobj\n');
      return objectNumber;
    }

    final fontObject = addObject(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    );
    final alphaObject = addObject('<< /Type /ExtGState /CA 0.5 /ca 0.5 >>');

    for (var i = 0; i < pages.length; i++) {
      final sourcePageIndex = source.pageNumbers[i] - 1;
      if (sourcePageIndex < 0 || sourcePageIndex >= _pages.length) {
        throw PdfExportException(
          'PDF page ${source.pageNumbers[i]} is not available.',
        );
      }

      final pageInfo = _pages[sourcePageIndex];
      final imageObjects = <String, int>{};
      final overlay = _OverlayBuilder(
        page: pages[i],
        mediaBox: pageInfo.mediaBox,
        addImageObject: (image) {
          final name = 'FXPIm${imageObjects.length + 1}';
          final imageObject = addObject(_imageObject(image));
          imageObjects[name] = imageObject;
          return name;
        },
      ).build();
      if (overlay.trim().isEmpty) continue;

      final streamObject = addObject(_streamObject(overlay));
      final resourceObject = addObject(
        _mergedResources(
          pageInfo.resourceDictionary,
          fontObject: fontObject,
          alphaObject: alphaObject,
          imageObjects: imageObjects,
        ),
      );
      final updatedPage = _updatedPageObject(
        pageInfo: pageInfo,
        newContentsObject: streamObject,
        newResourcesObject: resourceObject,
      );

      newOffsets[pageInfo.objectNumber] =
          _bytes.length + latin1.encode(builder.toString()).length;
      builder.write('${pageInfo.objectNumber} 0 obj\n$updatedPage\nendobj\n');
    }

    final xrefOffset = _bytes.length + latin1.encode(builder.toString()).length;
    builder.write('xref\n');
    final sortedObjects = newOffsets.keys.toList()..sort();
    for (final objectNumber in sortedObjects) {
      builder.write('$objectNumber 1\n');
      builder.write(
        '${newOffsets[objectNumber]!.toString().padLeft(10, '0')} 00000 n \n',
      );
    }
    builder.write('trailer\n');
    final trailerEntries = {
      'Size': '${max(nextObject, _maxObjectNumber + 1)}',
      'Root': '$_rootObject 0 R',
      if (_trailer['Info'] != null) 'Info': _trailer['Info']!,
      if (_trailer['ID'] != null) 'ID': _trailer['ID']!,
      'Prev': '$_previousXrefOffset',
    };
    builder.write('<< ');
    trailerEntries.forEach((key, value) => builder.write('/$key $value '));
    builder.write('>>\n');
    builder.write('startxref\n$xrefOffset\n%%EOF\n');

    return Uint8List.fromList([
      ..._bytes,
      ...latin1.encode(builder.toString()),
    ]);
  }

  void _parseXref() {
    final startxrefMatch = RegExp(
      r'startxref\s+(\d+)\s+%%EOF\s*$',
      dotAll: true,
    ).firstMatch(_text);
    if (startxrefMatch == null) {
      throw const PdfExportException('Could not find PDF startxref.');
    }
    _previousXrefOffset = int.parse(startxrefMatch.group(1)!);

    _offsets = {};
    _compressedObjectRefs = {};
    var maxObject = 0;
    _trailer = _parseXrefSectionAt(
      _previousXrefOffset,
      visitedOffsets: <int>{},
      onObject: (objectNumber, offset) {
        _offsets[objectNumber] = offset;
        _compressedObjectRefs.remove(objectNumber);
        maxObject = max(maxObject, objectNumber);
      },
      onCompressedObject: (objectNumber, ref) {
        _compressedObjectRefs[objectNumber] = ref;
        _offsets.remove(objectNumber);
        maxObject = max(maxObject, objectNumber);
      },
      onFreeObject: (objectNumber) {
        _offsets.remove(objectNumber);
        _compressedObjectRefs.remove(objectNumber);
        maxObject = max(maxObject, objectNumber);
      },
    );
    final trailerSize = int.tryParse(_trailer['Size'] ?? '');
    _maxObjectNumber = max(
      maxObject,
      trailerSize == null ? 0 : trailerSize - 1,
    );
  }

  Map<String, String> _parseXrefSectionAt(
    int xrefOffset, {
    required Set<int> visitedOffsets,
    required void Function(int objectNumber, int offset) onObject,
    required void Function(int objectNumber, _CompressedObjectRef ref)
    onCompressedObject,
    required void Function(int objectNumber) onFreeObject,
  }) {
    if (!visitedOffsets.add(xrefOffset)) {
      throw const PdfExportException('Cyclic PDF xref chain.');
    }
    if (!_text.startsWith('xref', xrefOffset)) {
      return _parseXrefStreamAt(
        xrefOffset,
        visitedOffsets: visitedOffsets,
        onObject: onObject,
        onCompressedObject: onCompressedObject,
        onFreeObject: onFreeObject,
      );
    }

    final trailerIndex = _text.indexOf('trailer', xrefOffset);
    if (trailerIndex < 0)
      throw const PdfExportException('Could not find PDF trailer.');

    final localOffsets = <int, int>{};
    final localFreeObjects = <int>{};
    final lines = _text
        .substring(xrefOffset + 4, trailerIndex)
        .split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      final header = RegExp(r'^\s*(\d+)\s+(\d+)\s*$').firstMatch(lines[i]);
      if (header == null) continue;
      final first = int.parse(header.group(1)!);
      final count = int.parse(header.group(2)!);
      for (var j = 0; j < count && i + 1 < lines.length; j++) {
        final entry = lines[++i];
        if (entry.length < 18) continue;
        final objectNumber = first + j;
        if (entry.substring(17, 18) == 'n') {
          localOffsets[objectNumber] = int.parse(entry.substring(0, 10));
          localFreeObjects.remove(objectNumber);
        } else if (entry.substring(17, 18) == 'f') {
          localOffsets.remove(objectNumber);
          localFreeObjects.add(objectNumber);
        }
      }
    }

    final trailerStart = _text.indexOf('<<', trailerIndex);
    final trailerEnd = _matchingDictionaryEnd(_text, trailerStart);
    final trailer = _dictionaryEntries(
      _text.substring(trailerStart, trailerEnd),
    );
    final previousXrefOffset = _integerValue(trailer['Prev']);
    final previousTrailer = previousXrefOffset == null
        ? <String, String>{}
        : _parseXrefSectionAt(
            previousXrefOffset,
            visitedOffsets: visitedOffsets,
            onObject: onObject,
            onCompressedObject: onCompressedObject,
            onFreeObject: onFreeObject,
          );

    localFreeObjects.forEach(onFreeObject);
    localOffsets.forEach(onObject);
    return {...previousTrailer, ...trailer};
  }

  Map<String, String> _parseXrefStreamAt(
    int xrefOffset, {
    required Set<int> visitedOffsets,
    required void Function(int objectNumber, int offset) onObject,
    required void Function(int objectNumber, _CompressedObjectRef ref)
    onCompressedObject,
    required void Function(int objectNumber) onFreeObject,
  }) {
    final xrefObject = _objectAtOffset(offset: xrefOffset);
    final trailer = _dictionaryEntries(xrefObject.dictionary);
    if (trailer['Type'] != '/XRef') {
      throw const PdfExportException('Unsupported PDF xref structure.');
    }

    final previousXrefOffset = _integerValue(trailer['Prev']);
    final previousTrailer = previousXrefOffset == null
        ? <String, String>{}
        : _parseXrefSectionAt(
            previousXrefOffset,
            visitedOffsets: visitedOffsets,
            onObject: onObject,
            onCompressedObject: onCompressedObject,
            onFreeObject: onFreeObject,
          );

    final w = _integersInValue(trailer['W']);
    if (w.length != 3) {
      throw const PdfExportException('Invalid PDF xref stream width table.');
    }
    final entryWidth = w.fold<int>(0, (sum, width) => sum + width);
    if (entryWidth == 0) {
      throw const PdfExportException('Invalid PDF xref stream entry width.');
    }

    final index = _integersInValue(trailer['Index']);
    final ranges = index.isEmpty
        ? <int>[0, _integerValue(trailer['Size']) ?? 0]
        : index;
    if (ranges.length.isOdd) {
      throw const PdfExportException('Invalid PDF xref stream index.');
    }

    final data = _decodedStreamBytes(xrefObject);
    var dataOffset = 0;
    for (var rangeOffset = 0; rangeOffset < ranges.length; rangeOffset += 2) {
      final firstObject = ranges[rangeOffset];
      final count = ranges[rangeOffset + 1];
      for (var i = 0; i < count; i++) {
        if (dataOffset + entryWidth > data.length) {
          throw const PdfExportException('Truncated PDF xref stream.');
        }
        final type = w[0] == 0 ? 1 : _bigEndianInteger(data, dataOffset, w[0]);
        dataOffset += w[0];
        final field2 = _bigEndianInteger(data, dataOffset, w[1]);
        dataOffset += w[1];
        final field3 = _bigEndianInteger(data, dataOffset, w[2]);
        dataOffset += w[2];

        final objectNumber = firstObject + i;
        if (type == 0) {
          onFreeObject(objectNumber);
        } else if (type == 1) {
          onObject(objectNumber, field2);
        } else if (type == 2) {
          onCompressedObject(
            objectNumber,
            _CompressedObjectRef(
              objectStreamObjectNumber: field2,
              objectIndex: field3,
            ),
          );
        } else {
          throw PdfExportException('Unsupported PDF xref entry type $type.');
        }
      }
    }

    return {...previousTrailer, ...trailer};
  }

  List<_PdfPageInfo> _loadPages() {
    final root = _object(_rootObject);
    final catalog = _dictionaryEntries(root.dictionary);
    final pagesRoot = _refNumber(catalog['Pages']);
    final result = <_PdfPageInfo>[];
    _walkPageTree(pagesRoot, result, inheritedResources: null);
    return result;
  }

  void _walkPageTree(
    int objectNumber,
    List<_PdfPageInfo> pages, {
    String? inheritedResources,
  }) {
    final object = _object(objectNumber);
    final dict = _dictionaryEntries(object.dictionary);
    final type = dict['Type'];
    final resources = dict['Resources'] ?? inheritedResources;
    if (type == '/Page') {
      final rotate = int.tryParse(dict['Rotate'] ?? '0') ?? 0;
      if (rotate != 0)
        throw const PdfExportException('Rotated PDF pages are not supported.');
      final mediaBox = _parseBox(dict['CropBox'] ?? dict['MediaBox']);
      if (mediaBox == null)
        throw const PdfExportException('PDF page is missing MediaBox.');
      pages.add(
        _PdfPageInfo(
          objectNumber: objectNumber,
          dictionary: object.dictionary,
          entries: dict,
          mediaBox: mediaBox,
          resourceDictionary: _resourceDictionary(resources),
        ),
      );
      return;
    }

    if (type != '/Pages') return;
    final kids = _refsInArray(dict['Kids']);
    for (final kid in kids) {
      _walkPageTree(kid, pages, inheritedResources: resources);
    }
  }

  _PdfObject _object(int objectNumber) {
    return _objectCache.putIfAbsent(objectNumber, () {
      final offset = _offsets[objectNumber];
      if (offset != null) {
        return _objectAtOffset(
          offset: offset,
          expectedObjectNumber: objectNumber,
        );
      }

      final compressedRef = _compressedObjectRefs[objectNumber];
      if (compressedRef != null) {
        return _objectFromObjectStream(objectNumber, compressedRef);
      }

      throw PdfExportException('Missing PDF object $objectNumber.');
    });
  }

  _PdfObject _objectAtOffset({required int offset, int? expectedObjectNumber}) {
    final header = RegExp(
      r'^(\d+)\s+\d+\s+obj\s*',
    ).matchAsPrefix(_text.substring(offset));
    if (header == null) throw const PdfExportException('Invalid PDF object.');
    final objectNumber = int.parse(header.group(1)!);
    if (expectedObjectNumber != null && objectNumber != expectedObjectNumber) {
      throw PdfExportException('Invalid PDF object $expectedObjectNumber.');
    }
    final start = offset + header.end;
    final end = _text.indexOf('endobj', start);
    if (end < 0)
      throw PdfExportException('Unterminated PDF object $objectNumber.');
    final body = _text.substring(start, end).trim();
    final dictStart = body.indexOf('<<');
    if (dictStart < 0) {
      throw PdfExportException('PDF object $objectNumber is not a dictionary.');
    }
    final dictEnd = _matchingDictionaryEnd(body, dictStart);
    return _PdfObject(
      body: body,
      dictionary: body.substring(dictStart, dictEnd),
    );
  }

  _PdfObject _objectFromObjectStream(
    int objectNumber,
    _CompressedObjectRef ref,
  ) {
    final objectStream = _object(ref.objectStreamObjectNumber);
    final objectStreamDictionary = _dictionaryEntries(objectStream.dictionary);
    if (objectStreamDictionary['Type'] != '/ObjStm') {
      throw PdfExportException(
        'PDF object stream ${ref.objectStreamObjectNumber} is invalid.',
      );
    }
    final count = _integerValue(objectStreamDictionary['N']);
    final first = _integerValue(objectStreamDictionary['First']);
    if (count == null || first == null || ref.objectIndex >= count) {
      throw PdfExportException(
        'PDF object $objectNumber has an invalid object stream reference.',
      );
    }

    final streamText = latin1.decode(_decodedStreamBytes(objectStream));
    if (first < 0 || first > streamText.length) {
      throw const PdfExportException('Invalid PDF object stream.');
    }
    final header = streamText.substring(0, first);
    final headerNumbers = _integersInValue(header);
    if (headerNumbers.length < count * 2) {
      throw const PdfExportException('Invalid PDF object stream header.');
    }

    final indexedObjectNumber = headerNumbers[ref.objectIndex * 2];
    if (indexedObjectNumber != objectNumber) {
      throw PdfExportException('Invalid compressed PDF object $objectNumber.');
    }
    final objectOffset = headerNumbers[ref.objectIndex * 2 + 1];
    final nextObjectOffset = ref.objectIndex + 1 < count
        ? headerNumbers[(ref.objectIndex + 1) * 2 + 1]
        : streamText.length - first;
    final bodyStart = first + objectOffset;
    final bodyEnd = first + nextObjectOffset;
    if (bodyStart < first ||
        bodyEnd < bodyStart ||
        bodyEnd > streamText.length) {
      throw const PdfExportException('Invalid PDF object stream offsets.');
    }

    final body = streamText.substring(bodyStart, bodyEnd).trim();
    final dictStart = body.indexOf('<<');
    if (dictStart < 0) {
      throw PdfExportException('PDF object $objectNumber is not a dictionary.');
    }
    final dictEnd = _matchingDictionaryEnd(body, dictStart);
    return _PdfObject(
      body: body,
      dictionary: body.substring(dictStart, dictEnd),
    );
  }

  Uint8List _decodedStreamBytes(_PdfObject object) {
    final entries = _dictionaryEntries(object.dictionary);
    var data = _rawStreamBytes(object, entries);
    final filter = entries['Filter'];
    if (filter == null) return data;

    final filters = _filterNames(filter);
    for (final filterName in filters) {
      if (filterName == 'FlateDecode' || filterName == 'Fl') {
        data = Uint8List.fromList(const ZLibDecoder().decodeBytes(data));
      } else {
        throw PdfExportException('Unsupported PDF stream filter /$filterName.');
      }
    }

    return _applyDecodeParameters(
      data,
      entries['DecodeParms'] ?? entries['DP'],
    );
  }

  Uint8List _rawStreamBytes(_PdfObject object, Map<String, String> entries) {
    final streamIndex = object.body.indexOf('stream', object.dictionary.length);
    if (streamIndex < 0) {
      throw const PdfExportException('PDF object stream data is missing.');
    }
    var dataStart = streamIndex + 'stream'.length;
    if (object.body.startsWith('\r\n', dataStart)) {
      dataStart += 2;
    } else if (object.body.startsWith('\n', dataStart) ||
        object.body.startsWith('\r', dataStart)) {
      dataStart += 1;
    }

    final dataLength = _integerValue(entries['Length']);
    if (dataLength != null) {
      final dataEnd = dataStart + dataLength;
      if (dataEnd > object.body.length) {
        throw const PdfExportException('Invalid PDF stream length.');
      }
      return Uint8List.fromList(
        latin1.encode(object.body.substring(dataStart, dataEnd)),
      );
    }

    var dataEnd = object.body.indexOf('endstream', dataStart);
    if (dataEnd < 0) {
      throw const PdfExportException('Unterminated PDF stream.');
    }
    if (dataEnd > dataStart && object.body.codeUnitAt(dataEnd - 1) == 0x0a) {
      dataEnd--;
      if (dataEnd > dataStart && object.body.codeUnitAt(dataEnd - 1) == 0x0d) {
        dataEnd--;
      }
    } else if (dataEnd > dataStart &&
        object.body.codeUnitAt(dataEnd - 1) == 0x0d) {
      dataEnd--;
    }
    return Uint8List.fromList(
      latin1.encode(object.body.substring(dataStart, dataEnd)),
    );
  }

  String? _resourceDictionary(String? resources) {
    if (resources == null) return null;
    if (resources.startsWith('<<')) return resources;
    final ref = RegExp(r'^(\d+)\s+\d+\s+R$').firstMatch(resources.trim());
    if (ref == null) return null;
    return _object(int.parse(ref.group(1)!)).dictionary;
  }

  String _mergedResources(
    String? oldResources, {
    required int fontObject,
    required int alphaObject,
    required Map<String, int> imageObjects,
  }) {
    final entries = oldResources == null
        ? <String, String>{}
        : Map<String, String>.from(_dictionaryEntries(oldResources));
    entries['Font'] = _mergedSubDictionary(entries['Font'], {
      'FXPHelvetica': '$fontObject 0 R',
    });
    entries['ExtGState'] = _mergedSubDictionary(entries['ExtGState'], {
      'FXPHighlight': '$alphaObject 0 R',
    });
    if (imageObjects.isNotEmpty) {
      entries['XObject'] = _mergedSubDictionary(
        entries['XObject'],
        imageObjects.map((key, value) => MapEntry(key, '$value 0 R')),
      );
    }

    final buffer = StringBuffer('<< ');
    entries.forEach((key, value) => buffer.write('/$key $value '));
    buffer.write('>>');
    return buffer.toString();
  }

  String _mergedSubDictionary(String? original, Map<String, String> additions) {
    final entries = <String, String>{};
    final dictionary = _directDictionary(original);
    if (dictionary != null) entries.addAll(_dictionaryEntries(dictionary));
    additions.forEach((key, value) => entries[key] = value);

    final buffer = StringBuffer('<< ');
    entries.forEach((key, value) => buffer.write('/$key $value '));
    buffer.write('>>');
    return buffer.toString();
  }

  String? _directDictionary(String? value) {
    if (value == null) return null;
    if (value.trim().startsWith('<<')) return value.trim();
    final ref = RegExp(r'^(\d+)\s+\d+\s+R$').firstMatch(value.trim());
    if (ref == null) return null;
    return _object(int.parse(ref.group(1)!)).dictionary;
  }

  String _updatedPageObject({
    required _PdfPageInfo pageInfo,
    required int newContentsObject,
    required int newResourcesObject,
  }) {
    var dict = pageInfo.dictionary;
    final contents = pageInfo.entries['Contents'];
    if (contents != null && contents.startsWith('<<')) {
      throw const PdfExportException(
        'Direct page content streams are not supported.',
      );
    }
    final newContents = contents == null
        ? '$newContentsObject 0 R'
        : contents.startsWith('[')
        ? '${contents.substring(0, contents.length - 1)} $newContentsObject 0 R ]'
        : '[ $contents $newContentsObject 0 R ]';

    dict = _replaceDictionaryEntry(dict, 'Contents', newContents);
    dict = _replaceDictionaryEntry(
      dict,
      'Resources',
      '$newResourcesObject 0 R',
    );
    return dict;
  }

  String _streamObject(String data) {
    final bytes = latin1.encode(data);
    return '<< /Length ${bytes.length} >>\nstream\n$data\nendstream';
  }

  String _imageObject(_PdfImage image) {
    return '<< /Type /XObject /Subtype /Image /Width ${image.width} /Height ${image.height} '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Length ${image.rgb.length} >>\n'
        'stream\n${latin1.decode(image.rgb)}\nendstream';
  }
}

class _OverlayBuilder {
  final XppPage page;
  final _PdfBox mediaBox;
  final String Function(_PdfImage image) addImageObject;

  _OverlayBuilder({
    required this.page,
    required this.mediaBox,
    required this.addImageObject,
  });

  String build() {
    final buffer = StringBuffer()..writeln('q');
    final pageSize = page.pageSize!.toSize();
    final scaleX = mediaBox.width / pageSize.width;
    final scaleY = mediaBox.height / pageSize.height;
    for (final layer in page.layers ?? <XppLayer>[]) {
      for (final content in layer.content ?? <XppContent?>[]) {
        if (content == null) continue;
        _drawContent(buffer, content, scaleX: scaleX, scaleY: scaleY);
      }
    }
    buffer.writeln('Q');
    return buffer.toString();
  }

  void _drawContent(
    StringBuffer buffer,
    XppContent content, {
    required double scaleX,
    required double scaleY,
  }) {
    if (content is XppStroke) {
      _drawStroke(buffer, content, scaleX: scaleX, scaleY: scaleY);
    } else if (content is XppImage) {
      _drawImage(buffer, content, scaleX: scaleX, scaleY: scaleY);
    } else if (content is XppText) {
      _drawText(
        buffer,
        content.text,
        content.offset,
        content.size,
        content.color,
        scaleX: scaleX,
        scaleY: scaleY,
      );
    } else if (content is XppTexImage) {
      _drawText(
        buffer,
        content.text,
        content.topLeft,
        18,
        content.color,
        scaleX: scaleX,
        scaleY: scaleY,
      );
    }
  }

  void _drawStroke(
    StringBuffer buffer,
    XppStroke stroke, {
    required double scaleX,
    required double scaleY,
  }) {
    final points = stroke.points;
    if (points == null || points.isEmpty) return;
    final color = stroke.tool == XppStrokeTool.ERASER
        ? const Color(0xffffffff)
        : stroke.color ?? const Color(0xff000000);
    buffer.writeln('q');
    if (stroke.tool == XppStrokeTool.HIGHLIGHTER)
      buffer.writeln('/FXPHighlight gs');
    buffer.writeln('${_rgb(color)} RG ${_rgb(color)} rg 1 J 1 j');
    if (points.length == 1) {
      final point = points.first;
      final radius = (point.width ?? 1) / 2;
      buffer.writeln(
        '${_n(_x(point.x!, scaleX) - radius)} ${_n(_y(point.y!, scaleY) - radius)} ${_n(radius * 2)} ${_n(radius * 2)} re f',
      );
    } else if (stroke.tool == XppStrokeTool.PEN) {
      for (var i = 1; i < points.length; i++) {
        final start = points[i - 1];
        final end = points[i];
        buffer.writeln(
          '${_n((end.width ?? 1) * ((scaleX + scaleY) / 2))} w '
          '${_n(_x(start.x!, scaleX))} ${_n(_y(start.y!, scaleY))} m '
          '${_n(_x(end.x!, scaleX))} ${_n(_y(end.y!, scaleY))} l S',
        );
      }
    } else {
      final width =
          points.fold<double>(0, (sum, point) => sum + (point.width ?? 1)) /
          points.length;
      buffer.write(
        '${_n(width * ((scaleX + scaleY) / 2))} w '
        '${_n(_x(points.first.x!, scaleX))} ${_n(_y(points.first.y!, scaleY))} m ',
      );
      for (final point in points.skip(1)) {
        buffer.write(
          '${_n(_x(point.x!, scaleX))} ${_n(_y(point.y!, scaleY))} l ',
        );
      }
      buffer.writeln('S');
    }
    buffer.writeln('Q');
  }

  void _drawImage(
    StringBuffer buffer,
    XppImage image, {
    required double scaleX,
    required double scaleY,
  }) {
    final data = image.data;
    final topLeft = image.topLeft;
    final bottomRight = image.bottomRight;
    if (data == null || topLeft == null || bottomRight == null) return;
    final decoded = img.decodeImage(data);
    if (decoded == null) return;
    final rgb = Uint8List(decoded.width * decoded.height * 3);
    var offset = 0;
    for (final pixel in decoded) {
      rgb[offset++] = pixel.r.toInt();
      rgb[offset++] = pixel.g.toInt();
      rgb[offset++] = pixel.b.toInt();
    }
    final name = addImageObject(
      _PdfImage(width: decoded.width, height: decoded.height, rgb: rgb),
    );
    final width = bottomRight.dx - topLeft.dx;
    final height = bottomRight.dy - topLeft.dy;
    buffer.writeln(
      'q ${_n(width * scaleX)} 0 0 ${_n(height * scaleY)} '
      '${_n(_x(topLeft.dx, scaleX))} ${_n(_y(bottomRight.dy, scaleY))} cm /$name Do Q',
    );
  }

  void _drawText(
    StringBuffer buffer,
    String? text,
    Offset? offset,
    double? size,
    Color? color, {
    required double scaleX,
    required double scaleY,
  }) {
    if (text == null || text.isEmpty || offset == null) return;
    final fontSize = size ?? 18;
    final fill = color ?? const Color(0xff000000);
    buffer.writeln(
      'q BT ${_rgb(fill)} rg /FXPHelvetica ${_n(fontSize * ((scaleX + scaleY) / 2))} Tf '
      '1 0 0 1 ${_n(_x(offset.dx, scaleX))} ${_n(_y(offset.dy + fontSize, scaleY))} Tm '
      '(${_escapePdfString(_latinPdfText(text))}) Tj ET Q',
    );
  }

  double _x(double x, double scaleX) => mediaBox.left + x * scaleX;

  double _y(double y, double scaleY) => mediaBox.top - y * scaleY;
}

class _PdfObject {
  final String body;
  final String dictionary;

  const _PdfObject({required this.body, required this.dictionary});
}

class _PdfPageInfo {
  final int objectNumber;
  final String dictionary;
  final Map<String, String> entries;
  final _PdfBox mediaBox;
  final String? resourceDictionary;

  const _PdfPageInfo({
    required this.objectNumber,
    required this.dictionary,
    required this.entries,
    required this.mediaBox,
    required this.resourceDictionary,
  });
}

class _PdfBox {
  final double left;
  final double bottom;
  final double right;
  final double top;

  const _PdfBox(this.left, this.bottom, this.right, this.top);

  double get width => right - left;
  double get height => top - bottom;
}

class _PdfImage {
  final int width;
  final int height;
  final Uint8List rgb;

  const _PdfImage({
    required this.width,
    required this.height,
    required this.rgb,
  });
}

class _CompressedObjectRef {
  final int objectStreamObjectNumber;
  final int objectIndex;

  const _CompressedObjectRef({
    required this.objectStreamObjectNumber,
    required this.objectIndex,
  });
}

int _matchingDictionaryEnd(String text, int start) {
  var depth = 0;
  for (var i = start; i < text.length - 1; i++) {
    if (text.codeUnitAt(i) == 0x25) {
      while (i < text.length &&
          text.codeUnitAt(i) != 0x0a &&
          text.codeUnitAt(i) != 0x0d) {
        i++;
      }
      continue;
    }
    if (text.substring(i, i + 2) == '<<') {
      depth++;
      i++;
    } else if (text.substring(i, i + 2) == '>>') {
      depth--;
      i++;
      if (depth == 0) return i + 1;
    }
  }
  throw const PdfExportException('Unterminated PDF dictionary.');
}

Map<String, String> _dictionaryEntries(String dictionary) {
  final inner = dictionary
      .trim()
      .replaceFirst('<<', '')
      .replaceFirst(RegExp(r'>>$'), '');
  final entries = <String, String>{};
  var i = 0;
  while (i < inner.length) {
    i = _skipWhitespace(inner, i);
    if (i >= inner.length) break;
    if (inner.codeUnitAt(i) != 0x2f) {
      i++;
      continue;
    }
    final keyStart = ++i;
    while (i < inner.length && !_isDelimiter(inner.codeUnitAt(i))) {
      i++;
    }
    final key = inner.substring(keyStart, i);
    i = _skipWhitespace(inner, i);
    final valueStart = i;
    i = _skipValue(inner, i);
    entries[key] = inner.substring(valueStart, i).trim();
  }
  return entries;
}

int _skipValue(String text, int index) {
  index = _skipWhitespace(text, index);
  if (index >= text.length) return index;
  if (text.startsWith('<<', index)) return _matchingDictionaryEnd(text, index);
  final code = text.codeUnitAt(index);
  if (code == 0x5b) return _skipBalanced(text, index, 0x5b, 0x5d);
  if (code == 0x28) return _skipBalanced(text, index, 0x28, 0x29);
  if (code == 0x2f) {
    index++;
    while (index < text.length && !_isDelimiter(text.codeUnitAt(index))) {
      index++;
    }
    return index;
  }
  while (index < text.length && !_isDelimiter(text.codeUnitAt(index))) {
    index++;
  }
  final afterFirst = _skipWhitespace(text, index);
  final numberRef = RegExp(
    r'^\d+\s+R',
  ).matchAsPrefix(text.substring(afterFirst));
  if (numberRef != null) return afterFirst + numberRef.end;
  return index;
}

int _skipBalanced(String text, int index, int open, int close) {
  var depth = 0;
  var escaped = false;
  for (var i = index; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if (open == 0x28 && escaped) {
      escaped = false;
      continue;
    }
    if (open == 0x28 && code == 0x5c) {
      escaped = true;
      continue;
    }
    if (code == open) depth++;
    if (code == close) {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return text.length;
}

int _skipWhitespace(String text, int index) {
  while (index < text.length && RegExp(r'\s').hasMatch(text[index])) {
    index++;
  }
  return index;
}

bool _isDelimiter(int code) {
  return code <= 0x20 ||
      code == 0x2f ||
      code == 0x3c ||
      code == 0x3e ||
      code == 0x5b ||
      code == 0x5d ||
      code == 0x28 ||
      code == 0x29;
}

int _refNumber(String? value) {
  final match = RegExp(r'^(\d+)\s+\d+\s+R$').firstMatch(value?.trim() ?? '');
  if (match == null)
    throw const PdfExportException('Expected an indirect PDF reference.');
  return int.parse(match.group(1)!);
}

int? _integerValue(String? value) {
  final match = RegExp(r'^\d+$').firstMatch(value?.trim() ?? '');
  return match == null ? null : int.parse(match.group(0)!);
}

List<int> _integersInValue(String? value) {
  if (value == null) return const [];
  return RegExp(
    r'-?\d+',
  ).allMatches(value).map((match) => int.parse(match.group(0)!)).toList();
}

int _bigEndianInteger(Uint8List bytes, int offset, int width) {
  var value = 0;
  for (var i = 0; i < width; i++) {
    value = (value << 8) | bytes[offset + i];
  }
  return value;
}

List<String> _filterNames(String value) {
  return RegExp(
    r'/([A-Za-z0-9]+)',
  ).allMatches(value).map((match) => match.group(1)!).toList();
}

Uint8List _applyDecodeParameters(Uint8List data, String? decodeParameters) {
  final entries = decodeParameters?.trim().startsWith('<<') == true
      ? _dictionaryEntries(decodeParameters!)
      : <String, String>{};
  final predictor = _integerValue(entries['Predictor']) ?? 1;
  if (predictor == 1) return data;

  final columns = _integerValue(entries['Columns']);
  if (columns == null || columns <= 0) {
    throw const PdfExportException('Invalid PDF predictor columns.');
  }
  final colors = _integerValue(entries['Colors']) ?? 1;
  final bitsPerComponent = _integerValue(entries['BitsPerComponent']) ?? 8;
  if (colors != 1 || bitsPerComponent != 8) {
    throw const PdfExportException('Unsupported PDF predictor parameters.');
  }

  if (predictor == 2) return _applyTiffPredictor(data, columns);
  if (predictor >= 10 && predictor <= 15) {
    return _applyPngPredictor(data, columns);
  }
  throw PdfExportException('Unsupported PDF predictor $predictor.');
}

Uint8List _applyTiffPredictor(Uint8List data, int columns) {
  final output = Uint8List.fromList(data);
  for (var row = 0; row < output.length; row += columns) {
    final rowEnd = min(row + columns, output.length);
    for (var i = row + 1; i < rowEnd; i++) {
      output[i] = (output[i] + output[i - 1]) & 0xff;
    }
  }
  return output;
}

Uint8List _applyPngPredictor(Uint8List data, int columns) {
  final rows = <int>[];
  var offset = 0;
  var previousRow = Uint8List(columns);
  while (offset < data.length) {
    final predictor = data[offset++];
    if (offset + columns > data.length) {
      throw const PdfExportException('Truncated PDF predictor data.');
    }
    final row = Uint8List.fromList(data.sublist(offset, offset + columns));
    offset += columns;
    for (var i = 0; i < columns; i++) {
      final left = i == 0 ? 0 : row[i - 1];
      final up = previousRow[i];
      final upperLeft = i == 0 ? 0 : previousRow[i - 1];
      if (predictor == 1) {
        row[i] = (row[i] + left) & 0xff;
      } else if (predictor == 2) {
        row[i] = (row[i] + up) & 0xff;
      } else if (predictor == 3) {
        row[i] = (row[i] + ((left + up) >> 1)) & 0xff;
      } else if (predictor == 4) {
        row[i] = (row[i] + _paethPredictor(left, up, upperLeft)) & 0xff;
      } else if (predictor != 0) {
        throw PdfExportException('Unsupported PNG predictor $predictor.');
      }
    }
    rows.addAll(row);
    previousRow = row;
  }
  return Uint8List.fromList(rows);
}

int _paethPredictor(int left, int up, int upperLeft) {
  final estimate = left + up - upperLeft;
  final leftDistance = (estimate - left).abs();
  final upDistance = (estimate - up).abs();
  final upperLeftDistance = (estimate - upperLeft).abs();
  if (leftDistance <= upDistance && leftDistance <= upperLeftDistance) {
    return left;
  }
  if (upDistance <= upperLeftDistance) return up;
  return upperLeft;
}

List<int> _refsInArray(String? value) {
  if (value == null) return const [];
  return RegExp(
    r'(\d+)\s+\d+\s+R',
  ).allMatches(value).map((match) => int.parse(match.group(1)!)).toList();
}

_PdfBox? _parseBox(String? value) {
  if (value == null) return null;
  final nums = RegExp(
    r'-?\d+(?:\.\d+)?',
  ).allMatches(value).map((match) => double.parse(match.group(0)!)).toList();
  if (nums.length < 4) return null;
  return _PdfBox(nums[0], nums[1], nums[2], nums[3]);
}

String _replaceDictionaryEntry(String dictionary, String key, String value) {
  final pattern = '/$key';
  final index = dictionary.indexOf(pattern);
  if (index < 0) {
    return '${dictionary.substring(0, dictionary.length - 2)} $pattern $value >>';
  }
  var valueStart = index + pattern.length;
  valueStart = _skipWhitespace(dictionary, valueStart);
  final valueEnd = _skipValue(dictionary, valueStart);
  return '${dictionary.substring(0, index + pattern.length)} $value${dictionary.substring(valueEnd)}';
}

String _rgb(Color color) {
  final argb = color.toARGB32();
  return '${_n(((argb >> 16) & 0xff) / 255)} ${_n(((argb >> 8) & 0xff) / 255)} ${_n((argb & 0xff) / 255)}';
}

String _n(num value) {
  final text = value.toStringAsFixed(4);
  return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

String _escapePdfString(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n');
}

String _latinPdfText(String value) {
  return String.fromCharCodes(
    value.codeUnits.map((codeUnit) => codeUnit <= 0xff ? codeUnit : 0x3f),
  );
}
