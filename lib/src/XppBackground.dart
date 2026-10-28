import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:async';

import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/src/HexColor.dart';
import 'package:xournalpp/src/PdfBackgroundRenderService.dart';

import 'XppPage.dart';
import 'RasterImageCache.dart';

abstract class XppBackground {
  XppBackgroundType? type;
  XppPageSize? size;

  static XppBackground get none => _NoXppBackground();

  Widget render({
    ValueChanged<bool>? onLoadingChanged,
    ValueListenable<bool>? deferRasterUpdates,
    double? targetPixelWidth,
    double? targetPixelHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
  });

  XmlElement toXmlElement();
}

/// page background for a [XppPage] made from an image URI. I am sure it will be hard to implement for web.
/// TODO: implement background for web
class XppBackgroundImage extends XppBackground {
  final String? filename;
  final XppBackgroundImageDomain domain;
  final XppBackgroundType? type;

  XppBackgroundImage({
    this.type,
    this.filename,
    this.domain = XppBackgroundImageDomain.ABSOLUTE,
  });

  @override
  Widget render({
    ValueChanged<bool>? onLoadingChanged,
    ValueListenable<bool>? deferRasterUpdates,
    double? targetPixelWidth,
    double? targetPixelHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
  }) {
    return Container(color: Colors.white);
  }

  @override
  XmlElement toXmlElement() {
    late String domainString;
    switch (domain) {
      case XppBackgroundImageDomain.ABSOLUTE:
        domainString = 'absolute';
        break;
      case XppBackgroundImageDomain.ATTACH:
        domainString = 'attach';
        break;
      case XppBackgroundImageDomain.CLONE:
        domainString = 'clone';
        break;
    }
    XmlElement node = XmlElement(XmlName.parts('background'), [
      XmlAttribute(XmlName.parts('type'), 'pixmap'),
      XmlAttribute(XmlName.parts('domain'), domainString),
      XmlAttribute(XmlName.parts('filename'), filename!),
    ]);
    return (node);
  }
}

typedef Future<XppPickedFile> FileNotAvailableCallback(
  BuildContext context,
  String? path,
);

/// page background for a [XppPage] made from a PDF document
class XppBackgroundPdf extends XppBackground {
  final String? filename;
  final XppBackgroundImageDomain domain;
  final int? page;
  final FileNotAvailableCallback onUnavailable;

  XppBackgroundPdf({
    required this.onUnavailable,
    this.page,
    this.filename,
    this.domain = XppBackgroundImageDomain.ABSOLUTE,
  });

  @override
  Widget render({
    ValueChanged<bool>? onLoadingChanged,
    ValueListenable<bool>? deferRasterUpdates,
    double? targetPixelWidth,
    double? targetPixelHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
  }) {
    final snappedSize = pdfBackgroundRenderService.renderSizeFor(
      PdfBackgroundRenderVariant.full,
      targetWidth: targetPixelWidth,
      targetHeight: targetPixelHeight,
      pageWidthPoints: pageWidthPoints,
      pageHeightPoints: pageHeightPoints,
    );
    return (PDfBackgroundWidget(
      provider: this,
      onLoadingChanged: onLoadingChanged,
      deferRasterUpdates: deferRasterUpdates,
      targetPixelWidth: snappedSize.width.toDouble(),
      targetPixelHeight: snappedSize.height.toDouble(),
      pageWidthPoints: pageWidthPoints,
      pageHeightPoints: pageHeightPoints,
    ));
  }

  @override
  XmlElement toXmlElement() {
    final attributes = [
      XmlAttribute(XmlName.parts('type'), 'pdf'),
      XmlAttribute(XmlName.parts('pageno'), page.toString()),
      XmlAttribute(XmlName.parts('domain'), 'absolute'),
      if (filename != null) XmlAttribute(XmlName.parts('filename'), filename!),
    ];
    XmlElement node = XmlElement(XmlName.parts('background'), attributes);
    return (node);
  }
}

/// Recovery belongs to the editor, whose context survives page virtualization.
class PdfSourceScope extends InheritedWidget {
  final Future<PdfBackgroundRenderSource> Function(XppBackgroundPdf) resolve;

  const PdfSourceScope({
    super.key,
    required this.resolve,
    required super.child,
  });

  @override
  bool updateShouldNotify(PdfSourceScope oldWidget) => false;
}

class PDfBackgroundWidget extends StatefulWidget {
  final XppBackgroundPdf? provider;
  final ValueChanged<bool>? onLoadingChanged;
  final ValueListenable<bool>? deferRasterUpdates;
  final double? targetPixelWidth;
  final double? targetPixelHeight;
  final double? pageWidthPoints;
  final double? pageHeightPoints;
  final PdfBackgroundRenderService? renderService;

