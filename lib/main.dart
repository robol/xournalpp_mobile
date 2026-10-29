import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xournalpp/pages/OpenPage.dart';

import 'generated/l10n.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

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
  color: kLightColor,
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
      .copyWith(color: kLightColor)
      .copyWith(fontSize: kLargeFontSize * kFontSizeDivision),
  headlineSmall: kLargeFont.copyWith(color: kLightColor),
  titleLarge: kLargeFont.copyWith(color: kLightColor),
  titleMedium: kLargeFont.copyWith(color: kLightColor),
  bodyLarge: kBodyFont,
  bodyMedium: kBodyFont,
  bodySmall: kBodyFont.copyWith(color: const Color(0xffb0bec5)),
  labelLarge: kBodyFont,
);

// Shared workspace palette for every route and Material overlay.
final kColorScheme = ColorScheme.dark(
  primary: kPrimaryColor,
  onPrimary: kDarkColor!,
  primaryContainer: const Color(0xff244e63),
  onPrimaryContainer: kLightColor,
  secondary: kSecondaryColorAccent,
  onSecondary: kDarkColor!,
  secondaryContainer: const Color(0xff563543),
  onSecondaryContainer: kLightColor,
  surface: kDarkColor!,
  surfaceContainerLow: const Color(0xff2b3940),
  surfaceContainer: const Color(0xff304047),
  surfaceContainerHigh: const Color(0xff34454d),
  surfaceContainerHighest: const Color(0xff40535c),
  onSurface: kLightColor,
  onSurfaceVariant: const Color(0xffb0bec5),
  outline: const Color(0xff78909c),
  outlineVariant: const Color(0xff455a64),
  error: const Color(0xffffb4ab),
  onError: const Color(0xff690005),
);

final kDialogTheme = DialogThemeData(
  backgroundColor: kColorScheme.surfaceContainerHigh,
  surfaceTintColor: Colors.transparent,
  titleTextStyle: kLargeFont,
  contentTextStyle: kBodyFont.copyWith(color: kLightColor),
);

final kTextButtonTheme = TextButtonThemeData(
  style: TextButton.styleFrom(foregroundColor: kColorScheme.primary),
);

final kSnackBarTheme = SnackBarThemeData(
  backgroundColor: kColorScheme.surfaceContainerHigh,
  actionTextColor: kColorScheme.primary,
  contentTextStyle: kBodyFont.copyWith(color: kLightColor),
);

final kAppTheme = ThemeData(
  brightness: Brightness.dark,
  fontFamily: 'Open Sans',
  textTheme: kTextTheme.apply(
    bodyColor: kLightColor,
    displayColor: kLightColor,
  ),
  scaffoldBackgroundColor: kColorScheme.surface,
  colorScheme: kColorScheme,
  cardColor: kColorScheme.surfaceContainerHigh,
  visualDensity: VisualDensity.adaptivePlatformDensity,
  appBarTheme: AppBarTheme(
    backgroundColor: kColorScheme.surface,
    foregroundColor: kColorScheme.onSurface,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
    elevation: 0,
  ),
  bottomAppBarTheme: BottomAppBarThemeData(
    color: kColorScheme.surfaceContainer,
    surfaceTintColor: Colors.transparent,
  ),
  drawerTheme: DrawerThemeData(
    backgroundColor: kColorScheme.surfaceContainer,
    surfaceTintColor: Colors.transparent,
  ),
  bottomSheetTheme: BottomSheetThemeData(
    backgroundColor: kColorScheme.surfaceContainerHigh,
    modalBackgroundColor: kColorScheme.surfaceContainerHigh,
    surfaceTintColor: Colors.transparent,
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: kColorScheme.surfaceContainerHigh,
    surfaceTintColor: Colors.transparent,
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: kColorScheme.primaryContainer,
    foregroundColor: kColorScheme.onPrimaryContainer,
  ),
  listTileTheme: ListTileThemeData(
    textColor: kColorScheme.onSurface,
    iconColor: kColorScheme.onSurfaceVariant,
    subtitleTextStyle: kBodyFont.copyWith(color: kColorScheme.onSurfaceVariant),
  ),
  dialogTheme: kDialogTheme,
  textButtonTheme: kTextButtonTheme,
  snackBarTheme: kSnackBarTheme,
);

class XournalppMobile extends StatefulWidget {
  @override
  State<XournalppMobile> createState() => _XournalppMobileState();
}

class _XournalppMobileState extends State<XournalppMobile> {
  static const _intentChannel = MethodChannel('it.robol.xournal.mobile/intent');
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _drainingIntents = false;
  bool _intentNotificationPending = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _intentChannel.setMethodCallHandler((call) async {
        if (call.method == 'openIntentsAvailable') _drainIntents();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _drainIntents());
    }
  }

  Future<void> _drainIntents() async {
    if (!mounted) return;
    if (_drainingIntents) {
      _intentNotificationPending = true;
      return;
    }
    _drainingIntents = true;
    try {
      do {
        _intentNotificationPending = false;
        final intents = await _intentChannel.invokeListMethod<dynamic>(
          'takeOpenIntents',
        );
        for (final intent in intents ?? const []) {
          if (!mounted) return;
          await _navigatorKey.currentState?.push(
            MaterialPageRoute<void>(
              builder: (_) => OpenPage(initialExternalIntent: intent),
            ),
          );
        }
      } while (mounted && _intentNotificationPending);
    } on MissingPluginException {
      // The native channel is unavailable in widget tests and non-Android hosts.
    } finally {
      _drainingIntents = false;
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _intentChannel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
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
      themeMode: ThemeMode.dark,
      theme: kAppTheme,
      darkTheme: kAppTheme,
      home: OpenPage(),
    );
  }
}
