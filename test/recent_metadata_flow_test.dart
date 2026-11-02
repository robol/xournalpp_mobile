import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:xournalpp/src/PdfBackgroundRenderService.dart';
import 'package:xournalpp/src/TransparentImage.dart';
import 'package:xournalpp/src/XppBackground.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/NotebookActions.dart';

class _Storage implements NotebookStorage {
  @override
  String get id => 'example-cloud';
  @override
  String? get iconAsset => null;
  List<String>? savedReferences;
  @override
  Future<StoredNotebook?> save({
    required Uint8List bytes,
    required String name,
    StoredNotebook? existing,
    required List<NotebookPdfResource> pdfs,
  }) async {
    savedReferences = pdfs.map((pdf) => pdf.reference).toList();
    return existing;
  }

  @override
  Future<Uint8List> readPdf(StoredNotebook notebook, String reference) async =>
      Uint8List.fromList([1]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

XppBackgroundPdf pdf(String filename) => XppBackgroundPdf(
  filename: filename,
  page: 1,
  onUnavailable: (_, _) async => throw StateError('unexpected PDF recovery'),
);

void main() {
  testWidgets(
    'opening and saving a notebook indexes its current background references',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'notebookCache.enabled.v1': false,
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = _Storage();
      final notebook = StoredNotebook(
        backendId: storage.id,
        id: 'opaque',
        name: 'Notebook',
        modified: DateTime.utc(2025, 1, 2),
      );
      final file = XppFile.empty(title: 'Notebook')
        ..storage = storage
        ..storageNotebook = notebook
        ..recentFolderPath = '/My Courses'
        ..recentFileName = 'Original.xopp';
      file.pages!.first.background = pdf('Lecture.pdf');
      final service = PdfBackgroundRenderService(
        cacheReader: (_) async => kTransparentImage,
      );
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
            child: child!,
          ),
          home: ScaffoldMessenger(
            child: CanvasPage(
              file: file,
              filePath: notebook.id,
              pdfRenderService: service,
            ),
          ),
        ),
      );
      Future<Map> latest() async {
        final data = prefs.getString(PreferencesKeys.kRecentFiles);
        return data == null ? {} : (jsonDecode(data) as List).last as Map;
      }

      for (var i = 0; i < 100 && (await latest()).isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      var entry = await latest();
      expect(entry['pdfReferences'], ['Lecture.pdf']);
      expect(entry['readablePath'], '/My Courses');
      expect(entry['modified'], DateTime.utc(2025, 1, 2).toIso8601String());
      file.pages!.first.background = pdf('New Background.pdf');
      file.title = 'Updated Title';
      final dynamic canvas = tester.state(find.byType(CanvasPage));
      bool? saved;
      await tester.runAsync(() async {
        (canvas.saveFile() as Future<bool>).then((value) => saved = value);
      });
      for (var i = 0; i < 200 && saved == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(saved, true);
      entry = await latest();
      expect(storage.savedReferences, ['New Background.pdf']);
      expect(entry['pdfReferences'], ['New Background.pdf']);
      expect(entry['name'], 'Updated Title');
      expect(entry['readableName'], 'Original.xopp');
      expect(entry['readablePath'], '/My Courses');
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'transferred notebook remembers PDF references and destination path',
    () async {
      SharedPreferences.setMockInitialValues({
        'notebookCache.enabled.v1': false,
      });
      final storage = _Storage();
      final file = XppFile.empty(title: 'Moved')
        ..storage = storage
        ..storageNotebook = StoredNotebook(
          backendId: storage.id,
          id: 'new-id',
          name: 'Moved',
        )
        ..recentFolderPath = '/Destination'
        ..recentFileName = 'Actual.xopp';
      file.pages!.first.background = pdf('source.pdf');
      await rememberTransferredNotebook(file);
      final data = (await SharedPreferences.getInstance()).getString(
        PreferencesKeys.kRecentFiles,
      )!;
      final entry = (jsonDecode(data) as List).single as Map;
      expect(entry['pdfReferences'], ['source.pdf']);
      expect(entry['readablePath'], '/Destination');
      expect(entry['readableName'], 'Actual.xopp');
      expect(entry['path'], 'new-id');
    },
  );
}