  const PDfBackgroundWidget({
    Key? key,
    this.provider,
    this.onLoadingChanged,
    this.deferRasterUpdates,
    this.targetPixelWidth,
    this.targetPixelHeight,
    this.pageWidthPoints,
    this.pageHeightPoints,
    this.renderService,
  }) : super(key: key);
  @override
  _PDfBackgroundWidgetState createState() => _PDfBackgroundWidgetState();
}

class _PDfBackgroundWidgetState extends State<PDfBackgroundWidget> {
  StreamSubscription<PdfBackgroundRenderSnapshot>? _renderSubscription;
  Uint8List? _imageBytes;
  Uint8List? _deferredImageBytes;
  Object? _error;
  bool _isLoading = false;
  int _requestGeneration = 0;
  String? _subscribedKey;
  final Object _requestOwner = Object();
  PdfBackgroundRenderService get _service =>
      widget.renderService ?? pdfBackgroundRenderService;

  Future<PdfBackgroundRenderSource> _loadPdfSource(
    XppBackgroundPdf provider,
    int generation,
  ) async {
    final scope = context.getInheritedWidgetOfExactType<PdfSourceScope>();
    if (scope != null) return scope.resolve(provider);
    final filename = provider.filename;
    return _service.sourceForPath(
      filename,
      fallback: () => provider.onUnavailable(context, filename),
      isCurrent: () => mounted && generation == _requestGeneration,
    );
  }

