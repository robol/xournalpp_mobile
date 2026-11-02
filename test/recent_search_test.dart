import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/src/RecentFiles.dart';
import 'package:xournalpp/src/RecentSearch.dart';
import 'package:xournalpp/src/NotebookStorage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/src/XppPickedFile.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/Workspace.dart';

class _CountingProvider implements NotebookStorage {
  int reads = 0;
  @override
  String get id => 'gdrive:one';
  @override
  String? get iconAsset => null;
  @override
  Future<Uint8List> readNotebook(StoredNotebook notebook) async {
    reads++;
    throw StateError('Search must not scan providers');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final entries = <Map<String, dynamic>>[
    {
      'name': 'zebra',
      'path': '/archive/foo%20bar.xopp',
      'modified': '2025-01-02T12:00:00Z',
      'pdfReferences': ['../Old%20Lecture.PDF', '/second.pdf'],
    },
    {
      'name': 'Alpha',
      'path': 'drive1',
      'backendId': 'gdrive:one',
      'readablePath': '/Physics/Quantum Notes',
      'modified': '2025-01-02T13:00:00+01:00',
    },
    {
      'name': 'alpha',
      'path': '/bad%ZZ.xopp',
      'backendId': 'gdrive:two',
      'modified': 'not-a-date',
    },
    {'name': 'Gamma', 'path': 'internal-id', 'backendId': 'internal'},
    {
      'name': 'Beta',
      'path': '/other',
      'backendId': 'nextcloud:offline',
      'modified': '2026-01-01T00:00:00Z',
    },
  ];
  List<String> names(List<Map<String, dynamic>> list) =>
      list.map((e) => e['name'] as String).toList();
  test(
    'searches titles, decoded paths, readable folders and every PDF reference',
    () {
      expect(names(selectRecentFiles(entries, query: 'FOO BAR')), ['zebra']);
      expect(names(selectRecentFiles(entries, query: 'OLD LECTURE.pdf')), [
        'zebra',
      ]);
      expect(names(selectRecentFiles(entries, query: 'SECOND.PDF')), ['zebra']);
      expect(names(selectRecentFiles(entries, query: 'quantum notes')), [
        'Alpha',
      ]);
      final renamed = <Map<String, dynamic>>[
        {...entries[1], 'name': 'New Title', 'readableName': 'Original.xopp'},
      ];
      expect(
        names(selectRecentFiles(renamed, query: 'quantum notes/original.xopp')),
        ['New Title'],
      );
      expect(
        selectRecentFiles(renamed, query: 'quantum notes/new title.xopp'),
        isEmpty,
      );
      expect(names(selectRecentFiles(entries, query: 'ALPHA')), [
        'Alpha',
        'alpha',
      ]);
      expect(names(selectRecentFiles(entries, query: 'bad%zz')), ['alpha']);
      expect(selectRecentFiles(entries, query: 'not here'), isEmpty);
    },
  );
  test('filters by exact provider identity including legacy Local', () {
    expect(names(selectRecentFiles(entries, backendId: 'local')), ['zebra']);
    expect(names(selectRecentFiles(entries, backendId: 'gdrive:one')), [
      'Alpha',
    ]);
    expect(names(selectRecentFiles(entries, backendId: 'gdrive:two')), [
      'alpha',
    ]);
    expect(names(selectRecentFiles(entries, backendId: 'nextcloud:offline')), [
      'Beta',
    ]);
    expect(
      selectRecentFiles(entries, backendId: 'gdrive:one', query: 'zebra'),
      isEmpty,
    );
  });
  test(
    'sorts dates and titles both ways with missing dates last and stable ties',
    () {
      expect(names(selectRecentFiles(entries)), [
        'zebra',
        'Alpha',
        'alpha',
        'Gamma',
        'Beta',
      ]);
      expect(
        names(selectRecentFiles(entries, sort: RecentSort.modifiedNewest)),
        ['Beta', 'zebra', 'Alpha', 'alpha', 'Gamma'],
      );
      expect(
        names(selectRecentFiles(entries, sort: RecentSort.modifiedOldest)),
        ['zebra', 'Alpha', 'Beta', 'alpha', 'Gamma'],
      );
      expect(
        names(selectRecentFiles(entries, sort: RecentSort.titleAscending)),
        ['Alpha', 'alpha', 'Beta', 'Gamma', 'zebra'],
      );
      expect(
        names(selectRecentFiles(entries, sort: RecentSort.titleDescending)),
        ['zebra', 'Gamma', 'Beta', 'Alpha', 'alpha'],
      );
      expect(entries.first['name'], 'zebra');
    },
  );
  test(
    'recent metadata preserves omitted values, clears known PDFs and remains scoped',
    () async {
      SharedPreferences.setMockInitialValues({});
      await RecentFiles.remember(
        path: 'same',
        name: 'A',
        currentPage: 0,
        backendId: 'gdrive:one',
        pdfReferences: ['a.pdf', 'a.pdf', 'b.pdf', ''],
        readablePath: '/Physics',
        providerLabel: 'Drive A',
        readableName: 'Actual.xopp',
      );
      await RecentFiles.remember(
        path: 'same',
        name: 'B',
        currentPage: 0,
        backendId: 'gdrive:two',
        pdfReferences: ['other.pdf'],
      );
      await RecentFiles.remember(
        path: 'same',
        name: 'A2',
        currentPage: 1,
        backendId: 'gdrive:one',
      );
      var records =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  PreferencesKeys.kRecentFiles,
                )!,
              )
              as List;
      final a = records.last as Map;
      expect(a['pdfReferences'], ['a.pdf', 'b.pdf']);
      expect(a['readablePath'], '/Physics');
      expect(a['providerLabel'], 'Drive A');
      expect(a['readableName'], 'Actual.xopp');
      expect((records.first as Map)['pdfReferences'], ['other.pdf']);
      await RecentFiles.remember(
        path: 'same',
        name: 'A2',
        currentPage: 1,
        backendId: 'gdrive:one',
        pdfReferences: [],
      );
      await RecentFiles.updatePage('same', 3, backendId: 'gdrive:one');
      records =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  PreferencesKeys.kRecentFiles,
                )!,
              )
              as List;
      expect((records.last as Map)['pdfReferences'], isEmpty);
      expect((records.last as Map)['readablePath'], '/Physics');
      expect((records.last as Map)['readableName'], 'Actual.xopp');
      await RecentFiles.forget('same', backendId: 'gdrive:one');
      records =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  PreferencesKeys.kRecentFiles,
                )!,
              )
              as List;
      expect(records, hasLength(1));
      expect((records.single as Map)['backendId'], 'gdrive:two');
    },
  );
  test(
    'observed modification fills missing dates without replacing a newer save',
    () async {
      SharedPreferences.setMockInitialValues({});
      final newer = DateTime.utc(2026, 1, 2);
      final older = DateTime.utc(2025, 1, 2);
      await RecentFiles.remember(
        path: 'x',
        name: 'X',
        currentPage: 0,
        knownModified: older,
      );
      var record =
          (jsonDecode(
                        (await SharedPreferences.getInstance()).getString(
                          PreferencesKeys.kRecentFiles,
                        )!,
                      )
                      as List)
                  .single
              as Map;
      expect(record['modified'], older.toIso8601String());
      await RecentFiles.remember(
        path: 'x',
        name: 'X',
        currentPage: 0,
        modified: newer,
      );
      await RecentFiles.remember(
        path: 'x',
        name: 'X',
        currentPage: 0,
        knownModified: older,
      );
      record =
          (jsonDecode(
                        (await SharedPreferences.getInstance()).getString(
                          PreferencesKeys.kRecentFiles,
                        )!,
                      )
                      as List)
                  .single
              as Map;
      expect(record['modified'], newer.toIso8601String());
    },
  );
  test('parsed inherited PDF references are available for indexing', () async {
    final bytes = Uint8List.fromList(
      const GZipEncoder().encode(
        utf8.encode('''<xournal>
      <page width="200" height="300"><background type="pdf" filename="lecture.pdf" pageno="1"/><layer/></page>
      <page width="200" height="300"><background type="pdf" pageno="2"/><layer/></page>
      <page width="200" height="300"><background type="pdf" filename="second.pdf" pageno="1"/><layer/></page>
      </xournal>'''),
      ),
    );
    final file = await XppFile.fromXppPickedFile(
      XppPickedFile(bytes, fileName: 'test.xopp'),
      null,
      (_, _) => throw StateError('No PDF read'),
    );
    expect(file.pdfReferences, ['lecture.pdf', 'second.pdf']);
  });
  testWidgets('recent header adapts to available width', (tester) async {
    SharedPreferences.setMockInitialValues({
      PreferencesKeys.kRecentFiles: jsonEncode(entries),
    });
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(XournalppMobile());
    await tester.pumpAndSettle();
    final title = find.text('Recent Notebooks & Documents');
    final search = find.byType(TextField);
    expect(
      tester.getTopLeft(title).dy,
      closeTo(
        tester.getCenter(search).dy - tester.getSize(title).height / 2,
        2,
      ),
    );
    final border =
        tester.widget<TextField>(search).decoration!.border
            as OutlineInputBorder;
    expect(border.borderRadius, BorderRadius.circular(24));
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.binding.setSurfaceSize(const Size(400, 900));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(search).dy,
      greaterThan(tester.getBottomLeft(title).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'search controls remain usable on a small phone with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.kRecentFiles: jsonEncode(entries),
      });
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
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const OpenPage(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      final search = find.byType(TextField);
      await tester.ensureVisible(search);
      await tester.enterText(search, 'not here');
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -800),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No recent documents match these filters.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Clear filters'));
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(
        find.text('No recent documents match these filters.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'disconnected connections with colliding short IDs remain distinguishable',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.kRecentFiles: jsonEncode([
          {
            'name': 'One',
            'path': 'one',
            'backendId': 'gdrive:first12345678',
            'providerLabel': 'Google Drive · Alice',
          },
          {
            'name': 'Two',
            'path': 'two',
            'backendId': 'gdrive:second12345678',
            'providerLabel': 'Google Drive · Alice',
          },
        ]),
      });
      await tester.pumpWidget(XournalppMobile());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      final field = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byType(DropdownButtonFormField<String>),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      String label(String id) =>
          (field.items!.singleWhere((item) => item.value == id).child
                  as Tooltip)
              .message!;
      final first = label('gdrive:first12345678');
      final second = label('gdrive:second12345678');
      expect(first, isNot(second));
      expect(first, contains('Unavailable'));
      expect(second, contains('Unavailable'));
      expect(first, contains('Alice'));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'searching existing recents never reads their storage providers',
    (tester) async {
      final backend = _CountingProvider();
      notebookStorageBackends.add(backend);
      addTearDown(() => notebookStorageBackends.remove(backend));
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.kRecentFiles: jsonEncode(entries),
      });
      await tester.pumpWidget(XournalppMobile());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'unindexed.pdf');
      await tester.pumpAndSettle();
      expect(
        find.text('No recent documents match these filters.'),
        findsOneWidget,
      );
      expect(backend.reads, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('search and clear filters show matching and empty states', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      PreferencesKeys.kRecentFiles: jsonEncode(entries),
    });
    await tester.pumpWidget(XournalppMobile());
    await tester.pumpAndSettle();
    final search = find.byType(TextField);
    await tester.ensureVisible(search);
    await tester.enterText(search, 'old lecture.pdf');
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DocumentCard), findsOneWidget);
    expect(
      tester.widget<DocumentCard>(find.byType(DocumentCard)).name,
      'zebra',
    );
    await tester.ensureVisible(search);
    await tester.enterText(search, 'not present');
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.text('No recent documents match these filters.'),
    );
    expect(find.byType(DocumentCard), findsNothing);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, '');
    expect(find.text('No recent documents match these filters.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'active searches update as recents change and reset on reopening',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        PreferencesKeys.kRecentFiles: jsonEncode(entries),
      });
      await tester.pumpWidget(XournalppMobile());
      await tester.pumpAndSettle();
      final search = find.byType(TextField);
      await tester.ensureVisible(search);
      await tester.enterText(search, 'new-material.pdf');
      await tester.pumpAndSettle();
      expect(
        find.text('No recent documents match these filters.'),
        findsOneWidget,
      );
      await tester.runAsync(
        () => RecentFiles.remember(
          path: 'new',
          name: 'New record',
          backendId: 'internal',
          currentPage: 0,
          pdfReferences: ['new-material.pdf'],
        ),
      );
      for (
        var i = 0;
        i < 100 &&
            find
                .text('No recent documents match these filters.')
                .evaluate()
                .isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        find.text('No recent documents match these filters.'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(XournalppMobile());
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      await tester.ensureVisible(find.byIcon(Icons.filter_list));
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<RecentSort>>(
              find.byType(DropdownButtonFormField<RecentSort>),
            )
            .initialValue,
        RecentSort.recent,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('provider and sorting menus filter by connection and order', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      PreferencesKeys.kRecentFiles: jsonEncode(entries),
    });
    await tester.pumpWidget(XournalppMobile());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.filter_list));
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    final provider = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(provider);
    await tester.tap(provider);
    await tester.pumpAndSettle();
    final item = find
        .byWidgetPredicate(
          (widget) =>
              widget is DropdownMenuItem<String> &&
              widget.value == 'gdrive:two',
        )
        .last;
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<DocumentCard>(find.byType(DocumentCard)).name,
      'alpha',
    );
    await tester.ensureVisible(find.byIcon(Icons.filter_list));
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.ensureVisible(provider);
    await tester.tap(provider);
    await tester.pumpAndSettle();
    await tester.tap(find.text('All storage').last);
    await tester.pumpAndSettle();
    final sort = find.byType(DropdownButtonFormField<RecentSort>);
    await tester.ensureVisible(sort);
    await tester.tap(sort);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title: A–Z').last);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    final cards = tester
        .widgetList<DocumentCard>(find.byType(DocumentCard))
        .toList();
    expect(
      cards.first.name,
      'alpha',
    ); // Same title ties retain original recent order.
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 700),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.filter_list));
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.ensureVisible(provider);
    await tester.tap(provider);
    await tester.pumpAndSettle();
    final sameProvider = find
        .byWidgetPredicate(
          (widget) =>
              widget is DropdownMenuItem<String> &&
              widget.value == 'gdrive:two',
        )
        .last;
    await tester.ensureVisible(sameProvider);
    await tester.tap(sameProvider);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    final search = find.byType(TextField);
    await tester.ensureVisible(search);
    await tester.enterText(search, 'does not exist');
    await tester.pumpAndSettle();
    final emptyMessage = find.text('No recent documents match these filters.');
    await tester.ensureVisible(emptyMessage);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, '');
    await tester.ensureVisible(find.byIcon(Icons.filter_list));
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DropdownButtonFormField<String>>(provider).initialValue,
      '',
    );
    expect(
      tester.widget<DropdownButtonFormField<RecentSort>>(sort).initialValue,
      RecentSort.recent,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
