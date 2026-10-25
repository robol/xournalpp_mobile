import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/PdfBackgroundRenderService.dart';
import 'package:xournalpp/src/TransparentImage.dart';
import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/EditingToolbar.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';
import 'package:xournalpp/widgets/XppPagesBrowser.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.delegate.supportedLocales,
  home: child,
);

Future<XppFile> _open(WidgetTester tester, {bool shortPages = false}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(800, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final size = XppPageSize(width: 1000, height: shortPages ? 180 : 1000);
  final file = XppFile(
    title: 'Viewport races',
    pages: List.generate(
      12,
      (_) => XppPage(
        pageSize: size,
        background: XppBackgroundSolidLined(size: size),
        layers: [XppLayer.empty()],
      ),
    ),
  );
  await tester.pumpWidget(_app(CanvasPage(file: file)));
  await tester.pumpAndSettle();
  return file;
}

ScrollPosition _vertical(WidgetTester tester) => tester
    .stateList<ScrollableState>(find.byType(Scrollable))
    .firstWhere((state) => state.position.axis == Axis.vertical)
    .position;

Future<void> _wheel(WidgetTester tester, Offset position, double delta) =>
    tester.sendEventToBinding(
      PointerScrollEvent(
        position: position,
        scrollDelta: Offset(0, delta),
        kind: PointerDeviceKind.mouse,
      ),
    );

void main() {
  testWidgets('idle prefetch requests a frame without an unrelated rebuild', (
    tester,
  ) async {
    await _open(tester);
    // Control just the interaction timers so expiration does not itself pump
    // a frame (WidgetTester.pump would conceal a missing frame request).
    final timers = <_ManualTimer>[];
    await runZoned(
      () => _wheel(tester, const Offset(400, 300), 24),
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          if (duration == const Duration(milliseconds: 180)) {
            final timer = _ManualTimer(zone.bindCallback(callback));
            timers.add(timer);
            return timer;
          }
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    timers.singleWhere((timer) => timer.isActive).fire();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  for (final navigate in [false, true]) {
    testWidgets(
      'new ${navigate ? "page navigation" : "wheel pan"} stops animated zoom',
      (tester) async {
        await _open(tester);
        _vertical(tester).jumpTo(200);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithIcon(IconButton, Icons.add).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final dynamic canvas = tester.state(find.byType(CanvasPage));
        final scale = canvas.pageScale as double;
        expect(scale, greaterThan(1));
        expect(scale, lessThan(1.1));
        final before = _vertical(tester).pixels;
        if (navigate) {
          tester
              .widget<XppPagesBrowser>(find.byType(XppPagesBrowser))
              .onPageChange!(5);
        } else {
          await _wheel(tester, const Offset(400, 300), 24);
        }
        await tester.pumpAndSettle();
        expect(canvas.pageScale, scale);
        if (navigate) {
          expect(canvas.currentPage, 5);
        } else {
          expect(_vertical(tester).pixels, closeTo(before + 24, .01));
        }
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'new ${navigate ? "page navigation" : "wheel pan"} supersedes an ended pinch before layout',
      (tester) async {
        await _open(tester);
        final first = await tester.startGesture(
          const Offset(350, 300),
          pointer: 91,
        );
        final second = await tester.startGesture(
          const Offset(450, 300),
          pointer: 92,
        );
        await first.moveBy(const Offset(-20, 0));
        await second.moveBy(const Offset(20, 0));
        await first.up();
        await second.up();
        final before = _vertical(tester).pixels;
        if (navigate) {
          tester
              .widget<XppPagesBrowser>(find.byType(XppPagesBrowser))
              .onPageChange!(4);
        } else {
          await _wheel(tester, const Offset(400, 300), 24);
        }
        await tester.pumpAndSettle();
        if (navigate) {
          final dynamic canvas = tester.state(find.byType(CanvasPage));
          expect(canvas.currentPage, 4);
        } else {
          expect(_vertical(tester).pixels, closeTo(before + 24, .01));
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'prepared URI snapshot is reused by the editor without recovery or rereading',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var reads = 0;
      final service = PdfBackgroundRenderService(
        sourceReader: (_) async {
          reads++;
          return Uint8List.fromList([1]);
        },
        cacheReader: (_) async => kTransparentImage,
      );
      final file = XppFile(
        title: 'Prepared URI',
        pages: List.generate(
          12,
          (index) => XppPage(
            pageSize: XppPageSize.a4,
            background: _TestPdfBackground(
              service,
              index + 1,
              (_, __) async => throw StateError('unexpected recovery'),
            ),
            layers: [XppLayer.empty()],
          ),
        ),
      );
      late BuildContext owner;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              owner = context;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final preparing = file.prepareForOpening(owner, renderService: service);
      await tester.pump();
      await preparing;
      await tester.pumpWidget(
        _app(CanvasPage(file: file, pdfRenderService: service)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsWidgets);
      _vertical(tester).jumpTo(7000);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsWidgets);
      expect(reads, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await service.dispose();
    },
  );

  testWidgets(
    'missing PDF recovery is shared by the editor and survives page removal',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final picked = Completer<XppPickedFile>();
      final service = PdfBackgroundRenderService(
        sourceReader: (_) async => throw StateError('missing document'),
        cacheReader: (_) async => kTransparentImage,
      );
      var recoveries = 0;
      late BuildContext recoveryOwner;
      final file = XppFile(
        title: 'Recovery',
        pages: List.generate(
          12,
          (index) => XppPage(
            pageSize: XppPageSize.a4,
            background: _TestPdfBackground(service, index + 1, (context, _) {
              recoveries++;
              recoveryOwner = context;
              return picked.future;
            }),
            layers: [XppLayer.empty()],
          ),
        ),
      );
      await tester.pumpWidget(
        _app(CanvasPage(file: file, pdfRenderService: service)),
      );
      await tester.pumpAndSettle();
      final firstKey =
          tester.widget<PointerListener>(find.byType(PointerListener).first).key
              as GlobalKey;
      expect(recoveries, 1);
      expect(recoveryOwner.widget, isA<CanvasPage>());
      _vertical(tester).jumpTo(7000);
      await tester.pump();
      expect(firstKey.currentState, isNull);
      expect(recoveryOwner.mounted, isTrue);
      expect(recoveries, 1);
      picked.complete(XppPickedFile(Uint8List.fromList([1])));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await service.dispose();
    },
  );

  testWidgets('wheel over a page applies exactly one delta', (tester) async {
    await _open(tester);
    final before = _vertical(tester).pixels;
    await _wheel(tester, const Offset(400, 300), 24);
    await tester.pump();
    expect(_vertical(tester).pixels - before, closeTo(24, .01));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('wheel in a page gap applies exactly one delta', (tester) async {
    await _open(tester, shortPages: true);
    final firstRect = tester.getRect(find.byType(XppPageStack).first);
    final before = _vertical(tester).pixels;
    await _wheel(
      tester,
      Offset(firstRect.center.dx, firstRect.bottom + 14),
      24,
    );
    await tester.pump();
    expect(_vertical(tester).pixels - before, closeTo(24, .01));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'batched pinch moves preserve the focal document point on both axes',
    (tester) async {
      await _open(tester);
      final pageFinder = find.byType(XppPageStack).first;
      final box = tester.renderObject<RenderBox>(pageFinder);
      const focal = Offset(400, 300);
      final documentPoint = box.globalToLocal(focal);
      final first = await tester.startGesture(
        focal - const Offset(50, 0),
        pointer: 71,
      );
      final second = await tester.startGesture(
        focal + const Offset(50, 0),
        pointer: 72,
      );
      // Multiple input events with no intervening layout must result in one
      // absolute correction, rather than a backlog of focal deltas.
      await first.moveTo(focal - const Offset(75, 0));
      await second.moveTo(focal + const Offset(75, 0));
      await tester.pump();
      final dynamic canvas = tester.state(find.byType(CanvasPage));
      expect(canvas.pageScale, closeTo(1.5, .001));
      final after = tester
          .renderObject<RenderBox>(pageFinder)
          .localToGlobal(documentPoint);
      expect((after - focal).distance, lessThan(.1));
      await first.moveBy(const Offset(20, 20));
      await second.moveBy(const Offset(20, 20));
      await tester.pump();
      final translated = tester
          .renderObject<RenderBox>(pageFinder)
          .localToGlobal(documentPoint);
      expect(
        (translated - (focal + const Offset(20, 20))).distance,
        lessThan(.1),
      );
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cross-page pinch cancels touch ink and suppresses the remaining finger',
    (tester) async {
      final file = await _open(tester, shortPages: true);
      // Both page listeners use pen input; the canvas still owns the pinch.
      tester
          .widget<EditingToolBar>(find.byType(EditingToolBar))
          .onNewDeviceMap!({PointerDeviceKind.touch: EditingTool.STYLUS});
      await tester.pump();
      final centers = tester.getCenter(find.byType(XppPageStack).first);
      final next = tester.getCenter(find.byType(XppPageStack).at(1));
      final first = await tester.startGesture(centers, pointer: 81);
      await first.moveBy(const Offset(5, 0));
      expect(
        tester
            .state<PointerListenerState>(find.byType(PointerListener).first)
            .strokePoints
            .isEmpty,
        isFalse,
      );
      final second = await tester.startGesture(next, pointer: 82);
      await second.moveBy(const Offset(0, 25));
      await tester.pump();
      await second.up();
      await first.moveBy(const Offset(15, 0));
      await first.up();
      await tester.pumpAndSettle();
      expect(
        file.pages!
            .expand((page) => page.layers!)
            .expand((layer) => layer.content ?? []),
        isEmpty,
      );
      final dynamic canvas = tester.state(find.byType(CanvasPage));
      expect(canvas.pageScale, greaterThan(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('removing the gesture page cannot leave canvas pinch stuck', (
    tester,
  ) async {
    await _open(tester);
    final firstKey =
        tester.widget<PointerListener>(find.byType(PointerListener).first).key
            as GlobalKey;
    final first = await tester.startGesture(
      const Offset(350, 300),
      pointer: 91,
    );
    final second = await tester.startGesture(
      const Offset(450, 300),
      pointer: 92,
    );
    await second.moveBy(const Offset(20, 0));
    await tester.pump();
    _vertical(tester).jumpTo(7000);
    await tester.pump();
    expect(firstKey.currentState, isNull);
    await second.cancel();
    await first.up();
    await tester.pumpAndSettle();
    final before = _vertical(tester).pixels;
    await _wheel(tester, const Offset(400, 300), 24);
    await tester.pump();
    expect(_vertical(tester).pixels, closeTo(before + 24, .01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'page navigation retains target through intermediate frames and replacement',
    (tester) async {
      await _open(tester);
      tester
          .widget<XppPagesBrowser>(find.byType(XppPagesBrowser))
          .onPageChange!(5);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      final dynamic canvas = tester.state(find.byType(CanvasPage));
      expect(canvas.currentPage, 5);
      tester
          .widget<XppPagesBrowser>(find.byType(XppPagesBrowser))
          .onPageChange!(3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(canvas.currentPage, 3);
      await tester.pumpAndSettle();
      expect(canvas.currentPage, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('user wheel supersedes a programmatic page jump', (tester) async {
    await _open(tester);
    tester.widget<XppPagesBrowser>(find.byType(XppPagesBrowser)).onPageChange!(
      8,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final before = _vertical(tester).pixels;
    await _wheel(tester, const Offset(400, 300), 24);
    await tester.pumpAndSettle();
    expect(_vertical(tester).pixels, closeTo(before + 24, .01));
    final dynamic canvas = tester.state(find.byType(CanvasPage));
    expect(canvas.currentPage, isNot(8));
    await tester.pumpWidget(const SizedBox());
  });
}

class _ManualTimer implements Timer {
  _ManualTimer(this.callback);
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    callback();
  }
}

class _TestPdfBackground extends XppBackgroundPdf {
  final PdfBackgroundRenderService service;

  _TestPdfBackground(this.service, int page, FileNotAvailableCallback callback)
    : super(
        page: page,
        filename: 'content://lifecycle-test/document',
        onUnavailable: callback,
      );

  @override
  Widget render({
    ValueChanged<bool>? onLoadingChanged,
    ValueListenable<bool>? deferRasterUpdates,
    double? targetPixelWidth,
    double? targetPixelHeight,
    double? pageWidthPoints,
    double? pageHeightPoints,
  }) => PDfBackgroundWidget(
    provider: this,
    renderService: service,
    onLoadingChanged: onLoadingChanged,
    deferRasterUpdates: deferRasterUpdates,
    targetPixelWidth: targetPixelWidth,
    targetPixelHeight: targetPixelHeight,
    pageWidthPoints: pageWidthPoints,
    pageHeightPoints: pageHeightPoints,
  );
}