  Future<void> _startLoading(
    XppBackgroundPdf provider, {
    bool preserveCurrentImage = false,
  }) async {
    final generation = ++_requestGeneration;
    _setLoading(true);
    setState(() {
      if (!preserveCurrentImage) _imageBytes = null;
      _error = null;
    });

    try {
      final source = await _loadPdfSource(provider, generation);
      if (!mounted || generation != _requestGeneration) return;

      final key = _service.keyFor(
        source,
        provider.page,
        PdfBackgroundRenderVariant.full,
        targetWidth: widget.targetPixelWidth,
        targetHeight: widget.targetPixelHeight,
        pageWidthPoints: widget.pageWidthPoints,
        pageHeightPoints: widget.pageHeightPoints,
      );
      _subscribeToKey(key, generation);

      final cached = _service.peek(key);
      if (cached != null) {
        _applyImage(cached);
        return;
      }

      final bytes = await _service.request(
        source,
        provider.page,
        PdfBackgroundRenderVariant.full,
        targetWidth: widget.targetPixelWidth,
        targetHeight: widget.targetPixelHeight,
        pageWidthPoints: widget.pageWidthPoints,
        pageHeightPoints: widget.pageHeightPoints,
        priority: PdfBackgroundRenderPriority.active,
        owner: _requestOwner,
      );
      if (!mounted || generation != _requestGeneration) return;
      _applyImage(bytes);
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _error = error;
        if (!preserveCurrentImage) _imageBytes = null;
      });
    } finally {
      if (mounted && generation == _requestGeneration) _setLoading(false);
    }
  }

  void _subscribeToKey(String key, int generation) {
    if (_subscribedKey == key) return;
    _renderSubscription?.cancel();
    _subscribedKey = key;
    _renderSubscription = _service.watch(key).listen((snapshot) {
      if (!mounted || generation != _requestGeneration) return;
      if (snapshot.bytes != null) {
        _applyImage(snapshot.bytes!);
      } else if (snapshot.error != null) {
        setState(() => _error = snapshot.error);
      }
      _setLoading(snapshot.isLoading);
    });
  }

  void _applyImage(Uint8List bytes) {
    if (!mounted) return;
    final deferRasterUpdates = widget.deferRasterUpdates;
    if (deferRasterUpdates?.value == true && _imageBytes != null) {
      _deferredImageBytes = bytes;
      return;
    }
    setState(() {
      _imageBytes = bytes;
      _deferredImageBytes = null;
      _error = null;
    });
  }

  void _handleDeferRasterUpdatesChanged() {
    if (widget.deferRasterUpdates?.value == true) return;
    final bytes = _deferredImageBytes;
    if (bytes == null) return;
    _applyImage(bytes);
  }

  void _setLoading(bool isLoading) {
    if (_isLoading == isLoading) return;
    _isLoading = isLoading;
    final generation = _requestGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _requestGeneration ||
          _isLoading != isLoading)
        return;
      widget.onLoadingChanged?.call(isLoading);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    if (provider == null) return const SizedBox.shrink();
    if (_requestGeneration == 0) {
      final generation = ++_requestGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _requestGeneration)
          _startLoading(provider);
      });
    }

    if (_imageBytes != null) return Image.memory(_imageBytes!);
    if (_error != null) return const Icon(Icons.picture_as_pdf);
    // return const Center(child: CircularProgressIndicator());
    return const Center(); // return empty widget to avoid layout shift when loading
  }

  @override
  void didUpdateWidget(covariant PDfBackgroundWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.deferRasterUpdates != oldWidget.deferRasterUpdates) {
      oldWidget.deferRasterUpdates?.removeListener(
        _handleDeferRasterUpdatesChanged,
      );
      widget.deferRasterUpdates?.addListener(_handleDeferRasterUpdatesChanged);
      _handleDeferRasterUpdatesChanged();
    }
    final providerChanged = !_isSamePdfBackground(
      widget.provider,
      oldWidget.provider,
    );
    final renderTargetChanged =
        widget.targetPixelWidth != oldWidget.targetPixelWidth ||
        widget.targetPixelHeight != oldWidget.targetPixelHeight ||
        widget.pageWidthPoints != oldWidget.pageWidthPoints ||
        widget.pageHeightPoints != oldWidget.pageHeightPoints;
    if (providerChanged ||
        renderTargetChanged ||
        widget.renderService != oldWidget.renderService) {
      (oldWidget.renderService ?? pdfBackgroundRenderService).cancelRequests(
        _requestOwner,
      );
      _renderSubscription?.cancel();
      _renderSubscription = null;
      _subscribedKey = null;
      final generation = ++_requestGeneration;
      _deferredImageBytes = null;
      if (providerChanged) {
        _imageBytes = null;
        _deferredImageBytes = null;
        _error = null;
      }
      final provider = widget.provider;
      if (provider != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _requestGeneration) {
            _startLoading(
              provider,
              preserveCurrentImage: !providerChanged && _imageBytes != null,
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _service.cancelRequests(_requestOwner);
    _renderSubscription?.cancel();
    widget.deferRasterUpdates?.removeListener(_handleDeferRasterUpdatesChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.deferRasterUpdates?.addListener(_handleDeferRasterUpdatesChanged);
  }
}

bool _isSamePdfBackground(XppBackgroundPdf? a, XppBackgroundPdf? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.filename == b.filename && a.domain == b.domain && a.page == b.page;
}

/// page background for a [XppPage] made from a color and a style
abstract class XppBackgroundSolid extends XppBackground {
  Color? color;
  XppPageSize? size;
  XppBackgroundType? type = XppBackgroundType.SOLID;

  XmlElement generateXmlElement(String style) {
    XmlElement node = XmlElement(XmlName.parts('background'), [
      XmlAttribute(XmlName.parts('type'), 'solid'),
      XmlAttribute(
        XmlName.parts('color'),
        (color ?? Colors.white).toHexTriplet(),
      ),
      XmlAttribute(XmlName.parts('style'), style),
    ]);
    return (node);
  }
}

class XppBackgroundSolidLined extends XppBackgroundSolid {
  Color? color;
  XppPageSize? size;

  XppBackgroundSolidLined({this.color = Colors.white, this.size});
  @override
  Widget render({
    ValueChanged<bool>? onLoadingChanged,
    ValueListenable<bool>? deferRasterUpdates,
    double? targetPixelWidth,
    double? targetPixelHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
  }) {
    return _RasterizedSolidBackground(
      style: 'lined',
      color: color,
      size: size!.toSize(),
      targetPixelWidth: targetPixelWidth,
      targetPixelHeight: targetPixelHeight,
      painter: _LinePainter(color: color),
    );
  }

  @override
  XmlElement toXmlElement() => generateXmlElement('lined');
}

class XppBackgroundSolidRuled extends XppBackgroundSolid {
  Color? color;
  XppPageSize? size;

  XppBackgroundSolidRuled({this.color = Colors.white, this.size});
  @override
  Widget render({
    ValueChanged<bool>? onLoadingChanged,
    ValueListenable<bool>? deferRasterUpdates,
    double? targetPixelWidth,
    double? targetPixelHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
  }) {
    return _RasterizedSolidBackground(
      style: 'ruled',
      color: color,
      size: size!.toSize(),
      targetPixelWidth: targetPixelWidth,
      targetPixelHeight: targetPixelHeight,
      painter: _RuledPainter(color: color),
    );
  }

  @override
  XmlElement toXmlElement() => generateXmlElement('ruled');
}

class XppBackgroundSolidGraph extends XppBackgroundSolid {
  Color? color;
  XppPageSize? size;

  XppBackgroundSolidGraph({this.color = Colors.white, this.size});
  @override
  Widget render({
    ValueChanged<bool>? onLoadingChanged,
    ValueListenable<bool>? deferRasterUpdates,
    double? targetPixelWidth,
    double? targetPixelHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
  }) {
    return _RasterizedSolidBackground(
      style: 'graph',
      color: color,
      size: size!.toSize(),
      targetPixelWidth: targetPixelWidth,
      targetPixelHeight: targetPixelHeight,
      painter: _GraphPainter(color: color),
    );
  }

  @override
  XmlElement toXmlElement() => generateXmlElement('graph');
}

class XppBackgroundSolidDot extends XppBackgroundSolid {
  Color? color;
  XppPageSize? size;

  XppBackgroundSolidDot({this.color = Colors.white, this.size});
  @override
  Widget render({
    ValueChanged<bool>? onLoadingChanged,
    ValueListenable<bool>? deferRasterUpdates,
    double? targetPixelWidth,
    double? targetPixelHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
  }) {
    return _RasterizedSolidBackground(
      style: 'dotted',
      color: color,
      size: size!.toSize(),
      targetPixelWidth: targetPixelWidth,
      targetPixelHeight: targetPixelHeight,
      painter: _DotPainter(color: color),
    );
  }

  @override
  XmlElement toXmlElement() => generateXmlElement('dotted');
}

class XppBackgroundSolidPlain extends XppBackgroundSolid {
  Color? color;
  XppPageSize? size;

  XppBackgroundSolidPlain({this.color, this.size});
  @override
  Widget render({
    ValueChanged<bool>? onLoadingChanged,
    ValueListenable<bool>? deferRasterUpdates,
    double? targetPixelWidth,
    double? targetPixelHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
  }) {
    return Container(
      width: size!.width,
      height: size!.height,
      color: color ?? Colors.white,
    );
  }

  @override
  XmlElement toXmlElement() => generateXmlElement('plain');
}

class _NoXppBackground extends XppBackground {
  XppPageSize? size = XppPageSize(width: 0, height: 0);
  XppBackgroundType? type = XppBackgroundType.NONE;

  @override
  Widget render({
    ValueChanged<bool>? onLoadingChanged,
    ValueListenable<bool>? deferRasterUpdates,
    double? targetPixelWidth,
    double? targetPixelHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
  }) => Container(color: Colors.white);

  @override
  XmlElement toXmlElement() {
    XmlElement node = XmlElement(XmlName.parts('background'), [
      XmlAttribute(XmlName.parts('type'), 'solid'),
      XmlAttribute(XmlName.parts('color'), 'white'),
      XmlAttribute(XmlName.parts('style'), 'plain'),
    ]);
    return (node);
  }
}

class _RasterizedSolidBackground extends StatefulWidget {
  final String style;
  final Color? color;
  final Size size;
  final double? targetPixelWidth;
  final double? targetPixelHeight;
  final CustomPainter painter;

  const _RasterizedSolidBackground({
    required this.style,
    required this.color,
    required this.size,
    required this.targetPixelWidth,
    required this.targetPixelHeight,
    required this.painter,
  });

  @override
  State<_RasterizedSolidBackground> createState() =>
      _RasterizedSolidBackgroundState();
}

class _RasterizedSolidBackgroundState
    extends State<_RasterizedSolidBackground> {
  static final _imageCache = RasterImageCache<_RasterizedBackgroundKey>(
    maxBytes: 16 * 1024 * 1024,
  );

  ui.Image? _image;
  int _generation = 0;
  _RasterizedBackgroundKey? _cacheKey;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final targetPixelWidth =
        widget.targetPixelWidth ?? widget.size.width * pixelRatio;
    final targetPixelHeight =
        widget.targetPixelHeight ?? widget.size.height * pixelRatio;
    final target = boundedRasterSize(targetPixelWidth, targetPixelHeight);
    final key = _RasterizedBackgroundKey(
      style: widget.style,
      color: widget.color ?? Colors.white,
      size: widget.size,
      targetPixelWidth: target.width.toInt(),
      targetPixelHeight: target.height.toInt(),
    );
    if (_cacheKey != key) {
      _cacheKey = key;
      final generation = ++_generation;
      final cached = _imageCache.get(key);
      if (cached != null) {
        _image?.dispose();
        _image = cached;
      } else {
        unawaited(_loadImage(key, generation));
      }
    }

    return _image != null
        ? RawImage(
            image: _image,
            width: widget.size.width,
            height: widget.size.height,
            fit: BoxFit.fill,
          )
        : SizedBox(
            width: widget.size.width,
            height: widget.size.height,
            child: ColoredBox(color: widget.color ?? Colors.white),
          );
  }

  Future<void> _loadImage(_RasterizedBackgroundKey key, int generation) async {
    try {
      final image = await _imageCache.load(
        key,
        () => _renderImage(
          color: key.color,
          size: key.size,
          targetPixelWidth: key.targetPixelWidth,
          targetPixelHeight: key.targetPixelHeight,
          painter: widget.painter,
        ),
      );
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
      });
    } catch (_) {
      // Allow a later rebuild to retry a failed native allocation.
      if (mounted && generation == _generation) _cacheKey = null;
    }
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  static Future<ui.Image> _renderImage({
    required Color color,
    required Size size,
    required int targetPixelWidth,
    required int targetPixelHeight,
    required CustomPainter painter,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(
      targetPixelWidth / size.width,
      targetPixelHeight / size.height,
    );
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    painter.paint(canvas, size);

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(targetPixelWidth, targetPixelHeight);
    } finally {
      picture.dispose();
    }
  }
}

