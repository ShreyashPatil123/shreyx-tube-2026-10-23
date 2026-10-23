import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/tube_models.dart';
import 'tube_cache_service.dart';
import 'tube_youtube_explode_pool.dart';
import 'tube_innertube_client.dart';
import 'tube_channel_upload_pager.dart';

/// Comprehensive channel discovery service.
/// Retrieves metadata and content across all 5 channel sections:
/// Home, Videos (Latest/Popular/Oldest), Shorts, Live, and Playlists.
/// Streams every single video of a creator on demand via continuous lazy pagination.
class TubeChannelService {
  static final TubeChannelService _instance = TubeChannelService._internal();
  factory TubeChannelService() => _instance;
  TubeChannelService._internal() : _client = TubeInnertubeClient();
  TubeChannelService.withClient(this._client);
  final TubeInnertubeClient _client;
  final TubeYoutubeExplodePool _ytPool = TubeYoutubeExplodePool.instance;
  final TubeMemoryCache<TubeChannelInfo> _infoCache =
      TubeMemoryCache(defaultTtl: const Duration(minutes: 30));
  final Map<String, TubeChannelUploadPager> _pagers = {};
  final Map<String, Map<String, String>> _tabs = {};
  final Map<String, Future<Map<String, dynamic>>> _overview = {};
  final Map<String, String?> _sectionTokens = {};
  final Map<String, List<TubeVideoItem>> _sectionItems = {};
  final Map<String, List<TubeChannelPlaylist>> _sectionPlaylists = {};
  final Map<String, Future<void>> _sectionPending = {};
  int _epoch = 0;
  Set<String> availableTabs(String channelId) => {
        'Home',
        if (!_tabs.containsKey(channelId)) 'Videos',
        ...?_tabs[channelId]?.keys
      };
  Future<Map<String, dynamic>> _getOverview(String id) =>
      _overview.putIfAbsent(id, () async {
        final epoch = _epoch;
        try {
          final data = await _client.channelOverview(id);
          if (epoch != _epoch) return data;
          _tabs[id] = {
            for (final tab
                in TubeInnertubeClient.findNodes(data, 'tabRenderer'))
              if (['Videos', 'Shorts', 'Live', 'Playlists']
                      .contains(tab['title']) &&
                  tab['endpoint']?['browseEndpoint']?['params'] is String)
                tab['title'] as String:
                    tab['endpoint']['browseEndpoint']['params'] as String,
          };
          return data;
        } catch (_) {
          if (epoch == _epoch) _overview.remove(id);
          rethrow;
        }
      });
  bool hasMoreSection(String id, String tab) =>
      _sectionTokens['$id/$tab'] != null;
  Future<void> _loadSection(String id, String tab, {bool more = false}) async {
    final key = '$id/$tab';
    if (_sectionPending[key] != null) return _sectionPending[key];
    if (!more && _sectionItems.containsKey(key)) return;
    final task = _readSection(id, tab, more: more);
    _sectionPending[key] = task;
    try {
      await task;
    } finally {
      if (identical(_sectionPending[key], task)) _sectionPending.remove(key);
    }
  }

  Future<void> _readSection(String id, String tab, {required bool more}) async {
    final epoch = _epoch;
    final info = await getChannel(id);
    if (epoch != _epoch) return;
    final params = _tabs[id]?[tab];
    if (params == null) return;
    final token = more ? _sectionTokens['$id/$tab'] : null;
    if (more && token == null) return;
    final result = await _client.channelSection(info.id, params,
        continuation: token, channelTitle: info.title, shorts: tab == 'Shorts');
    if (epoch != _epoch) return;
    final key = '$id/$tab';
    final videos = more
        ? List<TubeVideoItem>.from(_sectionItems[key] ?? [])
        : <TubeVideoItem>[];
    final ids = videos.map((v) => v.id).toSet();
    videos.addAll(result.page.items.where((v) => ids.add(v.id)));
    _sectionItems[key] = videos;
    final playlists = more
        ? List<TubeChannelPlaylist>.from(_sectionPlaylists[key] ?? [])
        : <TubeChannelPlaylist>[];
    final playlistIds = playlists.map((p) => p.id).toSet();
    playlists.addAll(result.playlists.where((p) => playlistIds.add(p.id)));
    _sectionPlaylists[key] = playlists;
    _sectionTokens[key] = result.page.continuationToken == token
        ? null
        : result.page.continuationToken;
  }

