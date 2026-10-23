import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/tube_models.dart';
import 'tube_innertube_client.dart';
import 'tube_storage_service.dart';

enum TubeProbeNavigation { allow, unsupported, rejected }

/// Deliberately omit path, query, fragment and user-info: sign-in redirects can
/// carry bearer credentials. Only this destination label may reach the UI.
String tubeProbeDestinationLabel(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return 'unknown destination';
  if (url == 'about:blank') return 'about:blank';
  if (uri.host.isEmpty || uri.host.length > 255) {
    return 'unsupported destination type';
  }
  return uri.host;
}

TubeProbeNavigation tubeProbeNavigation(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      !{
        'accounts.google.com',
        'myaccount.google.com',
        'accounts.youtube.com',
        'www.youtube.com',
        'm.youtube.com',
        'youtube.com',
        'consent.youtube.com',
        'consent.google.com',
      }.contains(uri.host)) {
    return TubeProbeNavigation.unsupported;
  }
  final lower = url.toLowerCase();
  // Never attempt embedded OAuth, disguise the browser or bypass rejection.
  if (({'accounts.google.com', 'myaccount.google.com'}.contains(uri.host) &&
          (uri.path.startsWith('/o/oauth2') ||
              uri.path.contains('/signin/oauth'))) ||
      lower.contains('disallowed_useragent') ||
      lower.contains('deniedsigninrejected')) {
    return TubeProbeNavigation.rejected;
  }
  return TubeProbeNavigation.allow;
}

enum TubeAccountProbeFailure {
  signInRequired,
  rejected,
  unavailable,
  privacyChanged,
}

enum TubeAccountProbeDetail {
  missingSessionCookies,
  accountLoggedOut,
  accountMarkerAbsent,
  accountProfileAbsent,
  homeLoggedOut,
  homeMarkerAbsent,
}

class TubeAccountProbeException implements Exception {
  const TubeAccountProbeException(this.reason, {this.detail});
  final TubeAccountProbeFailure reason;
  final TubeAccountProbeDetail? detail;
  String get message =>
      '$_explanation${detail == null ? '' : ' [${detail!.name}]'}';
  String get _explanation => switch (reason) {
        TubeAccountProbeFailure.signInRequired =>
          'YouTube has not confirmed a signed-in session. Finish signing in on the YouTube page and try again.',
        TubeAccountProbeFailure.rejected =>
          'YouTube rejected this session. No account connection was saved.',
        TubeAccountProbeFailure.unavailable =>
          'The account or recommendation check could not complete. Check your connection and try again. No connection was saved.',
        TubeAccountProbeFailure.privacyChanged =>
          'The test was cancelled or Incognito was enabled. No account connection was saved.',
      };
  @override
  String toString() => message;
}

class TubeAccountProbeResult {
  const TubeAccountProbeResult(
      {required this.name,
      required this.videos,
      this.avatar = '',
      this.handle = ''});
  final String name;
  final String avatar;
  final String handle;
  final List<TubeVideoItem> videos;
}

/// One-shot authentication feasibility check, isolated from every live feed.
/// No credentials are persisted, logged or passed to the official OAuth client.
class TubeAccountProbe {
  TubeAccountProbe({http.Client? client, bool Function()? allowed})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _allowed = allowed ?? (() => !TubeStorageService().isIncognito);
  final http.Client _client;
  final bool _ownsClient;
  final bool Function() _allowed;
  static const origin = 'https://www.youtube.com';
  static const cookieNames = {
    'SAPISID',
    'SID',
    'HSID',
    'SSID',
    'LOGIN_INFO',
    'SIDCC',
    '__Secure-1PAPISID',
    '__Secure-3PAPISID',
    '__Secure-1PSID',
    '__Secure-3PSID',
    '__Secure-1PSIDTS',
    '__Secure-3PSIDTS',
  };

  static Map<String, String> sanitize(Map<String, String> cookies) => {
        for (final entry in cookies.entries)
          if (cookieNames.contains(entry.key) &&
              entry.value.isNotEmpty &&
              entry.value.length <= 16384 &&
              !RegExp(r'[\x00-\x20\x7f;]').hasMatch(entry.value))
            entry.key: entry.value,
      };

