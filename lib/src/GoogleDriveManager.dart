import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xournalpp/src/GoogleDriveStorage.dart';
import 'package:xournalpp/src/GoogleDesktopAuth.dart';
import 'package:xournalpp/src/NotebookStorage.dart';

/// Google SDK owns its platform credential store and access-token refresh.
class GoogleDriveManager {
  static const _configKey = 'googleDrive.folder.v1';
  static const _scope = 'https://www.googleapis.com/auth/drive';
  static const _webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const _iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static const _macosClientId = String.fromEnvironment(
    'GOOGLE_MACOS_CLIENT_ID',
  );
  static final changes = ValueNotifier<int>(0);
  static Future<void>? _initialization;
  static GoogleSignInAccount? _account;
  static DesktopGoogleAccount? _desktopAccount;
  static final _desktopAuth = GoogleDesktopAuth();
  static bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);
  static GoogleDriveStorage? get current =>
      notebookStorageBackends.whereType<GoogleDriveStorage>().firstOrNull;
  // Apple redirect schemes and desktop sign-in are not configured yet.
  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || _desktop);

  static Future<void> _initialize() {
    if (!supported)
      throw UnsupportedError(
        'Google Drive sign-in is unavailable on this platform.',
      );
    final clientId = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => _iosClientId,
      TargetPlatform.macOS => _macosClientId,
      _ => '',
    };
    if ((defaultTargetPlatform == TargetPlatform.android &&
            _webClientId.isEmpty) ||
        (defaultTargetPlatform != TargetPlatform.android && clientId.isEmpty)) {
      throw StateError(
        'Google OAuth client configuration is missing from this build.',
      );
    }
    return _initialization ??= GoogleSignIn.instance.initialize(
      clientId: clientId.isEmpty ? null : clientId,
      serverClientId: _webClientId.isEmpty ? null : _webClientId,
    );
  }

  static Future<GoogleDriveStorage> connect() async {
    if (_desktop) {
      _desktopAccount = await _desktopAuth.connect();
      return _desktopStorage(_desktopAccount!, 'root');
    }
    await _initialize();
    final account = await GoogleSignIn.instance.authenticate();
    await account.authorizationClient.authorizeScopes([_scope]);
    _account = account;
    return _storage(account, 'root');
  }

  static GoogleDriveStorage forFolder(String folderId) {
    if (_desktop) {
      final account = _desktopAccount;
      if (account == null) throw StateError('Google account is not connected.');
      return _desktopStorage(account, folderId);
    }
    final account = _account;
    if (account == null) throw StateError('Google account is not connected.');
    return _storage(account, folderId);
  }

  static GoogleDriveStorage _desktopStorage(
    DesktopGoogleAccount account,
    String folderId,
  ) => GoogleDriveStorage(
    accountId: account.id,
    folderId: folderId,
    accessToken: () => _desktopAuth.accessToken(account),
  );

  static GoogleDriveStorage _storage(
    GoogleSignInAccount account,
    String folderId,
  ) => GoogleDriveStorage(
    accountId: account.id,
    folderId: folderId,
    accessToken: () async {
      final authorization = await account.authorizationClient
          .authorizationForScopes([_scope]);
      if (authorization == null)
        throw StateError(
          'Google Drive authorization expired. Reconnect in settings.',
        );
      return authorization.accessToken;
    },
  );

  static Future<void> configure(
    GoogleDriveStorage storage,
    String folderName,
  ) async {
    final accountId = _desktop ? _desktopAccount?.id : _account?.id;
    final email = _desktop ? _desktopAccount?.email : _account?.email;
    if (accountId == null || accountId != storage.accountId)
      throw StateError('Google account is no longer connected.');
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      _configKey,
      jsonEncode({
        'accountId': accountId,
        'email': email,
        'folderId': storage.folderId,
        'folderName': folderName,
      }),
    ))
      throw StateError('Could not save Google Drive settings.');
    notebookStorageBackends.removeWhere(
      (backend) => backend is GoogleDriveStorage,
    );
    notebookStorageBackends.add(storage);
    changes.value++;
  }

  static Future<void> restore() async {
    if (!supported || current != null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw == null) return;
    if (_desktop) {
      final config = jsonDecode(raw) as Map<String, dynamic>;
      final account = await _desktopAuth.restore(config['accountId'] as String);
      if (account == null || current != null) return;
      _desktopAccount = account;
      notebookStorageBackends.add(
        _desktopStorage(account, config['folderId'] as String),
      );
      changes.value++;
      return;
    }
    await _initialize();
    final result = GoogleSignIn.instance.attemptLightweightAuthentication();
    final account = result == null ? null : await result;
    if (account == null) return;
    final config = jsonDecode(raw) as Map<String, dynamic>;
    if (config['accountId'] != account.id) return;
    if (await account.authorizationClient.authorizationForScopes([_scope]) ==
        null)
      return;
    _account = account;
    if (current != null) return;
    notebookStorageBackends.add(
      _storage(account, config['folderId'] as String),
    );
    changes.value++;
  }

  static Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (_desktop) {
      final id =
          _desktopAccount?.id ??
          (raw == null
              ? null
              : (jsonDecode(raw) as Map<String, dynamic>)['accountId']
                    as String?);
      if (id != null) await _desktopAuth.disconnect(id);
      _desktopAccount = null;
    }
    await prefs.remove(_configKey);
    if (_initialization != null) await GoogleSignIn.instance.signOut();
    _account = null;
    notebookStorageBackends.removeWhere(
      (backend) => backend is GoogleDriveStorage,
    );
    changes.value++;
  }
}
