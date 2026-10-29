import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/main.dart';
import 'package:xournalpp/pages/CanvasPage.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/pages/SettingsPage.dart';
import 'package:xournalpp/src/XppFile.dart';
import 'package:xournalpp/widgets/ToolSettingDialog.dart';
import 'package:xournalpp/widgets/XppPageStack.dart';

void main() {
  for (final platformBrightness in Brightness.values) {
    testWidgets('routes share workspace colors with $platformBrightness OS', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.platformDispatcher.platformBrightnessTestValue =
          platformBrightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(XournalppMobile());
      await tester.pumpAndSettle();
      final homeContext = tester.element(find.byType(OpenPage));
      final homeTheme = Theme.of(homeContext);
      expect(homeTheme.brightness, Brightness.dark);
      expect(homeTheme.scaffoldBackgroundColor, const Color(0xff263238));

      void checkRouteTheme(Finder route) {
        final theme = Theme.of(tester.element(route));
        expect(theme.colorScheme, homeTheme.colorScheme);
        expect(
          theme.appBarTheme.backgroundColor,
          homeTheme.colorScheme.surface,
        );
        expect(
          theme.appBarTheme.foregroundColor,
          homeTheme.colorScheme.onSurface,
        );
        expect(
          theme.textTheme.titleLarge!.color,
          homeTheme.colorScheme.onSurface,
        );
        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(
          appBar.backgroundColor ?? theme.appBarTheme.backgroundColor,
          homeTheme.colorScheme.surface,
        );
      }

      final navigator = Navigator.of(homeContext);
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
      );
      await tester.pumpAndSettle();
      checkRouteTheme(find.byType(SettingsPage));
      expect(find.byType(SwitchListTile), findsNWidgets(3));
      navigator.pop();
      await tester.pumpAndSettle();
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => CanvasPage(file: XppFile.empty()),
        ),
      );
      await tester.pumpAndSettle();
      checkRouteTheme(find.byType(CanvasPage));
      final paper = find.descendant(
        of: find.byType(XppPageStack),
        matching: find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == Colors.white,
        ),
      );
      expect(paper, findsWidgets);

      final canvasContext = tester.element(find.byType(CanvasPage));
      showDialog<void>(
        context: canvasContext,
        builder: (_) => ToolSettingDialog(width: 1, color: Colors.black),
      );
      await tester.pumpAndSettle();
      final dialogContext = tester.element(find.byType(ToolSettingDialog));
      expect(Theme.of(dialogContext).colorScheme, homeTheme.colorScheme);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color ==
                  homeTheme.colorScheme.surfaceContainerHigh,
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
