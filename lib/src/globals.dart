/// Prevent palm contacts from starting gestures just after a pen lifts.
const stylusTouchCooldown = Duration(milliseconds: 500);

/// Enable once Google approves this application's Google Drive API usage.
const bool googleDriveEnabled = false;

dynamic lastIntentData;

class PreferencesKeys {
  static const String kRecentFiles = 'recentFiles';
  static const String kMissingPdfFileMappings = 'missingPdfFileMappings';
  static const String kToolColor = 'toolColor';
  static const String kHighlighterColor = 'highlighterColor';
  static const String kToolWidth = 'toolWidth';
  static const String kHighlighterWidth = 'highlighterWidth';
  static const String kEraserWidth = 'eraserWidth';
  static const String kDrawWithStylusOnly = 'drawWithStylusOnly';
  static const String kSimplifyStrokes = 'simplifyStrokes';
  static const String kStylusPressureSensitivity = 'stylusPressureSensitivity';
}
