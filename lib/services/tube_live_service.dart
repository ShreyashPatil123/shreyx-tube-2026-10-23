import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/tube_models.dart';
import 'tube_cache_service.dart';
import 'tube_youtube_explode_pool.dart';

/// Discovery and metadata service for genuine live streams.
class TubeLiveService {
  static final TubeLiveService _instance = TubeLiveService._internal();
  factory TubeLiveService() => _instance;
  TubeLiveService._internal();

  final TubeYoutubeExplodePool _ytPool = TubeYoutubeExplodePool.instance;
  final TubeMemoryCache<List<TubeVideoItem>> _cache = TubeMemoryCache(defaultTtl: const Duration(minutes: 5));

  /// Discovers currently active live streams.
  Future<List<TubeVideoItem>> getLiveStreams() async {
    final cached = _cache.get('live_streams');
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final List<TubeVideoItem> items = [];
    try {
      final searchList = await _ytPool.yt.search.search('live stream news music gaming');
      for (final item in searchList) {
        if (item is SearchVideo) {
          // Check for actual live stream indicator
          final durationSec = item.duration?.inSeconds ?? 0;
          final isLikelyLive = durationSec == 0 || item.title.toLowerCase().contains('live') || item.title.toLowerCase().contains('🔴');

          if (isLikelyLive) {
            items.add(TubeVideoItem(
              id: item.id.value,
              title: item.title,
              channelTitle: item.author,
              channelId: item.channelId.value,
              thumbnailUrl: item.thumbnails.highResUrl.isNotEmpty
                  ? item.thumbnails.highResUrl
                  : 'https://i.ytimg.com/vi/${item.id.value}/hqdefault.jpg',
              durationSeconds: durationSec,
              isLive: true,
              description: item.description,
            ));
          }
        }
      }
      _cache.set('live_streams', items);
    } catch (e) {
      debugPrint('[TubeLiveService] Error fetching live streams: $e');
    }
    return items;
  }
}
