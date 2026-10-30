class GoogleDesktopAuth {
  Future<DesktopGoogleAccount> connect() =>
      throw UnsupportedError('Desktop sign-in unavailable');
  Future<DesktopGoogleAccount?> restore(String id) =>
      throw UnsupportedError('Desktop sign-in unavailable');
  Future<String> accessToken(DesktopGoogleAccount account) =>
      throw UnsupportedError('Desktop sign-in unavailable');
  Future<void> disconnect(String id) async {}
}

class DesktopGoogleAccount {
  DesktopGoogleAccount(this.id, this.email);
  final String id;
  final String email;
}
