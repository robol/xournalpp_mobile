
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:xournalpp/pages/OpenPage.dart';

import 'generated/l10n.dart';

void main() {
  /*
  /// STEP 1. Create catcher configuration.
  /// Debug configuration with dialog report mode and console handler. It will show dialog and once user accepts it, error will be shown   /// in console.
  CatcherOptions debugOptions = CatcherOptions(DialogReportMode(), [
    ConsoleHandler(),
  ]);

  /// Release configuration. Same as above, but once user accepts dialog, user will be prompted to send email with crash to support.
  CatcherOptions releaseOptions = CatcherOptions(DialogReportMode(), [
    EmailManualHandler(["leo@robol.it"])
  ]);

  /// STEP 2. Pass your root widget (MyApp) along with Catcher configuration:
  Catcher(XournalppMobile(),
      debugConfig: debugOptions, releaseConfig: releaseOptions);*/
  runApp(XournalppMobile());
}

const Color kPrimaryColor = Colors.lightBlue;
const Color kPrimaryColorAccent = Colors.deepPurpleAccent;
const Color kSecondaryColor = Colors.pink;
const Color kSecondaryColorAccent = Colors.pinkAccent;
final Color? kDarkColor = Colors.blueGrey[900];
const Color kLightColor = Colors.white;

const double kFontSizeDivision = 1.6;

const double kHugeFontSize = 72 / kFontSizeDivision;
const double kLargeFontSize = 28 / kFontSizeDivision;
const double kBodyFontSize = 24 / kFontSizeDivision;
const double kEmphasisFontSize = 25.2 / kFontSizeDivision;

const TextStyle kHugeFont = TextStyle(
  fontFamily: 'Open Sans',
  fontWeight: FontWeight.w800,
  color: kSecondaryColor,
  height: 1.4,
  fontSize: kHugeFontSize,
);
final TextStyle kLargeFont = TextStyle(
  fontFamily: 'Open Sans',
  fontSize: kLargeFontSize,
  color: kLightColor,
  height: 1.4,
);
const TextStyle kBodyFont = TextStyle(
  fontFamily: 'Open Sans',
  fontWeight: FontWeight.w300,
  height: 1.4,
  fontSize: kBodyFontSize,
);
const TextStyle kEmphasisFont = TextStyle(
  fontFamily: 'Glacial Indifference',
  fontSize: kEmphasisFontSize,
  height: 1.22,
  letterSpacing: 1.8,
);

final kTextTheme = TextTheme(
  displayLarge: kHugeFont,
  displayMedium: kHugeFont,
  headlineMedium: kLargeFont
      .copyWith(color: kDarkColor)
      .copyWith(fontSize: kLargeFontSize * kFontSizeDivision),
  headlineSmall: kLargeFont.copyWith(color: kDarkColor),
  titleLarge: kLargeFont.copyWith(color: kDarkColor),
  titleMedium: kLargeFont.copyWith(color: kDarkColor),
  bodyLarge: kBodyFont,
  bodyMedium: kBodyFont,
  bodySmall: kBodyFont,
  labelLarge: kBodyFont,
);

final kColorScheme = ColorScheme(
  primary: kPrimaryColor,
  secondary: kSecondaryColor,
  surface: kDarkColor!,
  error: Colors.deepOrange,
  onPrimary: kLightColor,
  onSecondary: kDarkColor!,
  onSurface: kLightColor,
  onError: kLightColor,
  brightness: Brightness.dark,
);

final kDialogTheme = DialogThemeData(
  backgroundColor: kDarkColor,
  titleTextStyle: kLargeFont.copyWith(color: kLightColor),
  contentTextStyle: kBodyFont.copyWith(color: kLightColor),
);

final kTextButtonTheme = TextButtonThemeData(
  style: TextButton.styleFrom(foregroundColor: kSecondaryColorAccent),
);

final kSnackBarTheme = SnackBarThemeData(
  backgroundColor: kDarkColor,
  actionTextColor: kSecondaryColorAccent,
  contentTextStyle: kBodyFont,
);

class XournalppMobile extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: kIsWeb ? 'Xournal++ Web' : 'Xournal++ Mobile',
      localizationsDelegates: [
        S.delegate,
        DefaultMaterialLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      theme: ThemeData(
        primarySwatch: kPrimaryColor as MaterialColor?,
        fontFamily: 'Open Sans',
        textTheme: kTextTheme,
        scaffoldBackgroundColor: kDarkColor,
        colorScheme: kColorScheme.copyWith(brightness: Brightness.light),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        dialogTheme: kDialogTheme,
        textButtonTheme: kTextButtonTheme,
        snackBarTheme: kSnackBarTheme,
      ),
      darkTheme: ThemeData(
        primarySwatch: kPrimaryColor as MaterialColor?,
        fontFamily: 'Open Sans',
        textTheme: kTextTheme,
        scaffoldBackgroundColor: kDarkColor,
        colorScheme: kColorScheme,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        dialogTheme: kDialogTheme,
        textButtonTheme: kTextButtonTheme,
        snackBarTheme: kSnackBarTheme,
      ),
      home: OpenPage(),
    );
  }
}