  static Map<String, String> headersFor(Map<String, String> cookies,
      {int? timestamp}) {
    final safe = sanitize(cookies);
    final sapisid = safe['SAPISID'] ?? safe['__Secure-3PAPISID'];
    if (sapisid == null ||
        !['SID', 'LOGIN_INFO', '__Secure-1PSID', '__Secure-3PSID']
            .any(safe.containsKey)) {
      throw const TubeAccountProbeException(
          TubeAccountProbeFailure.signInRequired,
          detail: TubeAccountProbeDetail.missingSessionCookies);
    }
    final seconds = timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final digest = sha1.convert(utf8.encode('$seconds $sapisid $origin'));
    return {
      'Authorization': 'SAPISIDHASH ${seconds}_$digest',
      'Cookie': safe.entries.map((e) => '${e.key}=${e.value}').join('; '),
      'Origin': origin,
      'X-Origin': origin,
      'Content-Type': 'application/json',
    };
  }

  Future<TubeAccountProbeResult> check(Map<String, String> cookies,
      {required String userAgent, bool Function()? stillActive}) async {
    void guard() {
      if (!_allowed() || !(stillActive?.call() ?? true)) {
        throw const TubeAccountProbeException(
            TubeAccountProbeFailure.privacyChanged);
      }
    }

    guard();
    final headers = headersFor(cookies);
    if (userAgent.isEmpty ||
        userAgent.length > 2048 ||
        RegExp(r'[\r\n]').hasMatch(userAgent)) {
      throw const TubeAccountProbeException(
          TubeAccountProbeFailure.unavailable);
    }
    headers['User-Agent'] = userAgent;
    // Fixed first-party destinations; redirects never forward session headers.
    Future<Map<String, dynamic>> post(String endpoint,
        {String? browseId}) async {
      guard();
      final request = http.Request(
          'POST', Uri.parse('$origin/youtubei/v1/$endpoint?prettyPrint=false'))
        ..followRedirects = false
        ..headers.addAll(headers)
        ..body = jsonEncode({
          'context': TubeInnertubeClient.clientContext,
          if (browseId != null) 'browseId': browseId,
        });
      final response = await (() async =>
              http.Response.fromStream(await _client.send(request)))()
          .timeout(const Duration(seconds: 10));
      guard();
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const TubeAccountProbeException(TubeAccountProbeFailure.rejected);
      }
      if (response.statusCode != 200) {
        throw const TubeAccountProbeException(
            TubeAccountProbeFailure.unavailable);
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      // Be conservative: an absent marker cannot prove authenticated Home.
      final loggedOut =
          data['responseContext']?['mainAppWebResponseContext']?['loggedOut'];
      if (loggedOut != false) {
        throw TubeAccountProbeException(TubeAccountProbeFailure.signInRequired,
            detail: endpoint == 'browse'
                ? loggedOut == true
                    ? TubeAccountProbeDetail.homeLoggedOut
                    : TubeAccountProbeDetail.homeMarkerAbsent
                : loggedOut == true
                    ? TubeAccountProbeDetail.accountLoggedOut
                    : TubeAccountProbeDetail.accountMarkerAbsent);
      }
      return data;
    }

    try {
      final account = await post('account/account_menu');
      final profiles = [
        ...TubeInnertubeClient.findNodes(
            account, 'activeAccountHeaderRenderer'),
        ...TubeInnertubeClient.findNodes(
            account, 'simpleAccountHeaderRenderer'),
      ];
      final name = profiles.isEmpty
          ? ''
          : TubeInnertubeClient.text(profiles.first['accountName']).trim();
      if (name.isEmpty) {
        throw const TubeAccountProbeException(
            TubeAccountProbeFailure.signInRequired,
            detail: TubeAccountProbeDetail.accountProfileAbsent);
      }
      final home = await post('browse', browseId: 'FEwhat_to_watch');
      final page = TubeInnertubeClient().parseFeedPage(home);
      guard();
      return TubeAccountProbeResult(
          name: name,
          avatar: (profiles.first['accountPhoto']?['thumbnails'] as List? ?? [])
                  .isEmpty
              ? ''
              : profiles.first['accountPhoto']['thumbnails'].last['url']
                      as String? ??
                  '',
          handle: TubeInnertubeClient.text(profiles.first['channelHandle']),
          videos: List.unmodifiable(page.items.take(20)));
    } on TubeAccountProbeException {
      rethrow;
    } catch (_) {
      // Never surface response bodies, cookies or underlying HTTP exceptions.
      throw const TubeAccountProbeException(
          TubeAccountProbeFailure.unavailable);
    } finally {
      headers.clear();
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
