import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/layer_contents/XppStroke.dart';
import 'package:xournalpp/pages/SettingsPage.dart';
import 'package:xournalpp/src/globals.dart';
import 'package:xournalpp/widgets/PointerListener.dart';
import 'package:xournalpp/widgets/ToolBoxBottomSheet.dart';

void main() {
  testWidgets('setting defaults on and persists changes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: const SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(SwitchListTile, 'Simplify strokes');
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getBool(
        PreferencesKeys.kSimplifyStrokes,
      ),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: const SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
  });

  testWidgets('switch controls points committed by pointer listener', (
    tester,
  ) async {
    Future<int> draw(bool simplify) async {
      XppStroke? saved;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PointerListener(
            simplifyStrokes: simplify,
            toolData: const {PointerDeviceKind.stylus: EditingTool.STYLUS},
            strokeWidth: 2,
            color: Colors.black,
            onNewContent: (content) => saved = content as XppStroke?,
            child: const SizedBox(width: 200, height: 200),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        const Offset(20, 20),
        kind: PointerDeviceKind.stylus,
      );
      for (var i = 1; i <= 30; i++) {
        await gesture.moveTo(Offset(20 + i.toDouble(), 20));
      }
      await gesture.up();
      await tester.pump();
      return saved!.points!.length;
    }

    final enabled = await draw(true);
    final disabled = await draw(false);
    expect(enabled, lessThan(disabled));
  });
}
