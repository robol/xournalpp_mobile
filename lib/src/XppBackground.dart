import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:async';

import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:xournalpp/src/HexColor.dart';
import 'package:xournalpp/src/PdfBackgroundRenderService.dart';

import 'XppPage.dart';

abstract class XppBackground {
  XppBackgroundType? type;
  XppPageSize? size;

  static XppBackground get none => _NoXppBackground();

  Widget render({
    ValueChanged<bool>? onLoadingChanged,
    bool fullQuality = true,
    double? targetPixelWidth,
    double? targetPixelHeight,
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
    bool fullQuality = true,
    double? targetPixelWidth,
    double? targetPixelHeight,
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
    XmlElement node = XmlElement(XmlName('background'), [
      XmlAttribute(XmlName('type'), 'pixmap'),
      XmlAttribute(XmlName('domain'), domainString),
      XmlAttribute(XmlName('filename'), filename!),
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
    bool fullQuality = true,
    double? targetPixelWidth,
    double? targetPixelHeight,
  }) {
    return (PDfBackgroundWidget(
      provider: this,
      onLoadingChanged: onLoadingChanged,
      fullQuality: fullQuality,
      targetPixelWidth: targetPixelWidth,
      targetPixelHeight: targetPixelHeight,
    ));
  }

  @override
  XmlElement toXmlElement() {
    final attributes = [
      XmlAttribute(XmlName('type'), 'pdf'),
      XmlAttribute(XmlName('pageno'), page.toString()),
      XmlAttribute(XmlName('domain'), 'absolute'),
      if (filename != null) XmlAttribute(XmlName('filename'), filename!),
    ];
    XmlElement node = XmlElement(XmlName('background'), attributes);
    return (node);
  }
}

class PDfBackgroundWidget extends StatefulWidget {
  final XppBackgroundPdf? provider;
  final ValueChanged<bool>? onLoadingChanged;
  final bool fullQuality;
  final double? targetPixelWidth;
  final double? targetPixelHeight;

  const PDfBackgroundWidget({
    Key? key,
    this.provider,
    this.onLoadingChanged,
    this.fullQuality = true,
    this.targetPixelWidth,
    this.targetPixelHeight,
  }) : super(key: key);
  @override
  _PDfBackgroundWidgetState createState() => _PDfBackgroundWidgetState();
}

class _PDfBackgroundWidgetState extends State<PDfBackgroundWidget>
    with AutomaticKeepAliveClientMixin {
  StreamSubscription<PdfBackgroundRenderSnapshot>? _renderSubscription;
  Uint8List? _imageBytes;
  Object? _error;
  bool _isLoading = false;
  int _requestGeneration = 0;
  String? _subscribedKey;

  Future<PdfBackgroundRenderSource> _loadPdfSource(
    XppBackgroundPdf provider,
  ) async {
    final filename = provider.filename;
    return pdfBackgroundRenderService.sourceForPath(
      filename,
      fallback: () => provider.onUnavailable(context, filename),
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
      final source = await _loadPdfSource(provider);
      if (!mounted || generation != _requestGeneration) return;

      final variant = widget.fullQuality
          ? PdfBackgroundRenderVariant.full
          : PdfBackgroundRenderVariant.thumbnail;
      final key = pdfBackgroundRenderService.keyFor(
        source,
        provider.page,
        variant,
        targetWidth: widget.targetPixelWidth,
        targetHeight: widget.targetPixelHeight,
      );
      _subscribeToKey(key, generation);

      final cached = pdfBackgroundRenderService.peek(key);
      if (cached != null) {
        _applyImage(cached);
        return;
      }

      final bytes = await pdfBackgroundRenderService.request(
        source,
        provider.page,
        variant,
        targetWidth: widget.targetPixelWidth,
        targetHeight: widget.targetPixelHeight,
        priority: widget.fullQuality
            ? PdfBackgroundRenderPriority.active
            : PdfBackgroundRenderPriority.visible,
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
    _renderSubscription = pdfBackgroundRenderService.watch(key).listen((
      snapshot,
    ) {
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
    setState(() {
      _imageBytes = bytes;
      _error = null;
    });
  }

  void _setLoading(bool isLoading) {
    if (_isLoading == isLoading) return;
    _isLoading = isLoading;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onLoadingChanged?.call(isLoading);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = widget.provider;
    if (provider == null) return const SizedBox.shrink();
    if (_requestGeneration == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startLoading(provider);
      });
    }

    if (_imageBytes != null) return Image.memory(_imageBytes!);
    if (_error != null) return const Icon(Icons.picture_as_pdf);
    // return const Center(child: CircularProgressIndicator());
    return const Center(); // return empty widget to avoid layout shift when loading
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant PDfBackgroundWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final providerChanged = !_isSamePdfBackground(
      widget.provider,
      oldWidget.provider,
    );
    final renderTargetChanged =
        widget.fullQuality != oldWidget.fullQuality ||
        widget.targetPixelWidth != oldWidget.targetPixelWidth ||
        widget.targetPixelHeight != oldWidget.targetPixelHeight;
    if (providerChanged || renderTargetChanged) {
      _renderSubscription?.cancel();
      _renderSubscription = null;
      _subscribedKey = null;
      _requestGeneration++;
      if (providerChanged) {
        _imageBytes = null;
        _error = null;
      }
      final provider = widget.provider;
      if (provider != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
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
    _renderSubscription?.cancel();
    super.dispose();
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
    XmlElement node = XmlElement(XmlName('background'), [
      XmlAttribute(XmlName('type'), 'solid'),
      XmlAttribute(XmlName('color'), (color ?? Colors.white).toHexTriplet()),
      XmlAttribute(XmlName('style'), style),
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
    bool fullQuality = true,
    double? targetPixelWidth,
    double? targetPixelHeight,
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
    bool fullQuality = true,
    double? targetPixelWidth,
    double? targetPixelHeight,
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
    bool fullQuality = true,
    double? targetPixelWidth,
    double? targetPixelHeight,
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
    bool fullQuality = true,
    double? targetPixelWidth,
    double? targetPixelHeight,
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
    bool fullQuality = true,
    double? targetPixelWidth,
    double? targetPixelHeight,
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
    bool fullQuality = true,
    double? targetPixelWidth,
    double? targetPixelHeight,
  }) => Container(color: Colors.white);

  @override
  XmlElement toXmlElement() {
    XmlElement node = XmlElement(XmlName('background'), [
      XmlAttribute(XmlName('type'), 'solid'),
      XmlAttribute(XmlName('color'), 'white'),
      XmlAttribute(XmlName('style'), 'plain'),
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
  static final Map<_RasterizedBackgroundKey, Future<ui.Image>> _imageCache = {};

  Future<ui.Image>? _imageFuture;
  _RasterizedBackgroundKey? _cacheKey;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final targetPixelWidth =
        widget.targetPixelWidth ?? widget.size.width * pixelRatio;
    final targetPixelHeight =
        widget.targetPixelHeight ?? widget.size.height * pixelRatio;
    final key = _RasterizedBackgroundKey(
      style: widget.style,
      color: widget.color ?? Colors.white,
      size: widget.size,
      targetPixelWidth: targetPixelWidth.ceil().clamp(1, 100000),
      targetPixelHeight: targetPixelHeight.ceil().clamp(1, 100000),
    );
    if (_cacheKey != key) {
      _cacheKey = key;
      _imageFuture = _imageCache.putIfAbsent(
        key,
        () => _renderImage(
          color: key.color,
          size: widget.size,
          targetPixelWidth: key.targetPixelWidth,
          targetPixelHeight: key.targetPixelHeight,
          painter: widget.painter,
        ),
      );
    }

    return FutureBuilder<ui.Image>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return RawImage(
            image: snapshot.data,
            width: widget.size.width,
            height: widget.size.height,
            fit: BoxFit.fill,
          );
        }

        return SizedBox(
          width: widget.size.width,
          height: widget.size.height,
          child: ColoredBox(color: widget.color ?? Colors.white),
        );
      },
    );
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
    final image = await picture.toImage(targetPixelWidth, targetPixelHeight);
    picture.dispose();
    return image;
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
