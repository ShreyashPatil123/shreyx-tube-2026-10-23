import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/tube_models.dart';
import 'tube_google_auth.dart';
import 'tube_account_probe.dart';
import 'tube_storage_service.dart';
import 'tube_youtube_account_client.dart';

abstract class TubeSessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class _SecureSessionStore implements TubeSessionStore {
  final _storage = const FlutterSecureStorage();
  static const key = 'tube_google_connection_v1';
  @override
  Future<String?> read() async {
    // Retire the previous experimental cookie login. Never reuse those cookies.
    await _storage.delete(key: 'tube_youtube_session_v1');
    if (await _storage.read(key: 'tube_cookie_login_retired') != 'true' ||
        await _storage.read(key: 'tube_account_probe_pending') == 'true') {
      try {
        await TubeSessionService.clearBrowserCookies();
        await _storage.write(key: 'tube_cookie_login_retired', value: 'true');
        await _storage.delete(key: 'tube_account_probe_pending');
      } on PlatformException {
        // An unavailable WebView provider must not block official/Guest mode.
        // Retry retirement next startup; these cookies are never used.
      }
    }
    return _storage.read(key: key);
  }

  @override
  Future<void> write(String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete() async {
    await _storage.delete(key: key);
    await _storage.delete(key: 'tube_youtube_session_v1');
  }
}

/// Opt-in, encrypted local connection. Official OAuth tokens remain in memory;
/// a separately verified YouTube website session can supply the native feed.
class TubeSessionService extends ChangeNotifier {
  static final instance = TubeSessionService.withStore(_SecureSessionStore());
  factory TubeSessionService() => instance;
  TubeSessionService.withStore(this._store,
      {TubeGoogleAuth? auth,
      String? webClientId,
      Future<TubeChannelInfo?> Function(String)? profileLoader})
      : _auth = auth ?? TubeGoogleSdkAuth(),
        _webClientId =
            webClientId ?? const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
        _profileLoader =
            profileLoader ?? TubeYoutubeAccountClient.fetchMyChannel;
  final TubeSessionStore _store;
  final TubeGoogleAuth _auth;
  final String _webClientId;
  final Future<TubeChannelInfo?> Function(String) _profileLoader;
  TubeGoogleIdentity? _identity;
  String? _token;
  Map<String, String> _privateCookies = {};
  String _privateUserAgent = '';
  String userChannelName = '';
  String userAvatarUrl = '';
  String userHandle = '';
  int _revision = 0;
  bool _initialized = false;
  Future<void>? _opening;
  Future<void>? _connecting;
  Future<void> _writes = Future.value();
  String? notice;
  int get revision => _revision;
  bool get hasPrivateConnection => _privateCookies.isNotEmpty;
  bool get isLoggedIn =>
      hasPrivateConnection || (_identity != null && _token != null);
  bool get usesPrivateFeed =>
      hasPrivateConnection && !TubeStorageService().isIncognito;
  bool get usesAccountData =>
      !hasPrivateConnection && isLoggedIn && !TubeStorageService().isIncognito;
  bool get isConfigured =>
      RegExp(r'^[a-zA-Z0-9_-]+\.apps\.googleusercontent\.com$')
          .hasMatch(_webClientId);

  late final youtube = TubeYoutubeAccountClient(
      tokenProvider: (refresh) => authorizationToken(refresh: refresh),
      onUnauthorized: () => usesAccountData
          ? clearSession(
              message:
                  'Google authorization expired. Connect again or continue as Guest.')
          : Future.value());

  static String safeAvatar(String value) {
    final uri = Uri.tryParse(value);
    return uri?.scheme == 'https' &&
            (uri!.host.endsWith('.googleusercontent.com') ||
                uri.host.endsWith('.ggpht.com'))
        ? value
        : '';
  }

  Map<String, String> getAuthHeaders() => usesAccountData && _token != null
      ? {'Authorization': 'Bearer $_token'}
      : {};

  Map<String, String> getPrivateHeaders() => usesPrivateFeed
      ? {
          ...TubeAccountProbe.headersFor(_privateCookies),
          'User-Agent': _privateUserAgent
        }
      : {};

  Future<bool> savePrivateConnection(Map<String, String> cookies,
      {required String name,
      required String userAgent,
      String avatar = '',
      String handle = '',
      bool Function()? stillActive}) async {
    final safe = TubeAccountProbe.sanitize(cookies);
    TubeAccountProbe.headersFor(safe).clear();
    if (name.trim().isEmpty ||
        userAgent.isEmpty ||
        userAgent.length > 2048 ||
        RegExp(r'[\r\n]').hasMatch(userAgent) ||
        TubeStorageService().isIncognito) {
      throw ArgumentError(
          'A verified account and browser session are required.');
    }
    final revision = ++_revision;
    var saved = false;
    bool active() =>
        revision == _revision &&
        !TubeStorageService().isIncognito &&
        (stillActive?.call() ?? true);
    await _serialize(() async {
      if (!active()) return;
      final previous = await _store.read();
      if (!active()) return;
      await _store.write(jsonEncode({
        'mode': 'youtubeSession',
        'cookies': safe,
        'userAgent': userAgent,
        'name': name.trim(),
        'avatar': safeAvatar(avatar),
        'handle': handle,
      }));
      if (!active()) {
        if (revision == _revision) {
          if (previous == null) {
            await _store.delete();
          } else {
            await _store.write(previous);
          }
        }
        return;
      }
      _identity = null;
      _token = null;
      _privateCookies = safe;
      _privateUserAgent = userAgent;
      userChannelName = name.trim();
      userAvatarUrl = safeAvatar(avatar);
      userHandle = handle;
      _initialized = true;
      notice = null;
      ++_revision;
      saved = true;
      notifyListeners();
    });
    return saved;
  }

