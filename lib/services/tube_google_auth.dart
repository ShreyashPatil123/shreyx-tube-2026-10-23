import 'package:google_sign_in/google_sign_in.dart';

class TubeGoogleIdentity {
  final String id;
  final String name;
  final String avatar;
  const TubeGoogleIdentity(this.id, this.name, this.avatar);
}

abstract class TubeGoogleAuth {
  Future<void> initialize(String webClientId);
  Future<TubeGoogleIdentity?> restore();
  Future<TubeGoogleIdentity> authenticate();
  Future<String?> token({bool interactive = false, bool refresh = false});
  Future<void> disconnect();
}

/// Google's Android SDK owns account selection and consent. No passwords or
/// browser cookies are read by this app, and no client secret is embedded.
class TubeGoogleSdkAuth implements TubeGoogleAuth {
  final _google = GoogleSignIn.instance;
  GoogleSignInAccount? _account;
  Future<void>? _initializing;
  String? _clientId;
  String? _lastToken;
  static const scopes = ['https://www.googleapis.com/auth/youtube.readonly'];

  @override
  Future<void> initialize(String webClientId) {
    if (_clientId != null && _clientId != webClientId) {
      throw StateError('Restart the app after changing OAuth configuration.');
    }
    _clientId = webClientId;
    return _initializing ??= _google.initialize(serverClientId: webClientId);
  }

  TubeGoogleIdentity _identity(GoogleSignInAccount account) =>
      TubeGoogleIdentity(account.id, account.displayName ?? 'Google account',
          account.photoUrl ?? '');
  @override
  Future<TubeGoogleIdentity?> restore() async {
    _account = await _google.attemptLightweightAuthentication(
        reportAllExceptions: true);
    return _account == null ? null : _identity(_account!);
  }

  @override
  Future<TubeGoogleIdentity> authenticate() async {
    _account = await _google.authenticate(scopeHint: scopes);
    return _identity(_account!);
  }

  @override
  Future<String?> token(
      {bool interactive = false, bool refresh = false}) async {
    final account = _account;
    if (account == null) return null;
    if (refresh && _lastToken != null) {
      await account.authorizationClient
          .clearAuthorizationToken(accessToken: _lastToken!);
    }
    final authorization =
        await account.authorizationClient.authorizationForScopes(scopes) ??
            (interactive
                ? await account.authorizationClient.authorizeScopes(scopes)
                : null);
    _lastToken = authorization?.accessToken;
    return _lastToken;
  }

  @override
  Future<void> disconnect() async {
    _account = null;
    _lastToken = null;
    if (_initializing != null) await _google.disconnect();
  }
}
