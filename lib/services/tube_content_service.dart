import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/tube_models.dart';
import 'tube_cache_service.dart';
import 'tube_innertube_client.dart';
import 'tube_youtube_explode_pool.dart';

/// Public content discovery & retrieval service.
/// Uses high-performance YouTube Innertube API with zero-tracking and zero-telemetry.
/// NEVER resolves stream URLs for preview lists.
class TubeContentService {
  static final TubeContentService _instance = TubeContentService._internal();
  factory TubeContentService() => _instance;
  TubeContentService._internal();

  final TubeYoutubeExplodePool _ytPool = TubeYoutubeExplodePool.instance;
  final TubeInnertubeClient _innertube = TubeInnertubeClient();

  final TubeMemoryCache<TubeVideoItem> _videoDetailsCache =
      TubeMemoryCache(defaultTtl: const Duration(minutes: 30));
  final TubeMemoryCache<List<TubeVideoItem>> _relatedCache =
      TubeMemoryCache(defaultTtl: const Duration(minutes: 15));
  final TubeMemoryCache<TubeChannelInfo> _channelCache =
      TubeMemoryCache(defaultTtl: const Duration(hours: 1));

  // Preset search queries for Home discovery categories
  static const Map<String, String> categoryQueries = {
    'Recommended': 'popular viral videos trending',
    'Trending': 'trending videos today popular',
    'Music': 'official music video trending hits',
    'Gaming': 'gaming highlights gameplay trailers',
    'Technology': 'new tech review innovations gadgets',
    'Education': 'science documentary education lecture',
    'News': 'global news headlines today live',
    'Sports': 'sports highlights best moments match',
    'Shorts': 'youtube shorts viral trends',
    'Live': 'live stream now news gaming',
  };

  /// Fetches public feed videos for a selected Home category.
  Future<List<TubeVideoItem>> getCategoryFeed(String category) async {
    final query = categoryQueries[category] ?? categoryQueries['Recommended']!;
    debugPrint('[TubeContentService] Fetching feed for category: $category (query: "$query")');

    try {
      final res = await _innertube.searchVideos(query);
      if (res.items.isNotEmpty) {
        return res.items;
      }
    } catch (e) {
      debugPrint('[TubeContentService] Innertube feed error: $e. Falling back to YoutubeExplode.');
    }

    try {
      final searchList = await _ytPool.yt.search.search(query);
      final List<TubeVideoItem> fallback = [];
      for (final item in searchList) {
        if (item is SearchVideo) {
          fallback.add(TubeVideoItem(
            id: item.id.value,
            title: item.title,
            channelTitle: item.author,
            channelId: item.channelId.value,
            thumbnailUrl: item.thumbnails.highResUrl.isNotEmpty
                ? item.thumbnails.highResUrl
                : 'https://i.ytimg.com/vi/${item.id.value}/hqdefault.jpg',
            durationSeconds: item.duration?.inSeconds ?? 0,
            description: item.description,
          ));
        }
      }
      return fallback;
    } catch (e) {
      debugPrint('[TubeContentService] YoutubeExplode fallback error: $e');
      return [];
    }
  }

