import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/PdfBackgroundRenderService.dart';
import 'package:xournalpp/src/TransparentImage.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppPickedFile.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.delegate.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'initial and cached images display even while updates are deferred',
    (tester) async {
      final defer = ValueNotifier(true);
      var reads = 0;
      final service = PdfBackgroundRenderService(
        sourceRevision: (_) async => 'snapshot',
        sourceReader: (_) async => Uint8List(1),
        cacheReader: (_) async {
          reads++;
          return kTransparentImage;
        },
      );
      final background = XppBackgroundPdf(
        filename: '/cached.pdf',
        onUnavailable: (_, __) async => throw StateError('unexpected recovery'),
      );
      Widget build() => _app(
        PDfBackgroundWidget(
          provider: background,
          renderService: service,
          deferRasterUpdates: defer,
        ),
      );
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(reads, 1);
      expect(defer.value, isTrue);
      await tester.pumpWidget(const SizedBox());
      defer.dispose();
      await service.dispose();
    },
  );

  testWidgets(
    'virtualized PDF releases its pending render when scrolled away',
    (tester) async {
      final cacheRead = Completer<Uint8List?>();
      final service = PdfBackgroundRenderService(
        sourceRevision: (_) async => 'revision',
        sourceReader: (_) async => Uint8List(1),
        cacheReader: (_) => cacheRead.future,
      );
      final controller = ScrollController();
      final key = GlobalKey();
      await tester.pumpWidget(
        _app(
          ListView.builder(
            controller: controller,
            itemExtent: 1000,
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            itemCount: 20,
            itemBuilder: (_, index) => index == 0
                ? PDfBackgroundWidget(
                    key: key,
                    renderService: service,
                    provider: XppBackgroundPdf(
                      filename: '/virtual.pdf',
                      onUnavailable: (_, __) async =>
                          throw StateError('unused'),
                    ),
                  )
                : const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(key.currentState, isNotNull);
      controller.jumpTo(5000);
      await tester.pump();
      expect(key.currentState, isNull);
      cacheRead.complete(kTransparentImage);
      await tester.pumpAndSettle();
      final source = await service.sourceForPath(
        '/virtual.pdf',
        fallback: () async => throw StateError('unused'),
      );
      expect(
        service.peek(
          service.keyFor(source, null, PdfBackgroundRenderVariant.full),
        ),
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await service.dispose();
    },
  );

  testWidgets('disposed background never invokes delayed missing-file UI', (
    tester,
  ) async {
    final revision = Completer<String?>();
    var recoveries = 0;
    final service = PdfBackgroundRenderService(
      sourceRevision: (_) => revision.future,
    );
    await tester.pumpWidget(
      _app(
        PDfBackgroundWidget(
          renderService: service,
          provider: XppBackgroundPdf(
            filename: '/missing.pdf',
            onUnavailable: (_, __) async {
              recoveries++;
              return XppPickedFile(Uint8List(1));
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    revision.complete(null);
    await tester.pump();
    expect(recoveries, 0);
    expect(tester.takeException(), isNull);
    await service.dispose();
  });

  testWidgets('replacing provider invalidates a pending recovery callback', (
    tester,
  ) async {
    final revision = Completer<String?>();
    var oldRecovery = 0;
    var newRecovery = 0;
    final service = PdfBackgroundRenderService(
      sourceRevision: (_) => revision.future,
      cacheReader: (_) async => kTransparentImage,
    );
    final old = XppBackgroundPdf(
      filename: '/old.pdf',
      onUnavailable: (_, __) async {
        oldRecovery++;
        return XppPickedFile(Uint8List.fromList([1]));
      },
    );
    final next = XppBackgroundPdf(
      filename: '/new.pdf',
      onUnavailable: (_, __) async {
        newRecovery++;
        return XppPickedFile(Uint8List.fromList([2]));
      },
    );
    await tester.pumpWidget(
      _app(PDfBackgroundWidget(provider: old, renderService: service)),
    );
    await tester.pumpWidget(
      _app(PDfBackgroundWidget(provider: next, renderService: service)),
    );
    revision.complete(null);
    await tester.pumpAndSettle();
    expect(oldRecovery, 0);
    expect(newRecovery, 1);
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
  });

  testWidgets('obsolete deferred raster is cleared when the target changes', (
    tester,
  ) async {
    final defer = ValueNotifier(false);
    final secondRead = Completer<Uint8List?>();
    final initial = Uint8List.fromList(kTransparentImage);
    final obsolete = Uint8List.fromList(kTransparentImage);
    final latest = Uint8List.fromList(kTransparentImage);
    var reads = 0;
    final service = PdfBackgroundRenderService(
      sourceRevision: (_) async => 'unchanged',
      sourceReader: (_) async => Uint8List(1),
      cacheReader: (_) async => ++reads == 1
          ? initial
          : reads == 2
          ? obsolete
          : secondRead.future,
    );
    final background = XppBackgroundPdf(
      filename: '/deferred.pdf',
      onUnavailable: (_, __) async => throw StateError('unused'),
    );
    Widget build(double width) => _app(
      PDfBackgroundWidget(
        provider: background,
        renderService: service,
        deferRasterUpdates: defer,
        targetPixelWidth: width,
        targetPixelHeight: width,
      ),
    );
    await tester.pumpWidget(build(128));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    defer.value = true;
    await tester.pumpWidget(build(256));
    await tester.pumpAndSettle();
    await tester.pumpWidget(build(512));
    await tester.pump();
    defer.value = false;
    await tester.pump();
    // The initial image stays usable while replacement rasters are deferred.
    // Flushing the obsolete replacement must not schedule another rebuild.
    expect(find.byType(Image), findsOneWidget);
    expect(
      (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes,
      same(initial),
    );
    secondRead.complete(latest);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(
      (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes,
      same(latest),
    );
    await tester.pumpWidget(const SizedBox());
    defer.dispose();
    await service.dispose();
  });

  testWidgets('missing-file dialog rejects a disposed recovery owner', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
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
    await tester.pumpWidget(const SizedBox());
    await expectLater(
      showMissingFileDialog(owner, '/missing.pdf'),
      throwsStateError,
    );
    expect(tester.takeException(), isNull);
  });
}
