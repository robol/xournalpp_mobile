// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a en locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'en';

  static String m0(name) =>
      "An unsaved draft of ${name} was found. Recover it?";

  static String m1(date) => "Last modified: ${date}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "abort": MessageLookupByLibrary.simpleMessage("Abort"),
    "about": MessageLookupByLibrary.simpleMessage("About"),
    "aboutXournal": MessageLookupByLibrary.simpleMessage("About Xournal++"),
    "aboutXournalMobileEdition": MessageLookupByLibrary.simpleMessage(
      "About Xournal++ Mobile",
    ),
    "addPage": MessageLookupByLibrary.simpleMessage("Add page"),
    "alsoDeleteFile": MessageLookupByLibrary.simpleMessage(
      "Also delete the file from the device (cannot be undone)",
    ),
    "apply": MessageLookupByLibrary.simpleMessage("Apply"),
    "areYouSureIHaveThePermissionAndAreYou":
        MessageLookupByLibrary.simpleMessage(
          ". Are you sure I have the permission? And are you sure it is a Xournal++ file?",
        ),
    "areYouSureToDeleteTheSelectedFileThisCannot":
        MessageLookupByLibrary.simpleMessage(
          "Remove this document from the recent list? The file will remain on your device unless you choose to delete it.",
        ),
    "background": MessageLookupByLibrary.simpleMessage("Background"),
    "between1And": MessageLookupByLibrary.simpleMessage("Between 1 and"),
    "cacheBrowse": MessageLookupByLibrary.simpleMessage("Cached notebooks"),
    "cacheCheckpoint": MessageLookupByLibrary.simpleMessage("Local checkpoint"),
    "cacheClear": MessageLookupByLibrary.simpleMessage("Clear cache"),
    "cacheClearConfirm": MessageLookupByLibrary.simpleMessage(
      "Delete all cached notebooks and PDFs? Recovery drafts will be kept.",
    ),
    "cacheEmpty": MessageLookupByLibrary.simpleMessage(
      "No cached notebooks are available.",
    ),
    "cacheIncomplete": MessageLookupByLibrary.simpleMessage(
      "Some PDF backgrounds are missing.",
    ),
    "cacheLimit": MessageLookupByLibrary.simpleMessage("Cache storage limit"),
    "cacheLimitDescription": MessageLookupByLibrary.simpleMessage(
      "Old confirmed copies are removed first. Unsaved working copies are excluded from automatic cache trimming.",
    ),
    "cacheOpen": MessageLookupByLibrary.simpleMessage("Open cached copy"),
    "cacheOpenTitle": MessageLookupByLibrary.simpleMessage("Open cached copy?"),
    "cacheOverwrite": MessageLookupByLibrary.simpleMessage(
      "Overwrite original",
    ),
    "cacheOverwriteTitle": MessageLookupByLibrary.simpleMessage(
      "Overwrite original?",
    ),
    "cacheSaveCopy": MessageLookupByLibrary.simpleMessage("Save a copy"),
    "cacheSaved": MessageLookupByLibrary.simpleMessage(
      "Last confirmed version",
    ),
    "cacheSetting": MessageLookupByLibrary.simpleMessage(
      "Local notebook cache",
    ),
    "cacheSettingDescription": MessageLookupByLibrary.simpleMessage(
      "Keep local copies of notebooks and PDF backgrounds for provider failures. Storage usage can grow. Turning this off retains existing copies until cleared.",
    ),
    "cacheUnavailable": MessageLookupByLibrary.simpleMessage(
      "The local cache is unavailable.",
    ),
    "cacheUnlimited": MessageLookupByLibrary.simpleMessage("Unlimited"),
    "cacheUnsaved": MessageLookupByLibrary.simpleMessage(
      "Includes unsaved edits",
    ),
    "cacheUpdateFailed": MessageLookupByLibrary.simpleMessage(
      "The local copy could not be updated. The provider operation was not affected.",
    ),
    "cacheWarning": MessageLookupByLibrary.simpleMessage(
      "You are editing a cached copy. It may be outdated. Saving to the original location may overwrite newer changes.",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Cancel"),
    "close": MessageLookupByLibrary.simpleMessage("Close"),
    "color": MessageLookupByLibrary.simpleMessage("Color"),
    "confirmDelete": MessageLookupByLibrary.simpleMessage(
      "Forget recent document",
    ),
    "copyErrorMessage": MessageLookupByLibrary.simpleMessage(
      "Copy error message",
    ),
    "couldNotFindBackgroundPdfSelectNewOne":
        MessageLookupByLibrary.simpleMessage(
          "Could not find the background PDF. Select a new one",
        ),
    "delete": MessageLookupByLibrary.simpleMessage("Delete"),
    "deleteNotebookConfirm": MessageLookupByLibrary.simpleMessage(
      "Delete this notebook from its storage? This cannot be undone here. Recovery drafts will be kept. Google Drive notebooks will be moved to Trash.",
    ),
    "deletePage": MessageLookupByLibrary.simpleMessage("Delete page"),
    "dotted": MessageLookupByLibrary.simpleMessage("Dotted"),
    "doubleTapToChange": MessageLookupByLibrary.simpleMessage(
      "Double tap to change.",
    ),
    "drawStylusOnly": MessageLookupByLibrary.simpleMessage(
      "Draw with stylus only",
    ),
    "dropFilesToOpen": MessageLookupByLibrary.simpleMessage(
      "Drop files to open",
    ),
    "eraser": MessageLookupByLibrary.simpleMessage("Eraser"),
    "error": MessageLookupByLibrary.simpleMessage("Error"),
    "errorLoadingFile": MessageLookupByLibrary.simpleMessage(
      "Error loading file",
    ),
    "errorOpeningFile": MessageLookupByLibrary.simpleMessage(
      "Error opening file",
    ),
    "exportingPdf": MessageLookupByLibrary.simpleMessage("Exporting PDF..."),
    "fingerPanHint": MessageLookupByLibrary.simpleMessage(
      "Finger touches pan the page instead of drawing.",
    ),
    "forgetRecent": MessageLookupByLibrary.simpleMessage("Forget"),
    "forkedBy": MessageLookupByLibrary.simpleMessage(
      "This code has been forked by xournalpp_mobile from @TheOneWithTheBraid, and is mostly based on her work",
    ),
    "googleDriveConnect": MessageLookupByLibrary.simpleMessage(
      "Connect Google Drive",
    ),
    "googleDriveConnected": MessageLookupByLibrary.simpleMessage("Connected"),
    "graph": MessageLookupByLibrary.simpleMessage("Graph"),
    "highlighter": MessageLookupByLibrary.simpleMessage("Highlighter"),
    "home": MessageLookupByLibrary.simpleMessage("Home"),
    "imVerySorryButICouldntReadTheFile": MessageLookupByLibrary.simpleMessage(
      "I\'m very sorry, but I couldn\'t read the file ",
    ),
    "image": MessageLookupByLibrary.simpleMessage("Image"),
    "importPdf": MessageLookupByLibrary.simpleMessage("Import PDF"),
    "internalDelete": MessageLookupByLibrary.simpleMessage("Delete notebook"),
    "internalDeleteConfirm": MessageLookupByLibrary.simpleMessage(
      "Permanently delete this internal notebook and its stored PDF backgrounds?",
    ),
    "internalPdfExternalTitle": MessageLookupByLibrary.simpleMessage(
      "PDF backgrounds are not copied",
    ),
    "internalPdfExternalWarning": MessageLookupByLibrary.simpleMessage(
      "Local storage saves the notebook file only. PDF backgrounds kept in Internal storage may need to be located again. Keep the Internal notebook or retain the original PDFs separately.",
    ),
    "internalStorage": MessageLookupByLibrary.simpleMessage("Internal"),
    "invalidNotebookName": MessageLookupByLibrary.simpleMessage(
      "Enter a notebook name without slashes or control characters.",
    ),
    "latexNotImplemented": MessageLookupByLibrary.simpleMessage(
      "LaTeX (not implemented)",
    ),
    "lined": MessageLookupByLibrary.simpleMessage("Lined"),
    "loadingFile": MessageLookupByLibrary.simpleMessage("Loading file..."),
    "localStorage": MessageLookupByLibrary.simpleMessage("Local storage"),
    "mb": MessageLookupByLibrary.simpleMessage("MB"),
    "mobileEditionUnofficial": MessageLookupByLibrary.simpleMessage(
      "official mobile app",
    ),
    "move": MessageLookupByLibrary.simpleMessage("Move"),
    "moveCopyRetained": MessageLookupByLibrary.simpleMessage(
      "Copy saved, but the original could not be deleted. Both copies were kept. Saving now updates the destination.",
    ),
    "moveFailed": MessageLookupByLibrary.simpleMessage(
      "Could not move notebook. The original was kept. Choose another name if the destination already exists.",
    ),
    "moveNeedsFreshSource": MessageLookupByLibrary.simpleMessage(
      "Reopen the original from its storage before moving or renaming a cached notebook.",
    ),
    "movePage": MessageLookupByLibrary.simpleMessage("Move page"),
    "movePdfUnsafe": MessageLookupByLibrary.simpleMessage(
      "This notebook uses stored PDF backgrounds. Moving it to Local storage would leave those backgrounds dependent on the original storage. Use Save As instead.",
    ),
    "moveTo": MessageLookupByLibrary.simpleMessage("Move to…"),
    "newDocument": MessageLookupByLibrary.simpleMessage("New Document"),
    "newFile": MessageLookupByLibrary.simpleMessage("New"),
    "newNotebook": MessageLookupByLibrary.simpleMessage("New notebook"),
    "newPageIndex": MessageLookupByLibrary.simpleMessage("New page index"),
    "newTitle": MessageLookupByLibrary.simpleMessage("New title"),
    "nextcloudAddress": MessageLookupByLibrary.simpleMessage(
      "Nextcloud server address",
    ),
    "nextcloudCancelLogin": MessageLookupByLibrary.simpleMessage(
      "Cancel login",
    ),
    "nextcloudChooseFolder": MessageLookupByLibrary.simpleMessage(
      "Choose a folder",
    ),
    "nextcloudConnect": MessageLookupByLibrary.simpleMessage("Connect"),
    "nextcloudDisconnect": MessageLookupByLibrary.simpleMessage("Disconnect"),
    "nextcloudNotConnected": MessageLookupByLibrary.simpleMessage(
      "Not connected",
    ),
    "nextcloudParentFolder": MessageLookupByLibrary.simpleMessage(
      "Parent folder",
    ),
    "nextcloudReplace": MessageLookupByLibrary.simpleMessage("Replace"),
    "nextcloudReplaceMessage": MessageLookupByLibrary.simpleMessage(
      "A notebook with this name already exists. Replace it?",
    ),
    "nextcloudReplaceTitle": MessageLookupByLibrary.simpleMessage(
      "Replace notebook?",
    ),
    "nextcloudUseFolder": MessageLookupByLibrary.simpleMessage(
      "Use this folder",
    ),
    "noFileSelected": MessageLookupByLibrary.simpleMessage("No file selected"),
    "noRecentFiles": MessageLookupByLibrary.simpleMessage("No recent files."),
    "noSavedNotebooks": MessageLookupByLibrary.simpleMessage(
      "No saved notebooks yet.",
    ),
    "notImplemented": MessageLookupByLibrary.simpleMessage(
      " (not implemented)",
    ),
    "notWorkingYet": MessageLookupByLibrary.simpleMessage("Not working yet."),
    "notebookActionUnavailable": MessageLookupByLibrary.simpleMessage(
      "The storage provider is unavailable or does not support this action.",
    ),
    "notebookEditConflict": MessageLookupByLibrary.simpleMessage(
      "The notebook changed in storage. Save a separate copy to protect both versions.",
    ),
    "notebookMoved": MessageLookupByLibrary.simpleMessage("Notebook moved."),
    "okay": MessageLookupByLibrary.simpleMessage("Okay"),
    "open": MessageLookupByLibrary.simpleMessage("Open"),
    "openNavigation": MessageLookupByLibrary.simpleMessage("Open navigation"),
    "opening": MessageLookupByLibrary.simpleMessage("Opening"),
    "openingFile": MessageLookupByLibrary.simpleMessage("Opening file"),
    "pageBackground": MessageLookupByLibrary.simpleMessage("Page background"),
    "pdf": MessageLookupByLibrary.simpleMessage("PDF"),
    "pen": MessageLookupByLibrary.simpleMessage("Pen"),
    "quota": MessageLookupByLibrary.simpleMessage("Storage"),
    "recentBackendUnavailable": MessageLookupByLibrary.simpleMessage(
      "Storage is unavailable. Reconnect the original account and folder.",
    ),
    "recentFiles": MessageLookupByLibrary.simpleMessage("Recent files"),
    "recoveryDiscard": MessageLookupByLibrary.simpleMessage("Discard draft"),
    "recoveryLater": MessageLookupByLibrary.simpleMessage("Later"),
    "recoveryLoadFailed": MessageLookupByLibrary.simpleMessage(
      "Could not check for recovery drafts.",
    ),
    "recoveryMessage": m0,
    "recoveryOpen": MessageLookupByLibrary.simpleMessage("Recover"),
    "recoverySaveFailed": MessageLookupByLibrary.simpleMessage(
      "Could not save a recovery draft. Save your work manually.",
    ),
    "recoveryTitle": MessageLookupByLibrary.simpleMessage(
      "Recover unsaved work?",
    ),
    "removeSavedNotebook": MessageLookupByLibrary.simpleMessage(
      "Remove from saved notebooks",
    ),
    "renameFolderAccess": MessageLookupByLibrary.simpleMessage(
      "Select the notebook’s current folder to allow renaming. Choosing a different folder will cancel the operation.",
    ),
    "renameNotebook": MessageLookupByLibrary.simpleMessage("Rename"),
    "retrySourceDelete": MessageLookupByLibrary.simpleMessage("Retry deletion"),
    "ruled": MessageLookupByLibrary.simpleMessage("Ruled"),
    "safEditedCopy": MessageLookupByLibrary.simpleMessage(" (pending save)"),
    "safOriginalCopy": MessageLookupByLibrary.simpleMessage(
      " (before the interrupted save)",
    ),
    "safSaveFailed": MessageLookupByLibrary.simpleMessage(
      "The document provider did not confirm the save. Recovery copies are stored on this device. Reopen the app to recover them, then use Save As.",
    ),
    "save": MessageLookupByLibrary.simpleMessage("Save"),
    "saveAs": MessageLookupByLibrary.simpleMessage("Save as..."),
    "savedNotebooks": MessageLookupByLibrary.simpleMessage("Saved notebooks"),
    "savingFile": MessageLookupByLibrary.simpleMessage("Saving file..."),
    "selectColor": MessageLookupByLibrary.simpleMessage("Select color"),
    "selectNotImplemented": MessageLookupByLibrary.simpleMessage(
      "Select (not implemented)",
    ),
    "setDocumentTitle": MessageLookupByLibrary.simpleMessage(
      "Set document title",
    ),
    "settingsTitle": MessageLookupByLibrary.simpleMessage("Settings"),
    "shapeCircle": MessageLookupByLibrary.simpleMessage("Circle"),
    "shapeEllipse": MessageLookupByLibrary.simpleMessage("Ellipse"),
    "shapeLine": MessageLookupByLibrary.simpleMessage("Line"),
    "shapeOutlineColor": MessageLookupByLibrary.simpleMessage("Outline color"),
    "shapeRectangle": MessageLookupByLibrary.simpleMessage("Rectangle"),
    "shapeSquare": MessageLookupByLibrary.simpleMessage("Square"),
    "shapes": MessageLookupByLibrary.simpleMessage("Shapes"),
    "sharePage": MessageLookupByLibrary.simpleMessage("Share page..."),
    "simplifyStrokes": MessageLookupByLibrary.simpleMessage("Simplify strokes"),
    "simplifyStrokesDescription": MessageLookupByLibrary.simpleMessage(
      "Reduce points in newly drawn strokes to save space.",
    ),
    "sourceCode": MessageLookupByLibrary.simpleMessage("Source Code"),
    "stillSaving": MessageLookupByLibrary.simpleMessage(
      "Still saving. Keep this notebook open until the operation finishes.",
    ),
    "storageBackend": MessageLookupByLibrary.simpleMessage("Storage location"),
    "storageFolderOnboarding": MessageLookupByLibrary.simpleMessage(
      "After connecting, you will choose a folder. Documents must be in that folder or its subfolders.",
    ),
    "strokeWidth": MessageLookupByLibrary.simpleMessage("Stroke width:"),
    "stylusPressureSensitivity": MessageLookupByLibrary.simpleMessage(
      "Stylus pressure sensitivity",
    ),
    "stylusPressureSensitivityDescription":
        MessageLookupByLibrary.simpleMessage(
          "Adjust new pen stroke widths using stylus pressure when available.",
        ),
    "successfullySaved": MessageLookupByLibrary.simpleMessage(
      "Successfully saved.",
    ),
    "successfullyShared": MessageLookupByLibrary.simpleMessage(
      "Successfully shared",
    ),
    "textNotImplemented": MessageLookupByLibrary.simpleMessage(
      "Text (not implemented)",
    ),
    "theFollowingErrorWasDetected": MessageLookupByLibrary.simpleMessage(
      "The following error was detected:",
    ),
    "thereWereNoMorePagesWeAddedOne": MessageLookupByLibrary.simpleMessage(
      "There were no more pages. We added one.",
    ),
    "thumbnailSaveWarning": MessageLookupByLibrary.simpleMessage(
      "The notebook was saved, but its thumbnail could not be updated.",
    ),
    "tool": MessageLookupByLibrary.simpleMessage("Tool"),
    "toolboxNotImplementedYet": MessageLookupByLibrary.simpleMessage(
      "Toolbox not implemented yet.",
    ),
    "tools": MessageLookupByLibrary.simpleMessage("Tools"),
    "unfortunatelyThereWasAnErrorSavingThisFile":
        MessageLookupByLibrary.simpleMessage(
          "Unfortunately, there was an error saving this file.",
        ),
    "used": MessageLookupByLibrary.simpleMessage("used"),
    "whiteoutEraserNotImplemented": MessageLookupByLibrary.simpleMessage(
      "Whiteout eraser (not implemented)",
    ),
    "workspaceCreate": MessageLookupByLibrary.simpleMessage("Create Notebook"),
    "workspaceEmptyDescription": MessageLookupByLibrary.simpleMessage(
      "Create your first notebook or open an existing document to get started.",
    ),
    "workspaceEmptyTitle": MessageLookupByLibrary.simpleMessage(
      "Your workspace is ready",
    ),
    "workspaceModified": m1,
    "workspaceOpen": MessageLookupByLibrary.simpleMessage("Open Document"),
    "workspaceRecents": MessageLookupByLibrary.simpleMessage(
      "Recent Notebooks & Documents",
    ),
    "workspaceSubtitle": MessageLookupByLibrary.simpleMessage(
      "A Xournal++ compatible editor.",
    ),
    "workspaceTitle": MessageLookupByLibrary.simpleMessage("Your Workspace"),
    "xournalMobileEditionIsAnUnofficialProjectTryingToMake":
        MessageLookupByLibrary.simpleMessage(
          "Xournal++ Mobile is a project trying to make Xournal++ files and features available on different devices.",
        ),
    "youDidNotSelectAnyFile": MessageLookupByLibrary.simpleMessage(
      "You did not select any file.",
    ),
    "youveBeenRedirectedToTheLocalApp": MessageLookupByLibrary.simpleMessage(
      "You\'ve been redirected to the local app.",
    ),
  };
}
