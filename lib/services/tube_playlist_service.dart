import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/tube_models.dart';
import 'tube_cache_service.dart';
import 'tube_youtube_explode_pool.dart';

/// Public YouTube playlist exploration service.
/// Supports fetching large playlists beyond arbitrary 100-video limits with pagination.
class TubePlaylistService {
  static final TubePlaylistService _instance = TubePlaylistService._internal();
  factory TubePlaylistService() => _instance;
  TubePlaylistService._internal();

  final TubeYoutubeExplodePool _ytPool = TubeYoutubeExplodePool.instance;
  final TubeMemoryCache<List<TubeVideoItem>> _cache =
      TubeMemoryCache(defaultTtl: const Duration(minutes: 30));
  final TubeMemoryCache<Playlist> _metadataCache =
      TubeMemoryCache(defaultTtl: const Duration(hours: 1));

  int _epoch = 0;
  void clearCache() {
    _epoch++;
    _cache.clear();
    _metadataCache.clear();
  }

  /// Retrieves playlist metadata (title, author, video count)
  Future<Playlist?> getPlaylistMetadata(String playlistId) async {
    final epoch = _epoch;
    final cached = _metadataCache.get(playlistId);
    if (cached != null) return cached;
    try {
      final pl = await _ytPool.yt.playlists.get(playlistId);
      if (epoch == _epoch) _metadataCache.set(playlistId, pl);
      return pl;
    } catch (e) {
      debugPrint(
          '[TubePlaylistService] Error fetching playlist metadata $playlistId: $e');
      return null;
    }
  }

  /// Retrieves videos in a public playlist without arbitrary 100-video caps.
  Future<List<TubeVideoItem>> getPlaylistVideos(
    String playlistId, {
    int limit = 200,
    int offset = 0,
  }) async {
    final epoch = _epoch;
    final cacheKey = '${playlistId}_${offset}_$limit';
    final cached = _cache.get(cacheKey);
    if (cached != null) return cached;

    final List<TubeVideoItem> items = [];
    try {
      final stream =
          _ytPool.yt.playlists.getVideos(playlistId).skip(offset).take(limit);
      await for (final v in stream) {
        items.add(TubeVideoItem(
          id: v.id.value,
          title: v.title,
          channelTitle: v.author,
          channelId: v.channelId.value,
          thumbnailUrl: v.thumbnails.highResUrl.isNotEmpty
              ? v.thumbnails.highResUrl
              : 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg',
          durationSeconds: v.duration?.inSeconds ?? 0,
        ));
      }
      if (epoch == _epoch) _cache.set(cacheKey, items);
    } catch (e) {
      debugPrint(
          '[TubePlaylistService] Error fetching playlist $playlistId: $e');
      rethrow;
    }
    return items;
  }
}
