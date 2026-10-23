import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/tube_models.dart';
import 'tube_session_service.dart';
import 'tube_storage_service.dart';

typedef TubeFeedPageData = ({
  List<TubeVideoItem> items,
  String? continuationToken
});

class TubeInnertubeClient {
  static final TubeInnertubeClient instance = TubeInnertubeClient._internal();
  factory TubeInnertubeClient() => instance;
  TubeInnertubeClient._internal()
      : _httpClient = http.Client(),
        session = TubeSessionService();
  TubeInnertubeClient.withClient(http.Client client,
      {TubeSessionService? session})
      : _httpClient = client,
        session = session ?? TubeSessionService();

  final http.Client _httpClient;
  final TubeSessionService session;
  static String _absoluteImageUrl(String value) =>
      value.startsWith('//') ? 'https:$value' : value;
  bool get isConnected => session.usesPrivateFeed;
  String get requestIdentity =>
      '${session.revision}/${TubeStorageService().isIncognito}/$isConnected';

  void _requireAccountFeed(Map<String, dynamic> data) {
    if (isConnected &&
        data['responseContext']?['mainAppWebResponseContext']?['loggedOut'] !=
            false) {
      throw StateError(
          'YouTube could not confirm the account feed. Retry or reconnect.');
    }
  }

  Future<http.Response> _post(
      String endpoint, Map<String, dynamic> body) async {
    final identity = requestIdentity;
    final connected = isConnected;
    final request = http.Request(
        'POST', Uri.parse('$baseUrl/$endpoint?prettyPrint=false'))
      ..followRedirects = !connected
      ..headers
          .addAll({...headers, if (connected) ...session.getPrivateHeaders()})
      ..body = jsonEncode(body);
    final response = await (() async =>
            http.Response.fromStream(await _httpClient.send(request)))()
        .timeout(const Duration(seconds: 10));
    if (identity != requestIdentity) {
      throw StateError('Account changed during request');
    }
    if (connected) {
      var expired = response.statusCode == 401;
      if (response.statusCode == 200) {
        try {
          expired = jsonDecode(response.body)['responseContext']
                  ?['mainAppWebResponseContext']?['loggedOut'] ==
              true;
        } on FormatException {
          /* The calling parser handles malformed responses. */
        }
      }
      if (expired) {
        await session.clearSession(
            message:
                'Your YouTube connection expired. Reconnect or continue as Guest.');
        throw StateError('YouTube connection expired');
      }
    }
    return response;
  }

  static const String baseUrl = 'https://www.youtube.com/youtubei/v1';
  static const Map<String, String> headers = {
    'Content-Type': 'application/json',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  };

  static const Map<String, dynamic> clientContext = {
    'client': {
      'clientName': 'WEB',
      'clientVersion': '2.20261009.01.00',
      'hl': 'en',
      'gl': 'IN',
    }
  };