class _RasterizedBackgroundKey {
  final String style;
  final Color color;
  final Size size;
  final int targetPixelWidth;
  final int targetPixelHeight;

  const _RasterizedBackgroundKey({
    required this.style,
    required this.color,
    required this.size,
    required this.targetPixelWidth,
    required this.targetPixelHeight,
  });

  @override
  bool operator ==(Object other) {
    return other is _RasterizedBackgroundKey &&
        other.style == style &&
        other.color == color &&
        other.size == size &&
        other.targetPixelWidth == targetPixelWidth &&
        other.targetPixelHeight == targetPixelHeight;
  }

  @override
  int get hashCode =>
      Object.hash(style, color, size, targetPixelWidth, targetPixelHeight);
}

@visibleForTesting
typedef RasterizedBackgroundKeyForTest = _RasterizedBackgroundKey;

class _LinePainter extends CustomPainter {
  final Color? color;

  _LinePainter({this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[500]!.withValues(alpha: .3)
      ..strokeWidth = 1;
    // 1 because no line at the top
    for (int i = 1; i < size.height / 24; i++) {
      canvas.drawLine(
        Offset(0, i * 24.toDouble()),
        Offset(size.width, i * 24.toDouble()),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _RuledPainter extends CustomPainter {
  final Color? color;

  _RuledPainter({this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[500]!.withValues(alpha: .3)
      ..strokeWidth = 1;
    // 1 because no line at the top
    for (int i = 1; i < size.height / 24; i++) {
      canvas.drawLine(
        Offset(0, i * 24.toDouble()),
        Offset(size.width, i * 24.toDouble()),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _GraphPainter extends CustomPainter {
  final Color? color;

  _GraphPainter({this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[500]!.withValues(alpha: .3)
      ..strokeWidth = 1;
    // 1 because no line at the top
    for (int i = 1; i < size.height / XppPageSize.pt2mm(5); i++) {
      canvas.drawLine(
        Offset(0, i * XppPageSize.pt2mm(5).toDouble()),
        Offset(size.width, i * XppPageSize.pt2mm(5).toDouble()),
        paint,
      );
    }
    // 1 because no line at the beginning
    for (int i = 1; i < size.width / XppPageSize.pt2mm(5); i++) {
      canvas.drawLine(
        Offset(i * XppPageSize.pt2mm(5).toDouble(), 0),
        Offset(i * XppPageSize.pt2mm(5).toDouble(), size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _DotPainter extends CustomPainter {
  final Color? color;

  _DotPainter({this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[500]!.withValues(alpha: .3)
      ..strokeWidth = 1;
    // 1 because no line at the top
    for (int i = 1; i < size.height / XppPageSize.pt2mm(5); i++) {
      // 1 because no line at the beginning
      for (int j = 1; j < size.width / XppPageSize.pt2mm(5); j++) {
        canvas.drawCircle(
          Offset(
            j * XppPageSize.pt2mm(5).toDouble(),
            i * XppPageSize.pt2mm(5).toDouble(),
          ),
          XppPageSize.pt2mm(.5).toDouble(),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

enum XppBackgroundImageDomain { ABSOLUTE, ATTACH, CLONE }

enum XppBackgroundType { NONE, SOLID, PIXMAP }
