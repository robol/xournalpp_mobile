# Google Drive OAuth setup

The Google Drive sign-in integration supports Android, Windows, and Linux. It uses Google Sign-In and requests `https://www.googleapis.com/auth/drive` to browse user-selected folders and notebooks. Google classifies this as a restricted scope; production distribution may require OAuth consent-screen verification and a security assessment. While the consent screen is in testing, add the intended users as test users.

In Google Cloud, enable the Google Drive API and configure the OAuth consent screen. Create:

1. A **Web application** OAuth client. Set its public client ID as the GitHub Actions variable or secret `GOOGLE_WEB_CLIENT_ID`. The release workflow passes it as a Dart build definition. A client ID is embedded in the app and is not a secret; do not put a client secret in the app.
2. An **Android** OAuth client for package `it.robol.xournal.mobile`, registered with the SHA-1 fingerprint of each signing certificate used to run the app. Use the app-signing certificate SHA-1 from Play Console for Google Play installs, the upload/release key fingerprint for directly distributed APKs, and a separate debug fingerprint for local debug builds when different.

The Android client ID itself and the SHA-1 fingerprints do not need to be runtime variables. Google uses the package and certificate registration to identify the installed app. GitHub Actions secrets and variables are only injected into builds through the workflow; adding one does not change an already running environment or an already built APK.

For a local Android build, provide the web client ID explicitly:

```sh
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

Without the client ID, Settings reports that Google OAuth configuration is missing. Windows and Linux use a **Desktop app** OAuth client and the system browser with a temporary loopback callback and PKCE. Add `GOOGLE_DESKTOP_CLIENT_ID` as a GitHub Actions variable or secret and `GOOGLE_DESKTOP_CLIENT_SECRET` as a GitHub Actions secret. The release workflow embeds both in desktop builds. The desktop client secret is recoverable from distributed binaries and is not a confidential credential. Do not reuse a server-side secret. Refresh tokens are stored in the operating system credential store; Linux requires an available Secret Service keyring.

For a local desktop build, pass `--dart-define=GOOGLE_DESKTOP_CLIENT_ID=...` and `--dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=...`. The Drive API and OAuth consent screen must be configured, and users must be added as test users while the consent screen is in testing.

iOS and macOS are not enabled and require additional sign-in configuration.