  Future<({List<TubeVideoItem> items, String? continuationToken})> searchVideos(
    String query, {
    String? continuation,
  }) async {
    try {
      final response = await search(query, continuation: continuation);
      if (response.statusCode != 200) {
        return (items: <TubeVideoItem>[], continuationToken: null);
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return parseFeedPage(data, includeShorts: true);
    } catch (_) {
      return (items: <TubeVideoItem>[], continuationToken: null);
    }
  }

  Future<http.Response> search(String query, {String? continuation}) async {
    final body = {
      'context': clientContext,
      if (continuation == null)
        'query': query
      else
        'continuation': continuation,
    };
    return _post('search', body);
  }

  Future<http.Response> next(String videoId, {String? continuation}) async {
    final body = {
      'context': clientContext,
      if (continuation == null)
        'videoId': videoId
      else
        'continuation': continuation,
    };
    return _post('next', body);
  }

  Future<Map<String, dynamic>> authenticatedPlayer(String videoId) async {
    if (!isConnected) throw StateError('Connect an eligible YouTube account.');
    final response = await _post('player', {
      'context': clientContext,
      'videoId': videoId,
    });
    if (response.statusCode != 200) {
      throw StateError('YouTube account playback could not load. Retry.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<({List<TubeVideoItem> items, String? continuationToken})> homeFeed(
      {String? continuation}) async {
    final response = await browse('FEwhat_to_watch',
        params: continuation == null ? null : {'continuation': continuation});
    if (response.statusCode != 200) {
      throw StateError('YouTube home is unavailable');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _requireAccountFeed(data);
    return parseFeedPage(data);
  }

  Future<TubeFeedPageData> shortsFeed({String? continuation}) async {
    final response = await browse('FEshorts',
        params: continuation == null ? null : {'continuation': continuation});
    if (response.statusCode != 200) {
      throw StateError('YouTube Shorts are unavailable');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _requireAccountFeed(data);
    final page = parseFeedPage(data, includeShorts: true);
    return (
      items: page.items.where((v) => v.isShort).toList(),
      continuationToken: page.continuationToken
    );
  }

  Future<TubeFeedPageData> subscriptionsFeed({String? continuation}) async {
    final response = await browse('FEsubscriptions',
        params: continuation == null ? null : {'continuation': continuation});
    if (response.statusCode != 200) {
      throw StateError('YouTube subscriptions are unavailable');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _requireAccountFeed(data);
    return parseFeedPage(data);
  }

  Future<List<TubeChannelInfo>> subscribedChannels() async {
    final response = await browse('FEchannels');
    if (response.statusCode != 200) {
      throw StateError('Subscribed channels are unavailable');
    }
    final seen = <String>{};
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _requireAccountFeed(data);
    return findNodes(data, 'channelRenderer')
        .map(parseChannelRenderer)
        .whereType<TubeChannelInfo>()
        .where((c) => seen.add(c.id))
        .toList();
  }

  Future<({List<TubeVideoItem> items, String? continuationToken})> relatedFeed(
      String videoId,
      {String? continuation}) async {
    final response = await next(videoId, continuation: continuation);
    if (response.statusCode != 200) {
      throw StateError('YouTube recommendations are unavailable');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final secondary =
        data['contents']?['twoColumnWatchNextResults']?['secondaryResults'];
    _requireAccountFeed(data);
    return parseFeedPage(
        continuation == null && secondary is Map<String, dynamic>
            ? {'contents': secondary}
            : data);
  }

  /// Retains YouTube's ordering and ignores advertising and Shorts shelves.
  ({List<TubeVideoItem> items, String? continuationToken}) parseFeedPage(
      Map<String, dynamic> data,
      {bool includeShorts = false}) {
    final items = <TubeVideoItem>[];
    final seen = <String>{};
    String? token;
    void read(dynamic node) {
      if (node is List) {
        for (final value in node) {
          read(value);
        }
      } else if (node is Map<String, dynamic>) {
        if (node.keys.any((key) =>
            key == 'adSlotRenderer' ||
            key == 'promotedSparklesWebRenderer' ||
            key == 'statementBannerRenderer' ||
            key.toLowerCase().contains('promoted') ||
            key == 'displayAdRenderer' ||
            key == 'inFeedAdLayoutRenderer' ||
            (!includeShorts &&
                (key == 'reelShelfRenderer' ||
                    key == 'shortsLockupViewModel')))) {
          return;
        }
        if (includeShorts &&
            (node['shortsLockupViewModel'] != null ||
                node['reelItemRenderer'] != null)) {
          final short = node['shortsLockupViewModel'] is Map<String, dynamic>
              ? parseShortsLockupViewModel(node['shortsLockupViewModel'])
              : parseReelItemRenderer(node['reelItemRenderer']);
          if (short != null && seen.add(short.id)) items.add(short);
          return;
        }
        final renderer = node['videoRenderer'] ??
            node['compactVideoRenderer'] ??
            node['gridVideoRenderer'];
        final lockup = node['lockupViewModel'];
        if (renderer is Map<String, dynamic> ||
            lockup is Map<String, dynamic>) {
          final item = lockup is Map<String, dynamic>
              ? parseVideoLockup(lockup)
              : parseVideoRenderer(renderer as Map<String, dynamic>);
          if (item != null &&
              (includeShorts || !item.isShort) &&
              seen.add(item.id)) {
            items.add(item);
          }
          return;
        }
        final cursor = node['continuationItemRenderer']?['continuationEndpoint']
            ?['continuationCommand']?['token'];
        if (cursor is String && cursor.isNotEmpty) token = cursor;
        for (final entry in node.entries) {
          if (entry.key == 'contents' ||
              entry.key == 'content' ||
              entry.key == 'continuationContents' ||
              entry.key == 'entries' ||
              entry.key == 'items' ||
              entry.key == 'tabs' ||
              entry.key == 'primaryContents' ||
              entry.key == 'gridShelfViewModel' ||
              entry.key == 'results' ||
              entry.key.endsWith('Renderer') ||
              entry.key.endsWith('Results') ||
              entry.key.endsWith('Action') ||
              entry.key.startsWith('onResponseReceived') ||
              entry.key == 'continuationItems' ||
              entry.key == 'secondaryResults') {
            read(entry.value);
          }
        }
      }
    }

    read(data);
    return (items: items, continuationToken: token);
  }

  static bool isShortRenderer(Map<String, dynamic> renderer) {
    final endpoint = renderer['navigationEndpoint'] ??
        renderer['rendererContext']?['commandContext']?['onTap']
            ?['innertubeCommand'];
    final url = endpoint?['commandMetadata']?['webCommandMetadata']?['url']
            ?.toString() ??
        '';
    if (url.contains('/shorts/') || endpoint?['reelWatchEndpoint'] != null) {
      return true;
    }
    return (renderer['thumbnailOverlays'] as List? ?? []).any((overlay) =>
        overlay['thumbnailOverlayTimeStatusRenderer']?['style'] == 'SHORTS');
  }

  Future<http.Response> browse(String browseId,
      {Map<String, dynamic>? params}) async {
    final body = {
      'context': clientContext,
      'browseId': browseId,
      if (params != null) ...params,
    };
    return _post('browse', body);
  }

  Future<Map<String, dynamic>> channelOverview(String channelId) async {
    final response = await browse(channelId);
    if (response.statusCode != 200) throw StateError('Channel unavailable');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static List<Map<String, dynamic>> findNodes(dynamic data, String key) {
    final found = <Map<String, dynamic>>[];
    void visit(dynamic node) {
      if (node is List) {
        for (final child in node) {
          visit(child);
        }
      }
      if (node is Map<String, dynamic>) {
        final value = node[key];
        if (value is Map<String, dynamic>) found.add(value);
        for (final child in node.values) {
          visit(child);
        }
      }
    }

    visit(data);
    return found;
  }

  static String text(dynamic node) {
    if (node is String) return node;
    if (node is! Map) return '';
    if (node['content'] is String) return node['content'];
    if (node['simpleText'] is String) return node['simpleText'];
    return (node['runs'] as List? ?? []).map((r) => r['text'] ?? '').join();
  }

  Future<({TubeFeedPageData page, List<TubeChannelPlaylist> playlists})>
      channelSection(String channelId, String params,
          {String? continuation,
          String channelTitle = '',
          bool shorts = false}) async {
    final response = await browse(channelId,
        params: continuation == null
            ? {'params': params}
            : {'continuation': continuation});
    if (response.statusCode != 200) {
      throw StateError('Channel content unavailable');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final parsed = parseFeedPage(data, includeShorts: shorts);
    final items = parsed.items
        .map((v) => v.copyWith(
            channelId: v.channelId.isEmpty ? channelId : v.channelId,
            channelTitle:
                v.channelTitle.isEmpty ? channelTitle : v.channelTitle))
        .toList();
    final playlists = <TubeChannelPlaylist>[];
    final seen = <String>{};
    for (final renderer in [
      ...findNodes(data, 'playlistRenderer'),
      ...findNodes(data, 'gridPlaylistRenderer'),
      ...findNodes(data, 'lockupViewModel')
          .where((n) => n['contentType'] == 'LOCKUP_CONTENT_TYPE_PLAYLIST')
    ]) {
      final id =
          (renderer['playlistId'] ?? renderer['contentId']) as String? ?? '';
      if (id.isEmpty || !seen.add(id)) continue;
      final metadata = renderer['metadata']?['lockupMetadataViewModel'];
      final title = text(renderer['title']).isNotEmpty
          ? text(renderer['title'])
          : text(metadata?['title']);
      final thumbs = renderer['thumbnail']?['thumbnails'] ??
          renderer['thumbnails']?.firstOrNull?['thumbnails'] ??
          renderer['contentImage']?['collectionThumbnailViewModel']
                  ?['primaryThumbnail']?['thumbnailViewModel']?['image']
              ?['sources'];
      playlists.add(TubeChannelPlaylist(
          id: id,
          title: title,
          channelTitle: channelTitle,
          thumbnailUrl: thumbs is List && thumbs.isNotEmpty
              ? thumbs.last['url'] as String? ?? ''
              : '',
          videoCount: int.tryParse(text(renderer['videoCountText'])
                  .replaceAll(RegExp(r'[^0-9]'), '')) ??
              0));
    }
    return (
      page: (items: items, continuationToken: parsed.continuationToken),
      playlists: playlists
    );
  }

  TubeVideoItem? parseVideoRenderer(Map<String, dynamic> vr) {
    final videoId = vr['videoId'] as String?;
    if (videoId == null || videoId.isEmpty) return null;

    // Fix title truncation bug by joining all runs
    String title = '';
    final titleRuns = vr['title']?['runs'] as List?;
    if (titleRuns != null && titleRuns.isNotEmpty) {
      title = titleRuns.map((r) => r['text'] ?? '').join();
    } else {
      title = vr['title']?['simpleText']?.toString() ?? 'Video';
    }

    String channelTitle = '';
    String channelId = '';
    final ownerRuns = [
      vr['ownerText']?['runs'],
      vr['shortBylineText']?['runs'],
      vr['longBylineText']?['runs']
    ].whereType<List>().where((runs) => runs.isNotEmpty).firstOrNull;
    if (ownerRuns != null && ownerRuns.isNotEmpty) {
      channelTitle = ownerRuns.map((r) => r['text'] ?? '').join();
      final endpoint = ownerRuns[0]?['navigationEndpoint']?['browseEndpoint'];
      channelId = endpoint?['browseId']?.toString() ?? '';
    }

    String thumbnailUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    final thumbList = vr['thumbnail']?['thumbnails'] as List?;
    if (thumbList != null && thumbList.isNotEmpty) {
      thumbnailUrl = thumbList.last?['url']?.toString() ?? thumbnailUrl;
    }

    String channelAvatarUrl = '';
    final avatarThumbs = vr['channelThumbnailSupportedRenderers']
            ?['channelThumbnailWithLinkRenderer']?['thumbnail']?['thumbnails']
        as List?;
    if (avatarThumbs != null && avatarThumbs.isNotEmpty) {
      channelAvatarUrl = avatarThumbs.last?['url']?.toString() ?? '';
    }

    int durationSeconds = 0;
    final lengthText = vr['lengthText']?['simpleText'] as String?;
    if (lengthText != null) {
      final parts =
          lengthText.split(':').map((p) => int.tryParse(p) ?? 0).toList();
      if (parts.length == 2) {
        durationSeconds = parts[0] * 60 + parts[1];
      } else if (parts.length == 3) {
        durationSeconds = parts[0] * 3600 + parts[1] * 60 + parts[2];
      }
    }

    String? viewCountText;
    final vText = (vr['shortViewCountText']?['simpleText'] ??
        vr['viewCountText']?['simpleText']) as String?;
    if (vText != null && vText.isNotEmpty) {
      viewCountText = vText;
    } else {
      final vRuns = (vr['shortViewCountText']?['runs'] ??
          vr['viewCountText']?['runs']) as List?;
      if (vRuns != null && vRuns.isNotEmpty) {
        viewCountText = vRuns.map((r) => r['text'] ?? '').join();
      }
    }
    final viewCount = TubeVideoItem.parseViewCount(viewCountText);

    String? publishedTimeText;
    final pText = vr['publishedTimeText']?['simpleText'] as String?;
    if (pText != null && pText.isNotEmpty) {
      publishedTimeText = pText;
    } else {
      final pRuns = vr['publishedTimeText']?['runs'] as List?;
      if (pRuns != null && pRuns.isNotEmpty) {
        publishedTimeText = pRuns.map((r) => r['text'] ?? '').join();
      }
    }
    final uploadDate = TubeVideoItem.parseRelativeTime(publishedTimeText);

    String? description;
    final snippets = vr['detailedMetadataSnippets'] as List?;
    final Map<String, dynamic>? snippet =
        snippets != null && snippets.isNotEmpty
            ? snippets.first as Map<String, dynamic>
            : null;
    final descRuns = (snippet?['snippetText']?['runs'] ??
        vr['descriptionSnippet']?['runs']) as List?;
    if (descRuns != null) {
      description = descRuns.map((r) => r['text'] ?? '').join();
    }

    final isShort = isShortRenderer(vr);
    final isLive = (vr['badges'] as List? ?? []).any((b) =>
        b['metadataBadgeRenderer']?['style'] == 'BADGE_STYLE_TYPE_LIVE_NOW');

    return TubeVideoItem(
      id: videoId,
      title: title,
      channelTitle: channelTitle,
      channelId: channelId,
      channelAvatarUrl: _absoluteImageUrl(channelAvatarUrl),
      thumbnailUrl: thumbnailUrl,
      durationSeconds: durationSeconds,
      viewCount: viewCount,
      viewCountText: viewCountText,
      uploadDate: uploadDate,
      publishedTimeText: publishedTimeText,
      isLive: isLive,
      isShort: isShort,
      isMembersOnly: hasMembersOnlyBadge(vr),
      description: description ?? '',
    );
  }

  static bool hasMembersOnlyBadge(Map<String, dynamic> renderer) {
    bool scan(dynamic node, {bool inBadge = false}) {
      if (node is List) {
        return node.any((value) => scan(value, inBadge: inBadge));
      }
      if (node is Map) {
        return node.entries.any((entry) {
          final key = entry.key.toString().toLowerCase();
          if (key == 'title') return false;
          return scan(entry.value, inBadge: inBadge || key.contains('badge'));
        });
      }
      if (node is String) {
        final value = node.toLowerCase();
        return value == 'badge_style_type_members_only' ||
            (inBadge &&
                (value.contains('members only') ||
                    value.contains('members-only')));
      }
      return false;
    }

    return scan(renderer['badges'], inBadge: true) ||
        scan(renderer['thumbnailOverlays']) ||
        scan(renderer['metadata']) ||
        scan(renderer['contentImage']);
  }

  TubeVideoItem? parseVideoLockup(Map<String, dynamic> lockup) {
    final id = lockup['contentId'] as String?;
    if (id == null || lockup['contentType'] != 'LOCKUP_CONTENT_TYPE_VIDEO') {
      return null;
    }
    final metadata =
        lockup['metadata']?['lockupMetadataViewModel'] as Map<String, dynamic>?;
    final title = metadata?['title']?['content'] as String? ?? '';
    final rows = metadata?['metadata']?['contentMetadataViewModel']
            ?['metadataRows'] as List? ??
        [];
    final texts = <String>[];
    String channelId = '';
    void read(dynamic node) {
      if (node is List) {
        for (final value in node) {
          read(value);
        }
      }
      if (node is Map) {
        final browseId = node['browseEndpoint']?['browseId'];
        if (browseId is String && browseId.startsWith('UC')) {
          channelId = browseId;
        }
        for (final value in node.values) {
          read(value);
        }
      }
    }

    read(metadata);
    for (final row in rows) {
      for (final part in row['metadataParts'] as List? ?? []) {
        final text = part['text']?['content'];
        if (text is String) texts.add(text);
      }
    }
    final thumbnail =
        lockup['contentImage']?['thumbnailViewModel'] as Map<String, dynamic>?;
    final sources = thumbnail?['image']?['sources'] as List? ?? [];
    final overlay = jsonEncode(thumbnail?['overlays'] ?? []);
    final durationMatch =
        RegExp(r'"text"\s*:\s*"((?:\d+:)?\d+:\d+)"').firstMatch(overlay);
    var seconds = 0;
    for (final part in (durationMatch?.group(1) ?? '').split(':')) {
      seconds = seconds * 60 + (int.tryParse(part) ?? 0);
    }
    final date = texts
        .where((text) => TubeVideoItem.parseRelativeTime(text) != null)
        .firstOrNull;
    final views =
        texts.where((text) => text.toLowerCase().contains('views')).firstOrNull;
    return TubeVideoItem(
      id: id,
      title: title,
      channelId: channelId,
      channelTitle: texts
              .where((text) =>
                  TubeVideoItem.parseRelativeTime(text) == null &&
                  !text.toLowerCase().contains('views'))
              .firstOrNull ??
          '',
      channelAvatarUrl: _absoluteImageUrl((metadata?['image']
                      ?['decoratedAvatarViewModel']?['avatar']
                  ?['avatarViewModel']?['image']?['sources'] as List?)
              ?.lastOrNull?['url']
              ?.toString() ??
          ''),
      thumbnailUrl: sources.isEmpty
          ? 'https://i.ytimg.com/vi/$id/hqdefault.jpg'
          : sources.last['url'] as String,
      durationSeconds: seconds,
      publishedTimeText: date,
      viewCountText: views,
      viewCount: TubeVideoItem.parseViewCount(views),
      isMembersOnly: hasMembersOnlyBadge(lockup),
      isLive: overlay.contains('LIVE'),
      isShort: isShortRenderer(lockup),
    );
  }

  /// Reads only the uploads tab (never unrelated shelves or recommendations).
  Future<({List<TubeVideoItem> items, String? continuationToken})>
      channelVideos(String channelId,
          {String? continuation, String channelTitle = ''}) async {
    final body = <String, dynamic>{
      'context': clientContext,
      if (continuation == null) ...{
        'browseId': channelId,
        'params': 'EgZ2aWRlb3PyBgQKAjoA',
      } else
        'continuation': continuation,
    };
    final response = await _post('browse', body);
    if (response.statusCode != 200) {
      throw StateError('Channel browse returned HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    dynamic content;
    if (continuation == null) {
      final tabs = (data['contents']?['twoColumnBrowseResultsRenderer']
                  ?['tabs'] ??
              data['contents']?['singleColumnBrowseResultsRenderer']?['tabs'])
          as List?;
      if (tabs == null) throw StateError('Missing channel uploads tab');
      for (final tab in tabs) {
        final renderer = tab['tabRenderer'];
        if (renderer?['selected'] == true) {
          final title = renderer['title'];
          if (title != null && title != 'Videos') {
            throw StateError('YouTube did not select the channel Videos tab');
          }
          content = renderer['content'];
        }
      }
    } else {
      content = data['onResponseReceivedActions'] ??
          data['onResponseReceivedEndpoints'] ??
          data['onResponseReceivedCommands'];
    }
    if (content == null) throw StateError('Missing channel uploads response');
    final items = <TubeVideoItem>[];
    String? nextToken;
    void visit(dynamic node) {
      if (node is List) {
        for (final value in node) {
          visit(value);
        }
      } else if (node is Map<String, dynamic>) {
        final video = node['videoRenderer'] ??
            node['gridVideoRenderer'] ??
            node['lockupViewModel'];
        if (video is Map<String, dynamic>) {
          final item = node.containsKey('lockupViewModel')
              ? parseVideoLockup(video)
              : parseVideoRenderer(video);
          if (item != null) {
            items.add(item.copyWith(
              channelId: item.channelId.isEmpty ? channelId : item.channelId,
              channelTitle:
                  item.channelTitle.isEmpty ? channelTitle : item.channelTitle,
              // Membership and livestream cards can legitimately omit duration.
              isShort: false,
            ));
          }
          return;
        }
        final token = node['continuationItemRenderer']?['continuationEndpoint']
            ?['continuationCommand']?['token'];
        if (token is String && token.isNotEmpty) nextToken = token;
        for (final value in node.values) {
          visit(value);
        }
      }
    }

    visit(content);
    return (items: items, continuationToken: nextToken);
  }

  TubeVideoItem? parseShortsLockupViewModel(Map<String, dynamic> slvm) {
    String? videoId = slvm['onTap']?['innertubeCommand']?['reelWatchEndpoint']
        ?['videoId'] as String?;
    if (videoId == null || videoId.isEmpty) {
      final entityId = slvm['entityId'] as String?;
      if (entityId != null && entityId.startsWith('shorts-shelf-item-')) {
        videoId = entityId.replaceFirst('shorts-shelf-item-', '');
      }
    }
    if (videoId == null || videoId.isEmpty) return null;

    String title =
        slvm['overlayMetadata']?['primaryText']?['content']?.toString() ?? '';
    if (title.isEmpty) {
      title = slvm['accessibilityText']?.toString() ?? 'Short';
    }

    final viewCountText =
        slvm['overlayMetadata']?['secondaryText']?['content']?.toString();
    final viewCount = TubeVideoItem.parseViewCount(viewCountText);

    String thumbnailUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    final sources = slvm['thumbnailViewModel']?['thumbnailViewModel']?['image']
        ?['sources'] as List?;
    if (sources != null && sources.isNotEmpty) {
      thumbnailUrl = sources.last?['url']?.toString() ?? thumbnailUrl;
    }

    return TubeVideoItem(
      id: videoId,
      title: title,
      channelTitle: '',
      channelId: '',
      thumbnailUrl: thumbnailUrl,
      durationSeconds: 30,
      viewCount: viewCount,
      viewCountText: viewCountText,
      isShort: true,
      description: title,
    );
  }

  TubeVideoItem? parseReelItemRenderer(Map<String, dynamic> rir) {
    final videoId = rir['videoId'] as String? ??
        rir['navigationEndpoint']?['reelWatchEndpoint']?['videoId'] as String?;
    if (videoId == null || videoId.isEmpty) return null;

    String title = '';
    final headline = rir['headline'];
    if (headline is Map) {
      final runs = headline['runs'] as List?;
      if (runs != null && runs.isNotEmpty) {
        title = runs.map((r) => r['text'] ?? '').join();
      } else {
        title = headline['simpleText']?.toString() ?? '';
      }
    }

    String channelTitle = '';
    final channelRuns = (rir['channelTitleText']?['runs'] ??
        rir['ownerText']?['runs']) as List?;
    if (channelRuns != null && channelRuns.isNotEmpty) {
      channelTitle = channelRuns.map((r) => r['text'] ?? '').join();
    }

    String thumbnailUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    final thumbList = (rir['thumbnail']?['thumbnails'] ??
        rir['thumbnail']?['image']?['sources']) as List?;
    if (thumbList != null && thumbList.isNotEmpty) {
      thumbnailUrl = thumbList.last?['url']?.toString() ?? thumbnailUrl;
    }

    final viewCountText = rir['viewCountText']?['simpleText']?.toString();
    final viewCount = TubeVideoItem.parseViewCount(viewCountText);

    return TubeVideoItem(
      id: videoId,
      title: title.isNotEmpty ? title : 'Short',
      channelTitle: channelTitle,
      channelId: '',
      thumbnailUrl: thumbnailUrl,
      durationSeconds: 30,
      viewCount: viewCount,
      viewCountText: viewCountText,
      isShort: true,
    );
  }

  TubeChannelInfo? parseChannelRenderer(Map<String, dynamic> cr) {
    final channelId = cr['channelId'] as String?;
    if (channelId == null || channelId.isEmpty) return null;

    String title = '';
    final titleRuns =
        cr['title']?['simpleText'] ?? cr['title']?['runs'] as List?;
    if (titleRuns is List) {
      title = titleRuns.map((r) => r['text'] ?? '').join();
    } else if (titleRuns is String) {
      title = titleRuns;
    }

    String avatarUrl = '';
    final thumbList = cr['thumbnail']?['thumbnails'] as List?;
    if (thumbList != null && thumbList.isNotEmpty) {
      avatarUrl = thumbList.last?['url']?.toString() ?? '';
    }

    String subscriberCountText =
        cr['subscriberCountText']?['simpleText']?.toString() ?? '';

    return TubeChannelInfo(
      id: channelId,
      title: title,
      avatarUrl: _absoluteImageUrl(avatarUrl),
      bannerUrl:
          '', // Channel renderer rarely has banner, usually header renderer does
      subscriberCountText: subscriberCountText,
    );
  }

  void dispose() {
    _httpClient.close();
  }
}