  void clearCache() {
    ++_epoch;
    _infoCache.clear();
    _pagers.clear();
    _overview.clear();
    _tabs.clear();
    _sectionTokens.clear();
    _sectionItems.clear();
    _sectionPlaylists.clear();
    _sectionPending.clear();
  }

  bool hasMoreVideos(String channelId) => _pagers[channelId]?.hasMore ?? true;

  /// Retrieves channel header metadata (banner, avatar, handle, follower count, description)
  Future<TubeChannelInfo> getChannel(String channelId) async {
    final epoch = _epoch;
    final cached = _infoCache.get(channelId);
    if (cached != null) return cached;
    try {
      final data = await _getOverview(channelId);
      final metadata =
          TubeInnertubeClient.findNodes(data, 'channelMetadataRenderer')
                  .firstOrNull ??
              {};
      final legacy =
          TubeInnertubeClient.findNodes(data, 'c4TabbedHeaderRenderer')
                  .firstOrNull ??
              {};
      final view = TubeInnertubeClient.findNodes(data, 'pageHeaderViewModel')
              .firstOrNull ??
          {};
      final avatar = metadata['avatar']?['thumbnails'] ??
          legacy['avatar']?['thumbnails'] ??
          view['image']?['decoratedAvatarViewModel']?['avatar']
              ?['avatarViewModel']?['image']?['sources'];
      final banners = legacy['banner']?['thumbnails'] ??
          view['banner']?['imageBannerViewModel']?['image']?['sources'];
      final rows = view['metadata']?['contentMetadataViewModel']
              ?['metadataRows'] as List? ??
          [];
      final parts = rows
          .expand((r) => r['metadataParts'] as List? ?? [])
          .map((p) => TubeInnertubeClient.text(p['text']))
          .where((t) => t.isNotEmpty)
          .toList();
      final info = TubeChannelInfo(
        id: metadata['externalId'] as String? ?? channelId,
        title: metadata['title'] as String? ??
            legacy['title'] as String? ??
            TubeInnertubeClient.text(
                view['title']?['dynamicTextViewModel']?['text']),
        avatarUrl: avatar is List && avatar.isNotEmpty
            ? avatar.last['url'] as String? ?? ''
            : '',
        bannerUrl: banners is List && banners.isNotEmpty
            ? banners.last['url'] as String? ?? ''
            : '',
        handle: parts.where((s) => s.startsWith('@')).firstOrNull ??
            TubeInnertubeClient.text(legacy['channelHandleText']),
        subscriberCountText:
            parts.where((s) => s.contains('subscriber')).firstOrNull ??
                TubeInnertubeClient.text(legacy['subscriberCountText']),
        description: metadata['description'] as String? ?? '',
      );
      if (epoch == _epoch) _infoCache.set(channelId, info);
      return info;
    } catch (e) {
      debugPrint('[TubeChannelService] Channel header fetch error: $e');
      return TubeChannelInfo(
        id: channelId,
        title: '',
        avatarUrl: '',
      );
    }
  }

