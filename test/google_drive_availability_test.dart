import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/SettingsPage.dart';
import 'package:xournalpp/pages/GoogleDriveSettingsPage.dart';
import 'package:xournalpp/src/GoogleDriveManager.dart';
import 'package:xournalpp/src/globals.dart';

void main() {
  test(
    'disabled Drive cannot authenticate or restore saved configuration',
    () async {
      SharedPreferences.setMockInitialValues({
        'googleDrive.folder.v1': '{"accountId":"existing","folderId":"root"}',
      });
      expect(googleDriveEnabled, isFalse);
      expect(GoogleDriveManager.available, isFalse);
      await expectLater(GoogleDriveManager.connect(), throwsUnsupportedError);
      expect(
        () => GoogleDriveManager.forFolder('root'),
        throwsUnsupportedError,
      );
      await GoogleDriveManager.restore();
      expect(GoogleDriveManager.current, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('googleDrive.folder.v1'), isTrue);
    },
  );

  testWidgets('Drive stays visible but disabled in settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: const SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(ListTile, 'Google Drive');
    expect(tile, findsOneWidget);
    expect(tester.widget<ListTile>(tile).enabled, isFalse);
    expect(tester.widget<ListTile>(tile).onTap, isNull);
    expect(
      find.text('Unavailable pending Google API approval'),
      findsOneWidget,
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(GoogleDriveSettingsPage), findsNothing);
  });
}
