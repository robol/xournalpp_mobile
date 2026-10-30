# Google Drive OAuth setup

The current Google Drive sign-in integration supports Android. It uses Google Sign-In and requests `https://www.googleapis.com/auth/drive` to browse user-selected folders and notebooks. Google classifies this as a restricted scope; production distribution may require OAuth consent-screen verification and a security assessment. While the consent screen is in testing, add the intended users as test users.

In Google Cloud, enable the Google Drive API and configure the OAuth consent screen. Create:

1. A **Web application** OAuth client. Set its public client ID as the GitHub Actions variable or secret `GOOGLE_WEB_CLIENT_ID`. The release workflow passes it as a Dart build definition. A client ID is embedded in the app and is not a secret; do not put a client secret in the app.
2. An **Android** OAuth client for package `it.robol.xournal.mobile`, registered with the SHA-1 fingerprint of each signing certificate used to run the app. Use the app-signing certificate SHA-1 from Play Console for Google Play installs, the upload/release key fingerprint for directly distributed APKs, and a separate debug fingerprint for local debug builds when different.

The Android client ID itself and the SHA-1 fingerprints do not need to be runtime variables. Google uses the package and certificate registration to identify the installed app. GitHub Actions secrets and variables are only injected into builds through the workflow; adding one does not change an already running environment or an already built APK.

For a local Android build, provide the web client ID explicitly:

```sh
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

Without the client ID, Settings reports that Google OAuth configuration is missing. iOS and macOS require their own OAuth clients and registered reversed-client-ID URL schemes; Linux and Windows need a separate supported sign-in flow. Those platforms are not enabled by this change.
