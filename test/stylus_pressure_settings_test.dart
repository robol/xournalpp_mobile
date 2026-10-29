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
  testWidgets('pressure setting defaults on and persists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Widget settings() => MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      home: const SettingsPage(),
    );
    await tester.pumpWidget(settings());
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(
      SwitchListTile,
      'Stylus pressure sensitivity',
    );
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getBool(
        PreferencesKeys.kStylusPressureSensitivity,
      ),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(settings());
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
  });

  testWidgets('stylus pressure changes captured widths only when enabled', (
    tester,
  ) async {
    Future<XppStroke> draw({
      PointerDeviceKind kind = PointerDeviceKind.stylus,
      bool enabled = true,
      double min = 0,
      double max = 1,
      double first = 0.2,
      double last = 0.8,
      EditingTool tool = EditingTool.STYLUS,
    }) async {
      XppStroke? saved;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PointerListener(
            stylusPressureSensitivity: enabled,
            toolData: {kind: tool},
            strokeWidth: 10,
            highlighterWidth: 6,
            color: Colors.black,
            highlighterColor: Colors.yellow,
            onNewContent: (content) => saved = content as XppStroke?,
            child: const SizedBox(width: 200, height: 200),
          ),
        ),
      );
      await tester.sendEventToBinding(
        PointerDownEvent(
          pointer: 1,
          kind: kind,
          position: const Offset(20, 20),
          pressure: first,
          pressureMin: min,
          pressureMax: max,
        ),
      );
      await tester.sendEventToBinding(
        PointerMoveEvent(
          pointer: 1,
          kind: kind,
          position: const Offset(40, 20),
          pressure: last,
          pressureMin: min,
          pressureMax: max,
        ),
      );
      await tester.sendEventToBinding(
        PointerUpEvent(pointer: 1, kind: kind, position: const Offset(40, 20)),
      );
      await tester.pump();
      return saved!;
    }

    final stroke = await draw();
    expect(stroke.points!.first.width, closeTo(2, 0.001));
    expect(stroke.points!.last.width, closeTo(8, 0.001));
    expect(
      stroke.toXmlElement().getAttribute('width')!.split(' ').toSet().length,
      greaterThan(1),
    );
    for (final fixed in [
      await draw(enabled: false),
      await draw(kind: PointerDeviceKind.mouse),
      await draw(kind: PointerDeviceKind.touch),
      await draw(min: 1, max: 1),
      await draw(first: double.nan, last: double.nan),
    ]) {
      expect(fixed.points!.every((point) => point.width == 10), isTrue);
    }
    final inverted = await draw(kind: PointerDeviceKind.invertedStylus);
    expect(inverted.points!.first.width, closeTo(2, 0.001));
    final highlight = await draw(tool: EditingTool.HIGHLIGHT);
    expect(highlight.points!.every((point) => point.width == 6), isTrue);
    final clamped = await draw(first: -1, last: 2);
    expect(clamped.points!.first.width, closeTo(1, 0.001));
    expect(clamped.points!.last.width, closeTo(10, 0.001));
  });
}