  Future<void> init() {
    if (_initialized) return Future.value();
    return _opening ??= _load();
  }

  Future<void> _load() async {
    final revision = _revision;
    try {
      final stored = await _store.read();
      if (stored != null && revision == _revision) {
        try {
          final data = jsonDecode(stored) as Map<String, dynamic>;
          if (data['mode'] == 'youtubeSession') {
            final safe = TubeAccountProbe.sanitize(
                Map<String, String>.from(data['cookies']));
            final name = data['name'] as String;
            final agent = data['userAgent'] as String;
            try {
              TubeAccountProbe.headersFor(safe).clear();
            } on TubeAccountProbeException {
              throw const FormatException();
            }
            if (name.trim().isEmpty ||
                agent.isEmpty ||
                agent.length > 2048 ||
                RegExp(r'[\r\n]').hasMatch(agent)) {
              throw const FormatException();
            }
            _privateCookies = safe;
            _privateUserAgent = agent;
            userChannelName = name;
            userAvatarUrl = safeAvatar(data['avatar'] as String? ?? '');
            userHandle = data['handle'] as String? ?? '';
            ++_revision;
            return;
          }
          if (!isConfigured) return;
          await _auth
              .initialize(_webClientId)
              .timeout(const Duration(seconds: 8));
          final identity =
              await _auth.restore().timeout(const Duration(seconds: 8));
          final token = identity == null
              ? null
              : await _auth.token().timeout(const Duration(seconds: 8));
          if (revision != _revision) return;
          if (identity == null ||
              identity.id != data['accountId'] ||
              token == null) {
            await _store.delete();
            notice = 'Connect again to restore your Google account.';
          } else {
            _identity = identity;
            _token = token;
            userChannelName = data['name'] as String? ?? identity.name;
            userAvatarUrl =
                safeAvatar(data['avatar'] as String? ?? identity.avatar);
            userHandle = data['handle'] as String? ?? '';
            ++_revision;
          }
        } on FormatException {
          await _store.delete();
        } on TypeError {
          await _store.delete();
        } catch (_) {
          notice =
              'Your account connection could not be restored. Continue as Guest or reconnect.';
        }
      }
    } catch (_) {
      notice = 'Account storage is unavailable. Guest Mode is still available.';
    } finally {
      _initialized = true;
      _opening = null;
      notifyListeners();
    }
  }

  Future<void> _serialize(Future<void> Function() action) {
    final task = _writes.then((_) => action());
    _writes = task.catchError((Object _) {});
    return task;
  }

  Future<void> connect() {
    if (!isConfigured) {
      throw StateError(
          'Google app registration is required for this build. See GOOGLE_ACCOUNT_SETUP.md.');
    }
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    final revision = ++_revision;
    await _auth.initialize(_webClientId);
    final identity = await _auth.authenticate();
    final token = await _auth.token(interactive: true);
    if (token == null) {
      throw StateError('YouTube read permission was not granted.');
    }
    final channel = await _profileLoader(token);
    if (revision != _revision) return;
    final name =
        channel?.title.isNotEmpty == true ? channel!.title : identity.name;
    final avatar = safeAvatar(channel?.avatarUrl ?? identity.avatar);
    await _serialize(() async {
      if (revision != _revision) return;
      await _store.write(jsonEncode({
        'accountId': identity.id,
        'name': name,
        'avatar': avatar,
        'handle': channel?.handle ?? ''
      }));
      if (revision != _revision) return;
      _identity = identity;
      _token = token;
      _privateCookies = {};
      _privateUserAgent = '';
      userChannelName = name;
      userAvatarUrl = avatar;
      userHandle = channel?.handle ?? '';
      _initialized = true;
      notice = null;
      ++_revision;
      notifyListeners();
    });
  }

  Future<String?> authorizationToken({bool refresh = false}) async {
    if (!usesAccountData) return null;
    final revision = _revision;
    final token = await _auth.token(refresh: refresh);
    if (revision != _revision || !usesAccountData) return null;
    if (token == null) {
      await clearSession(
          message: 'Google consent is required again. Reconnect your account.');
      return null;
    }
    _token = token;
    return token;
  }

  Future<void> clearSession({String? message}) {
    ++_revision;
    _identity = null;
    _token = null;
    _privateCookies = {};
    _privateUserAgent = '';
    userChannelName = userAvatarUrl = userHandle = '';
    notice = message;
    notifyListeners();
    return _serialize(() async {
      await _store.delete();
      try {
        await _auth.disconnect();
      } catch (_) {
        notice =
            'Local session removed. Google access could not be revoked; manage it in your Google account permissions.';
      }
      await clearBrowserCookies();
    });
  }

  static Future<void> clearBrowserCookies() async {
    if (Platform.isAndroid) {
      await const MethodChannel('com.shreyx.tube/session_browser')
          .invokeMethod<void>('clear');
    }
  }
}
