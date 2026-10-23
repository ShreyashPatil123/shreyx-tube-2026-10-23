import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/tube_models.dart';

typedef TubeSubscriptionsPage = ({
  List<TubeChannelInfo> items,
  String? continuationToken
});

class TubeAccountApiException implements Exception {
  final String message;
  const TubeAccountApiException(this.message);
  @override
  String toString() => message;
}

/// OAuth tokens are sent only to the official YouTube Data API. Never use them
/// as private Innertube credentials or forward them through redirects.
class TubeYoutubeAccountClient {
  TubeYoutubeAccountClient(
      {http.Client? client,
      required this.tokenProvider,
      required this.onUnauthorized})
      : _http = client ?? http.Client();
  final http.Client _http;
  final Future<String?> Function(bool refresh) tokenProvider;
  final Future<void> Function() onUnauthorized;

  static Future<http.Response> _request(http.Client client, String path,
      Map<String, String> query, String token) async {
    final request = http.Request(
        'GET', Uri.https('www.googleapis.com', '/youtube/v3/$path', query))
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $token';
    return (() async => http.Response.fromStream(await client.send(request)))()
        .timeout(const Duration(seconds: 10));
  }

  static Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode != 200) {
      String reason = '';
      try {
        reason =
            jsonDecode(response.body)['error']['errors'][0]['reason'] as String;
      } catch (_) {/* Do not expose server response or tokens in errors. */}
      throw TubeAccountApiException(switch (reason) {
        'accessNotConfigured' ||
        'serviceDisabled' =>
          'Enable YouTube Data API v3 in the app’s Google Cloud project.',
        'quotaExceeded' ||
        'dailyLimitExceeded' =>
          'The app’s YouTube API quota has been reached. Try again later.',
        'insufficientPermissions' =>
          'YouTube read permission is required. Reconnect your Google account.',
        _ =>
          'YouTube account data could not load (HTTP ${response.statusCode}).',
      });
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<TubeChannelInfo?> fetchMyChannel(String token) async {
    final client = http.Client();
    try {
      final data = _decode(await _request(
          client, 'channels', {'part': 'snippet', 'mine': 'true'}, token));
      final items = data['items'] as List? ?? [];
      if (items.isEmpty) return null;
      final item = items.first;
      final snippet = item['snippet'] as Map<String, dynamic>;
      return TubeChannelInfo(
          id: item['id'] as String,
          title: snippet['title'] as String? ?? '',
          avatarUrl: _thumbnail(snippet),
          handle: snippet['customUrl'] as String? ?? '');
    } finally {
      client.close();
    }
  }

  static String _thumbnail(Map<String, dynamic> snippet) =>
      (snippet['thumbnails']?['high']?['url'] ??
              snippet['thumbnails']?['default']?['url'] ??
              '')
          .toString();

  Future<Map<String, dynamic>> _get(
      String path, Map<String, String> query) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await tokenProvider(attempt > 0);
      if (token == null) {
        throw const TubeAccountApiException(
            'Connect your Google account to view subscriptions.');
      }
      final response = await _request(_http, path, query, token);
      if (response.statusCode != 401) return _decode(response);
    }
    await onUnauthorized();
    throw const TubeAccountApiException(
        'Google authorization expired. Connect again or continue as Guest.');
  }

  Future<TubeSubscriptionsPage> getSubscribedChannels(
      {String? continuation}) async {
    final data = await _get('subscriptions', {
      'part': 'snippet',
      'mine': 'true',
      'maxResults': '50',
      'order': 'alphabetical',
      if (continuation != null) 'pageToken': continuation,
    });
    final seen = <String>{};
    final channels = <TubeChannelInfo>[];
    for (final item in data['items'] as List? ?? []) {
      final snippet = item['snippet'] as Map<String, dynamic>?;
      final id = snippet?['resourceId']?['channelId'] as String?;
      if (snippet == null || id == null || !seen.add(id)) continue;
      channels.add(TubeChannelInfo(
          id: id,
          title: snippet['title'] as String? ?? '',
          avatarUrl: _thumbnail(snippet)));
    }
    return (
      items: channels,
      continuationToken: data['nextPageToken'] as String?
    );
  }
}