  /// Fetches rich details for a single video.
  Future<TubeVideoItem?> getVideoDetails(String videoId) async {
    final cached = _videoDetailsCache.get(videoId);
    if (cached != null) return cached;

    // Primary: Innertube next endpoint
    try {
      final res = await _innertube.next(videoId);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final results = data['contents']?['twoColumnWatchNextResults']?['results']?['results']?['contents'] as List?;
        if (results != null) {
          for (final item in results) {
            final primary = item['videoPrimaryInfoRenderer'];
            if (primary != null) {
              final title = (primary['title']?['runs'] as List?)?.map((r) => r['text']).join() ?? '';
              final viewCountText = (primary['viewCount']?['videoViewCountRenderer']?['viewCount']?['simpleText'] ??
                  primary['viewCount']?['videoViewCountRenderer']?['shortViewCount']?['simpleText']) as String?;
              final views = TubeVideoItem.parseViewCount(viewCountText);
              final dateText = (primary['dateText']?['simpleText'] ??
                  (primary['dateText']?['runs'] as List?)?.map((r) => r['text'] ?? '').join()) as String?;

              final videoItem = TubeVideoItem(
                id: videoId,
                title: title.isNotEmpty ? title : 'Video',
                channelTitle: '',
                channelId: '',
                thumbnailUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
                durationSeconds: 0,
                viewCount: views,
                viewCountText: viewCountText,
                publishedTimeText: dateText,
                uploadDate: TubeVideoItem.parseRelativeTime(dateText),
              );
              _videoDetailsCache.set(videoId, videoItem);
              return videoItem;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[TubeContentService] Innertube getVideoDetails error: $e');
    }

    // Fallback: YoutubeExplode
    try {
      final video = await _ytPool.yt.videos.get(videoId);
      final item = TubeVideoItem(
        id: video.id.value,
        title: video.title,
        channelTitle: video.author,
        channelId: video.channelId.value,
        thumbnailUrl: video.thumbnails.highResUrl.isNotEmpty
            ? video.thumbnails.highResUrl
            : 'https://i.ytimg.com/vi/${video.id.value}/hqdefault.jpg',
        durationSeconds: video.duration?.inSeconds ?? 0,
        viewCount: video.engagement.viewCount,
        uploadDate: video.uploadDate,
        isLive: video.isLive,
        isShort: (video.duration?.inSeconds ?? 0) <= 60,
        description: video.description,
      );
      _videoDetailsCache.set(videoId, item);
      return item;
    } catch (e) {
      debugPrint('[TubeContentService] Error getting video details for $videoId: $e');
      return null;
    }
  }

  /// Fetches related public videos for the Watch page (Up Next / Recommendations).
  Future<List<TubeVideoItem>> getRelatedVideos(String videoId) async {
    final cached = _relatedCache.get(videoId);
    if (cached != null) return cached;

    try {
      final res = await _innertube.next(videoId);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final watchNext = data['contents']?['twoColumnWatchNextResults'];
        final secondary = (watchNext?['secondaryResults']?['secondaryResults']?['results'] ??
            watchNext?['secondaryResults']?['results']) as List?;
        if (secondary != null) {
          final List<TubeVideoItem> items = [];
          for (final item in secondary) {
            final cvr = item['compactVideoRenderer'];
            if (cvr != null) {
              final parsed = _parseCompactVideoRenderer(cvr);
              if (parsed != null) items.add(parsed);
              if (items.length >= 15) break;
            }
          }
          if (items.isNotEmpty) {
            _relatedCache.set(videoId, items);
            return items;
          }
        }
      }
    } catch (e) {
      debugPrint('[TubeContentService] Innertube getRelatedVideos error: $e');
    }

    // Fallback: YoutubeExplode
    try {
      final video = await _ytPool.yt.videos.get(videoId);
      final related = await _ytPool.yt.videos.getRelatedVideos(video);
      if (related == null) return [];

      final List<TubeVideoItem> items = [];
      for (final r in related.take(15)) {
        items.add(TubeVideoItem(
          id: r.id.value,
          title: r.title,
          channelTitle: r.author,
          channelId: r.channelId.value,
          thumbnailUrl: r.thumbnails.highResUrl.isNotEmpty
              ? r.thumbnails.highResUrl
              : 'https://i.ytimg.com/vi/${r.id.value}/hqdefault.jpg',
          durationSeconds: r.duration?.inSeconds ?? 0,
          uploadDate: null,
          isShort: (r.duration?.inSeconds ?? 0) <= 60,
        ));
      }
      _relatedCache.set(videoId, items);
      return items;
    } catch (e) {
      debugPrint('[TubeContentService] Error getting related videos: $e');
      return [];
    }
  }

  TubeVideoItem? _parseCompactVideoRenderer(Map<String, dynamic> cvr) {
    final videoId = cvr['videoId'] as String?;
    if (videoId == null || videoId.isEmpty) return null;

    final title = (cvr['title']?['runs'] as List?)?.map((r) => r['text'] ?? '').join() ?? cvr['title']?['simpleText'] ?? '';
    final channelTitle = (cvr['shortBylineText']?['runs'] as List?)?.map((r) => r['text'] ?? '').join() ?? '';
    final channelId = cvr['shortBylineText']?['runs']?[0]?['navigationEndpoint']?['browseEndpoint']?['browseId'] ?? '';
    final thumb = (cvr['thumbnail']?['thumbnails'] as List?)?.last?['url'] ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    final lenText = cvr['lengthText']?['simpleText'] as String?;

    int durationSeconds = 0;
    if (lenText != null) {
      final parts = lenText.split(':').map((p) => int.tryParse(p) ?? 0).toList();
      if (parts.length == 2) {
        durationSeconds = parts[0] * 60 + parts[1];
      } else if (parts.length == 3) {
        durationSeconds = parts[0] * 3600 + parts[1] * 60 + parts[2];
      }
    }

    String? viewCountText;
    final vText = (cvr['shortViewCountText']?['simpleText'] ?? cvr['viewCountText']?['simpleText']) as String?;
    if (vText != null && vText.isNotEmpty) {
      viewCountText = vText;
    } else {
      final vRuns = (cvr['shortViewCountText']?['runs'] ?? cvr['viewCountText']?['runs']) as List?;
      if (vRuns != null && vRuns.isNotEmpty) {
        viewCountText = vRuns.map((r) => r['text'] ?? '').join();
      }
    }
    final viewCount = TubeVideoItem.parseViewCount(viewCountText);

    String? publishedTimeText;
    final pText = cvr['publishedTimeText']?['simpleText'] as String?;
    if (pText != null && pText.isNotEmpty) {
      publishedTimeText = pText;
    } else {
      final pRuns = cvr['publishedTimeText']?['runs'] as List?;
      if (pRuns != null && pRuns.isNotEmpty) {
        publishedTimeText = pRuns.map((r) => r['text'] ?? '').join();
      }
    }
    final uploadDate = TubeVideoItem.parseRelativeTime(publishedTimeText);

    String channelAvatarUrl = '';
    final avatarThumbs = (cvr['channelThumbnail']?['thumbnails'] ??
            cvr['channelThumbnailSupportedRenderers']?['channelThumbnailWithLinkRenderer']?['thumbnail']?['thumbnails'])
        as List?;
    if (avatarThumbs != null && avatarThumbs.isNotEmpty) {
      channelAvatarUrl = avatarThumbs.last?['url']?.toString() ?? '';
    }

    return TubeVideoItem(
      id: videoId,
      title: title,
      channelTitle: channelTitle,
      channelId: channelId,
      channelAvatarUrl: channelAvatarUrl,
      thumbnailUrl: thumb,
      durationSeconds: durationSeconds,
      viewCount: viewCount,
      viewCountText: viewCountText,
      uploadDate: uploadDate,
      publishedTimeText: publishedTimeText,
      isShort: durationSeconds > 0 && durationSeconds <= 60,
    );
  }

  /// Fetches channel metadata.
  Future<TubeChannelInfo?> getChannel(String channelId) async {
    final cached = _channelCache.get(channelId);
    if (cached != null) return cached;

    try {
      final res = await _innertube.browse(channelId);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final header = data['header']?['c4TabbedHeaderRenderer'] ?? data['header']?['pageHeaderRenderer'];
        final title = header?['title']?['simpleText'] ?? (header?['title']?['runs'] as List?)?.first?['text'] ?? '';
        final avatar = (header?['avatar']?['thumbnails'] as List?)?.last?['url'] ?? '';
        final banner = (header?['banner']?['thumbnails'] as List?)?.last?['url'] ?? '';
        final subs = header?['subscriberCountText']?['simpleText'] ?? '';

        if (title.isNotEmpty) {
          final info = TubeChannelInfo(
            id: channelId,
            title: title,
            avatarUrl: avatar,
            bannerUrl: banner,
            subscriberCountText: subs,
          );
          _channelCache.set(channelId, info);
          return info;
        }
      }
    } catch (e) {
      debugPrint('[TubeContentService] Innertube getChannel error: $e');
    }

    // Fallback: YoutubeExplode
    try {
      final channel = await _ytPool.yt.channels.get(channelId);
      final info = TubeChannelInfo(
        id: channel.id.value,
        title: channel.title,
        avatarUrl: channel.logoUrl,
        bannerUrl: channel.bannerUrl,
        subscriberCountText: '',
      );
      _channelCache.set(channelId, info);
      return info;
    } catch (e) {
      debugPrint('[TubeContentService] Error fetching channel $channelId: $e');
      return null;
    }
  }

  /// Fetches uploads from a channel with a bounded limit.
  Future<List<TubeVideoItem>> getChannelUploads(String channelId, {int limit = 20}) async {
    try {
      final uploads = await _ytPool.yt.channels.getUploads(channelId).take(limit).toList();
      return uploads.map((v) => TubeVideoItem(
            id: v.id.value,
            title: v.title,
            channelTitle: v.author,
            channelId: channelId,
            thumbnailUrl: v.thumbnails.highResUrl,
            durationSeconds: v.duration?.inSeconds ?? 0,
            uploadDate: v.uploadDate,
            isShort: (v.duration?.inSeconds ?? 0) <= 60,
          )).toList();
    } catch (e) {
      debugPrint('[TubeContentService] Error fetching channel uploads: $e');
      return [];
    }
  }

  /// Fetches read-only public comments for a video.
  Future<List<TubeCommentItem>> getComments(String videoId, {int limit = 25}) async {
    try {
      final video = await _ytPool.yt.videos.get(videoId);
      // ignore: deprecated_member_use
      final comments = await _ytPool.yt.videos.commentsClient.getComments(video);
      if (comments == null) return [];

      final List<TubeCommentItem> result = [];
      for (final c in comments.take(limit)) {
        result.add(TubeCommentItem(
          id: '${videoId}_${c.author}_${result.length}',
          author: c.author,
          authorAvatar: '',
          text: c.text,
          publishedTime: c.publishedTime,
          likeCount: c.likeCount,
        ));
      }
      return result;
    } catch (e) {
      debugPrint('[TubeContentService] Error fetching comments: $e');
      return [];
    }
  }
}
