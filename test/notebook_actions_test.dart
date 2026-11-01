import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:xournalpp/src/NotebookTransfer.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/widgets/NotebookActions.dart';

class TransferStorage
    implements NotebookStorage, NotebookTransfer, NotebookDeletion {
  int copies = 0, deletes = 0;
  bool denied = false;
  @override
  String get id => 'test';
  @override
  String? get iconAsset => null;
  @override
  bool canDelete(StoredNotebook notebook) => true;
  @override
  Future<void> delete(StoredNotebook notebook) async {
    deletes++;
    if (denied) throw StateError('denied');
  }

  @override
  Future<Uint8List> readNotebook(StoredNotebook notebook) async => Uint8List(0);
  @override
  Future<NotebookFolder?> parentOf(StoredNotebook notebook) async =>
      const NotebookFolder('test', 'actual-folder');
  @override
  Future<StoredNotebook?> createInFolder({
    required NotebookFolder folder,
    required String name,
    required Uint8List bytes,
    required List<NotebookPdfResource> pdfs,
  }) async {
    expect(folder.id, 'actual-folder');
    copies++;
    return StoredNotebook(backendId: id, id: 'copy', name: name);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget app(Widget home) => MaterialApp(
  localizationsDelegates: [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.delegate.supportedLocales,
  home: home,
);
void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'notebookCache.enabled.v1': false,
    }),
  );
  testWidgets('rename adopts a completed copy when source deletion fails', (
    tester,
  ) async {
    final storage = TransferStorage()..denied = true;
    final file = XppFile.empty(title: 'Old')
      ..storage = storage
      ..storageNotebook = const StoredNotebook(
        backendId: 'test',
        id: 'old',
        name: 'Old',
      );
    NotebookTransferResult? result;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await transferNotebook(context, file, rename: true);
              },
              child: const Text('Start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'New');
    await tester.tap(find.text('Save'));
    for (var i = 0; i < 100 && result == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(result!.status, NotebookTransferStatus.copiedSourceRetained);
    expect(file.storageNotebook!.id, 'copy');
    expect(file.title, 'New');
    expect(storage.copies, 1);
    expect(storage.deletes, 1);
    expect(tester.takeException(), isNull);
  });
  for (final cached in [false, true]) {
    testWidgets(
      'canvas move is below Save As and cached=$cached controls availability',
      (tester) async {
        final storage = TransferStorage();
        final file = XppFile.empty(title: 'Old')
          ..storage = storage
          ..storageNotebook = const StoredNotebook(
            backendId: 'test',
            id: 'old',
            name: 'Old',
          )
          ..openedFromCache = cached;
        await tester.pumpWidget(app(CanvasPage(file: file, filePath: 'old')));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        final move = tester.widget<PopupMenuItem<String>>(
          find.ancestor(
            of: find.text('Move to…'),
            matching: find.byType(PopupMenuItem<String>),
          ),
        );
        expect(move.enabled, !cached);
        expect(
          tester.getTopLeft(find.text('Move to…')).dy,
          greaterThan(tester.getTopLeft(find.text('Save as...')).dy),
        );
        if (!cached) {
          await tester.tap(find.text('Move to…'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(SimpleDialog), findsOneWidget);
          expect(
            tester
                .widgetList<AbsorbPointer>(find.byType(AbsorbPointer))
                .any((widget) => widget.absorbing),
            isTrue,
          );
          final dynamic canvas = tester.state(find.byType(CanvasPage));
          expect(await canvas.saveFile(), isFalse);
          Navigator.of(tester.element(find.byType(SimpleDialog))).pop();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
