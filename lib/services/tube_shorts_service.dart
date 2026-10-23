import 'package:flutter/foundation.dart';

import '../models/tube_models.dart';
import '../models/tube_stream.dart';
import 'tube_cache_service.dart';
import 'tube_innertube_client.dart';
import 'tube_stream_resolver.dart';

/// Dedicated service for public Shorts feed discovery, pagination, and bounded prefetching.
/// Does not flood network with dozens of resolutions — pre-fetches strictly N+1.
class TubeShortsService {
  static final TubeShortsService _instance = TubeShortsService._internal();
  factory TubeShortsService() => _instance;
  TubeShortsService._internal() : _innertube = TubeInnertubeClient();
  TubeShortsService.withClient(this._innertube);

  final TubeInnertubeClient _innertube;
  final TubeStreamResolver _resolver = TubeStreamResolver();
  final TubeMemoryCache<List<TubeVideoItem>> _cache = TubeMemoryCache(
    defaultTtl: const Duration(minutes: 15),
  );

  // In-memory prefetch stream cache (Key: Video ID, Value: Resolved stream)
  final Map<String, TubeResolvedVideo> _prefetchedStreams = {};
  final Set<String> _currentlyPrefetching = {};

  final Map<int, String?> _continuations = {};
  final Set<String> _seen = {};

  final Map<String, Future<List<TubeVideoItem>>> _pending = {};
  int _epoch = 0;
  String? _identity;
  bool _accountShorts = false;
  void reset() {
    _epoch++;
    _pending.clear();
    _cache.clear();
    _prefetchedStreams.clear();
    _currentlyPrefetching.clear();
    _continuations.clear();
    _seen.clear();
    _identity = null;
    _accountShorts = false;
  }

  /// Keeps the public Shorts ordering and follows actual continuation cursors.
  Future<List<TubeVideoItem>> getShortsFeed({int page = 0}) async {
    final key = '$page/${_innertube.requestIdentity}';
    final existing = _pending[key];
    if (existing != null) return existing;
    final task = _loadShortsFeed(page);
    _pending[key] = task;
    try {
      return await task;
    } finally {
      if (identical(_pending[key], task)) _pending.remove(key);
    }
  }

  Future<List<TubeVideoItem>> _loadShortsFeed(int page) async {
    final identity = _innertube.requestIdentity;
    if (_identity != identity) {
      reset();
      _identity = identity;
      if (page > 0) return [];
    }
    final epoch = _epoch;
    final cacheKey = 'shorts_page_$page/$identity';
    final cached = _cache.get(cacheKey);
    if (cached != null) return cached;
    if (page == 0) {
      _seen.clear();
      _continuations.clear();
    }
    final token = _continuations[page - 1];
    if (page > 0 && token == null) return [];
    TubeFeedPageData? result;
    if (_innertube.isConnected && (page == 0 || _accountShorts)) {
      try {
        final private = await _innertube.shortsFeed(continuation: token);
        if (page > 0 || private.items.isNotEmpty) {
          result = private;
          _accountShorts = true;
        }
      } catch (_) {
        if (page > 0) rethrow;
      }
    }
    if (epoch != _epoch || identity != _innertube.requestIdentity) return [];
    result ??= await _innertube.searchVideos('#shorts viral trending',
        continuation: token);
    if (epoch != _epoch || identity != _innertube.requestIdentity) {
      return [];
    }
    _continuations[page] =
        result.continuationToken == token ? null : result.continuationToken;
    // A short duration or a #shorts title does not establish a Shorts video.
    final items = result.items
        .where((video) => video.isShort && _seen.add(video.id))
        .toList();
    _cache.set(cacheKey, items);
    return items;
  }
  // =========================================================================
  // BOUNDED PREFETCHING (Strictly N+1)
  // =========================================================================

  /// Asynchronously prefetches the video stream for the very next Short.
  /// Strictly bounded to 1 concurrent extraction request.
  Future<void> prefetchNextShort(TubeVideoItem nextShort) async {
    if (nextShort.isMembersOnly) return;
    final epoch = _epoch;
    final videoId = nextShort.id;
    if (_prefetchedStreams.containsKey(videoId) ||
        _currentlyPrefetching.contains(videoId)) {
      return;
    }

    // Limit in-memory cache to 3 prefetched streams
    if (_prefetchedStreams.length >= 3) {
      _prefetchedStreams.remove(_prefetchedStreams.keys.first);
    }

    _currentlyPrefetching.add(videoId);
    try {
      debugPrint(
        '[TubeShortsService] ⚡ Prefetching stream for upcoming short: $videoId ("${nextShort.title}")',
      );
      final resolved = await _resolver.resolve(videoId);
      if (epoch == _epoch) _prefetchedStreams[videoId] = resolved;
    } catch (e) {
      debugPrint('[TubeShortsService] Prefetching skipped for $videoId: $e');
    } finally {
      _currentlyPrefetching.remove(videoId);
    }
  }

  /// Returns prefetched resolved video if available, and frees it from cache
  TubeResolvedVideo? getPrefetchedStream(String videoId) {
    return _prefetchedStreams.remove(videoId);
  }
}