  /// Retrieves and sorts all loaded video uploads for the channel.
  Future<List<TubeChannelVideo>> getChannelVideos(
    String channelId, {
    TubeChannelSortOrder sort = TubeChannelSortOrder.latest,
  }) async {
    final rawVideos = await _getRawChannelUploads(channelId);
    // Filter to normal videos (non-shorts)
    final normalVideos = rawVideos.where((v) => !v.isShort).toList();
    // Sort according to user preference
    switch (sort) {
      case TubeChannelSortOrder.popular:
        normalVideos
            .sort((a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0));
        break;
      case TubeChannelSortOrder.oldest:
        normalVideos.sort((a, b) {
          if (a.uploadDate == null && b.uploadDate == null) return 0;
          if (a.uploadDate == null) return 1;
          if (b.uploadDate == null) return -1;
          return a.uploadDate!.compareTo(b.uploadDate!);
        });
        break;
      case TubeChannelSortOrder.latest:
        normalVideos.sort((a, b) {
          if (a.uploadDate == null && b.uploadDate == null) return 0;
          if (a.uploadDate == null) return 1;
          if (b.uploadDate == null) return -1;
          return b.uploadDate!.compareTo(a.uploadDate!);
        });
        break;
    }
    return normalVideos.map((item) {
      return TubeChannelVideo(
        item: item,
        isMembersOnly: item.isMembersOnly,
        isLive: item.isLive,
      );
    }).toList();
  }

  /// Paginates and loads more videos for the channel so every video of the creator is accessible
  Future<List<TubeChannelVideo>> loadMoreChannelVideos(
    String channelId, {
    TubeChannelSortOrder sort = TubeChannelSortOrder.latest,
  }) async {
    await _pager(channelId).loadMore();
    return getChannelVideos(channelId, sort: sort);
  }

  /// Retrieves channel-specific Shorts
  Future<List<TubeChannelShort>> getChannelShorts(String channelId,
      {bool more = false}) async {
    await _loadSection(channelId, 'Shorts', more: more);
    return (_sectionItems['$channelId/Shorts'] ?? [])
        .where((v) => v.isShort)
        .map((v) => TubeChannelShort(item: v, viewCount: v.viewCount))
        .toList();
  }

  Future<List<TubeChannelLive>> getChannelLiveStreams(String channelId,
      {bool more = false}) async {
    await _loadSection(channelId, 'Live', more: more);
    return (_sectionItems['$channelId/Live'] ?? [])
        .map((v) => TubeChannelLive(item: v, isCurrentlyLive: v.isLive))
        .toList();
  }

  Future<List<TubeChannelPlaylist>> getChannelPlaylists(String channelId,
      {bool more = false}) async {
    await _loadSection(channelId, 'Playlists', more: more);
    return _sectionPlaylists['$channelId/Playlists'] ?? [];
  }

  TubeVideoItem _mapVideoToTubeItem(Video video) {
    const isShort = false; // Duration alone never establishes a Short.
    final isLive = video.isLive;
    final views = video.engagement.viewCount;
    return TubeVideoItem(
      id: video.id.value,
      title: video.title,
      channelTitle: video.author,
      channelId: video.channelId.value,
      thumbnailUrl: video.thumbnails.highResUrl.isNotEmpty
          ? video.thumbnails.highResUrl
          : 'https://i.ytimg.com/vi/${video.id.value}/hqdefault.jpg',
      durationSeconds: video.duration?.inSeconds ?? 0,
      uploadDate: video.uploadDate,
      viewCount: views,
      isShort: isShort,
      isLive: isLive,
      description: video.description,
    );
  }

  // --- Internal Helper: Raw Uploads Stream with Caching & Lazy Pagination ---
  Future<List<TubeVideoItem>> _getRawChannelUploads(String channelId) async {
    final pager = _pager(channelId);
    return pager.items.isEmpty ? await pager.loadMore() : pager.items;
  }

  TubeChannelUploadPager _pager(String channelId) => _pagers.putIfAbsent(
      channelId,
      () => TubeChannelUploadPager(
            readPage: (token) async {
              final info = await getChannel(channelId);
              return _client.channelVideos(info.id,
                  continuation: token, channelTitle: info.title);
            },
            fallbackUploads: () => _ytPool.yt.channels
                .getUploads(channelId)
                .map(_mapVideoToTubeItem),
          ));
}
