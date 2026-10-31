import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/DraftRecovery.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppLayer.dart';
import 'package:xournalpp/src/XppPage.dart';
import 'package:xournalpp/src/conditional/draft_storage/draft_storage_io.dart'
    as storage;
import 'package:xournalpp/widgets/XppPageStack.dart';

Widget app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.delegate.supportedLocales,
  home: child,
);

void main() {
  late Directory directory;
  setUp(() {
    DraftRecovery.resetForTesting();
    directory = Directory.systemTemp.createTempSync('xpp_drafts_');
    storage.debugDraftDirectory = directory.path;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    storage.debugDraftDirectory = null;
    directory.deleteSync(recursive: true);
  });

  test(
    'newer snapshots replace older ones, and deletion follows pending writes',
    () async {
      const id = '123_456';
      final first = RecoveryDraft(
        id: id,
        bytes: Uint8List.fromList([1]),
        page: 1,
        title: 'First',
      );
      final second = RecoveryDraft(
        id: id,
        bytes: Uint8List.fromList([2]),
        page: 2,
        title: 'Second',
      );
      await Future.wait([
        DraftRecovery.save(first),
        DraftRecovery.save(second),
      ]);
      final drafts = await DraftRecovery.list();
      expect(drafts.single.bytes, [2]);
      expect(drafts.single.page, 2);
      expect(drafts.single.title, 'Second');
      await Future.wait([DraftRecovery.save(first), DraftRecovery.remove(id)]);
      expect(await DraftRecovery.list(), isEmpty);
    },
  );

  testWidgets('a successful save removes the corresponding recovery draft', (
    tester,
  ) async {
    const id = '123_789';
    await tester.runAsync(
      () => DraftRecovery.save(
        RecoveryDraft(id: id, bytes: Uint8List.fromList([1]), page: 0),
      ),
    );
    final size = XppPageSize(width: 200, height: 200);
    final file = XppFile(
      title: 'Notes',
      pages: [
        XppPage(
          pageSize: size,
          background: XppBackgroundSolidPlain(size: size),
          layers: [XppLayer.empty()],
        ),
      ],
    );
    final path = '${directory.path}/saved.xopp';
    await tester.pumpWidget(
      app(CanvasPage(file: file, filePath: path, recoveryDraftId: id)),
    );
    await tester.pumpAndSettle();
    final dynamic canvas = tester.state(find.byType(CanvasPage));
    bool? result;
    await tester.runAsync(() async {
      canvas.saveFile().then((bool value) => result = value);
    });
    for (var i = 0; i < 200 && result == null; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(File(path).existsSync(), isTrue);
    expect(await tester.runAsync(DraftRecovery.list), isEmpty);
  });

  testWidgets('backgrounded edits can be recovered and explicitly discarded', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final size = XppPageSize(width: 200, height: 200);
    final file = XppFile(
      title: 'Notes',
      pages: [
        XppPage(
          pageSize: size,
          background: XppBackgroundSolidPlain(size: size),
          layers: [XppLayer.empty()],
        ),
      ],
    );
    await tester.pumpWidget(app(CanvasPage(file: file)));
    await tester.pump();
    final start =
        tester.getRect(find.byType(XppPageStack)).topLeft +
        const Offset(200, 200);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveTo(start + const Offset(40, 40));
    await gesture.up();
    await tester.pump();
    expect(file.pages!.single.layers!.single.content, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    for (
      var i = 0;
      i < 100 &&
          directory.listSync().where((f) => f.path.endsWith('.json')).isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    expect(
      directory.listSync().where((f) => f.path.endsWith('.json')),
      hasLength(1),
    );
    await tester.pump();
    final drafts = await tester.runAsync(DraftRecovery.list) ?? [];
    expect(drafts, hasLength(1));
    expect(drafts.single.title, 'Notes');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(app(const OpenPage()));
    await tester.pump();
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 100 && find.text('Recover unsaved work?').evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    expect(find.text('Recover unsaved work?'), findsOneWidget);
    await tester.tap(find.text('Recover'));
    await tester.pump();
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 100 && find.byType(CanvasPage).evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    final canvas = tester.widget<CanvasPage>(find.byType(CanvasPage));
    expect(canvas.file!.pages!.single.layers!.single.content, hasLength(1));
    expect(canvas.filePath, isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Save changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    for (
      var i = 0;
      i < 100 &&
          directory
              .listSync()
              .where((f) => f.path.endsWith('.json'))
              .isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
    final remaining = await tester.runAsync(DraftRecovery.list);
    expect(remaining, isEmpty);
  });
  testWidgets('edits are checkpointed while the app remains active', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final size = XppPageSize(width: 200, height: 200);
    final file = XppFile(
      pages: [
        XppPage(
          pageSize: size,
          background: XppBackgroundSolidPlain(size: size),
          layers: [XppLayer.empty()],
        ),
      ],
    );
    await tester.pumpWidget(app(CanvasPage(file: file)));
    await tester.pump();
    final start =
        tester.getRect(find.byType(XppPageStack)).topLeft +
        const Offset(200, 200);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveTo(start + const Offset(40, 40));
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    for (
      var i = 0;
      i < 100 &&
          directory.listSync().where((f) => f.path.endsWith('.json')).isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(
      directory.listSync().where((f) => f.path.endsWith('.json')),
      hasLength(1),
    );
  });

  testWidgets('draft waits for pointer release and two seconds of inactivity', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final size = XppPageSize(width: 200, height: 200);
    final file = XppFile(
      pages: [
        XppPage(
          pageSize: size,
          background: XppBackgroundSolidPlain(size: size),
          layers: [XppLayer.empty()],
        ),
      ],
    );
    await tester.pumpWidget(app(CanvasPage(file: file)));
    await tester.pump();
    final start =
        tester.getRect(find.byType(XppPageStack)).topLeft +
        const Offset(200, 200);
    final first = await tester.startGesture(
      start,
      kind: PointerDeviceKind.stylus,
    );
    await first.moveTo(start + const Offset(30, 30));
    await first.up();
    await tester.pump(const Duration(seconds: 1));
    final second = await tester.startGesture(
      start,
      kind: PointerDeviceKind.stylus,
    );
    await second.moveTo(start + const Offset(40, 40));
    await tester.pump(const Duration(seconds: 3));
    expect(
      directory.listSync().where((f) => f.path.endsWith('.json')),
      isEmpty,
    );
    await second.up();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(
      directory.listSync().where((f) => f.path.endsWith('.json')),
      isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 500));
    for (
      var i = 0;
      i < 100 &&
          directory.listSync().where((f) => f.path.endsWith('.json')).isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(
      directory.listSync().where((f) => f.path.endsWith('.json')),
      hasLength(1),
    );
  });
}
