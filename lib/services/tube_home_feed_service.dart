import '../models/tube_models.dart';
import 'tube_cache_service.dart';
import 'tube_database_service.dart';
import 'tube_feed_refresh_controller.dart';
import 'tube_innertube_client.dart';
import 'tube_storage_service.dart';
import 'tube_user_profile_service.dart';
import 'tube_recommendation_engine.dart';

typedef TubeFeedPage = ({List<TubeVideoItem> items, String? continuationToken});
typedef _Discovery = ({TubeFeedPage page, String source, String seed});

/// Public discovery/cursors with bounded local ranking and persisted suppression.
class TubeHomeFeedService {
  static final TubeHomeFeedService _instance = TubeHomeFeedService._internal();
  factory TubeHomeFeedService() => _instance;
  TubeHomeFeedService._internal() : _innertube = TubeInnertubeClient();
  TubeHomeFeedService.withClient(this._innertube);
  final TubeInnertubeClient _innertube;
  final _refreshController = TubeFeedRefreshController();
  final _storage = TubeStorageService();
  final _profile = TubeUserProfileService();
  final _engine = TubeRecommendationEngine();
  final _db = TubeDatabaseService();
  final _cache = TubeMemoryCache<List<TubeVideoItem>>(
      defaultTtl: const Duration(minutes: 10));
  final Map<String, String?> _tokens = {};
  final Map<String, String> _sources = {};
  final Map<String, String> _seeds = {};
  final Map<String, Set<String>> _seen = {};
  final Map<String, int> _generations = {};
  final Map<String, Future<List<TubeVideoItem>>> _pendingPages = {};
  int _resetEpoch = 0;
  String get _privacy =>
      '${_innertube.requestIdentity}/${_storage.isIncognito}/${_storage.pausePersonalization}/${_storage.pauseWatchHistory}/${_storage.pauseSearchHistory}';
  String get requestIdentity => _privacy;
  bool get _personalized =>
      !_innertube.isConnected &&
      !_storage.isIncognito &&
      !_storage.pausePersonalization;
  static const categoryQueries = {
    'Recommended': 'popular videos India',
    'Trending': 'trending today India',
    'Music': 'official music video',
    'Gaming': 'gaming gameplay',
    'Technology': 'technology gadgets review',
    'Education': 'science education',
    'News': 'news today India',
    'Sports': 'sports highlights',
    'Live': 'live news',
  };
  bool hasMore(String category) => _tokens[category]?.isNotEmpty == true;
  void invalidateRecommendedFeed() => _cache.clear();
  void reset() {
    _resetEpoch++;
    _cache.clear();
    _tokens.clear();
    _sources.clear();
    _seeds.clear();
    _seen.clear();
    _generations.clear();
    _pendingPages.clear();
    _refreshController.reset();
  }

  List<TubeVideoItem> _visible(List<TubeVideoItem> items, String category) =>
      items
          .where((v) =>
              !v.isShort &&
              !v.isPrivate &&
              (category != 'Live' || v.isLive) &&
              (!_personalized ||
                  !_storage.isNotInterested(v.id, v.channelTitle)))
          .toList();

  List<String> _queries() {
    if (!_personalized) return [categoryQueries['Recommended']!];
    final learned = _storage.pauseWatchHistory
        ? <String, double>{}
        : _profile.profile.shortTermTopics;
    final searched = _storage.pauseSearchHistory
        ? <String, double>{}
        : _profile.profile.searchInterests;
    final rankedTopics = {...learned, ...searched}.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topics = <String>{
      ...rankedTopics
          .where((e) =>
              e.value > 0.3 &&
              (!_storage.pauseSearchHistory ||
                  !_profile.profile.searchInterests.containsKey(e.key)))
          .map((e) => e.key),
      ..._profile.interests,
      ..._profile.feedTypes
          .where((t) => t != 'Regular videos' && t != 'Shorts'),
      ...List<Map<String, dynamic>>.from(_profile.identity['creators'] ?? [])
          .map((c) => c['title'] as String),
      ..._storage.getFollowedChannels().take(2).map((c) => c.title),
    };
    return topics.isEmpty
        ? [categoryQueries['Recommended']!]
        : topics.take(3).toList();
  }

  Future<_Discovery> _initialPage(String category) async {
    if (category == 'Recommended' && _innertube.isConnected) {
      return (page: await _innertube.homeFeed(), source: 'home', seed: '');
    }
    if (category == 'Recommended') {
      TubeFeedPage? public;
      var source = 'home';
      var seed = '';
      try {
        public = await _innertube.homeFeed();
      } catch (_) {}
      final history = !_personalized || _storage.pauseWatchHistory
          ? <TubeHistoryItem>[]
          : _storage.getWatchHistory();
      if ((public?.items.isEmpty ?? true) && history.isNotEmpty) {
        seed = history.first.video.id;
        source = 'next';
        try {
          public = await _innertube.relatedFeed(seed);
        } catch (_) {}
      }
      if (_personalized &&
          (_profile.interests.isNotEmpty ||
              _profile.feedTypes
                  .any((t) => t != 'Regular videos' && t != 'Shorts') ||
              (!_storage.pauseWatchHistory &&
                  _profile.profile.totalWatchSessions > 0) ||
              (!_storage.pauseSearchHistory &&
                  _profile.profile.searchInterests.isNotEmpty) ||
              _storage.getFollowedChannels().isNotEmpty ||
              List<dynamic>.from(_profile.identity['creators'] ?? [])
                  .isNotEmpty)) {
        final queries = _queries();
        final results = await Future.wait(queries.take(2).map((q) async {
          try {
            return await _innertube.searchVideos(q);
          } catch (_) {
            return (items: <TubeVideoItem>[], continuationToken: null);
          }
        }));
        final selected = results.expand((p) => p.items).toList();
        if (public?.items.isNotEmpty == true) {
          return (
            page: (
              items: [...public!.items, ...selected],
              continuationToken: public.continuationToken
            ),
            source: source,
            seed: seed
          );
        }
        final primaryIndex = results.indexWhere((p) => p.items.isNotEmpty);
        if (primaryIndex >= 0) {
          return (
            page: (
              items: selected,
              continuationToken: results[primaryIndex].continuationToken
            ),
            source: 'search',
            seed: queries[primaryIndex]
          );
        }
      }
      if (public?.items.isNotEmpty == true) {
        return (page: public!, source: source, seed: seed);
      }
    }
    final query = categoryQueries[category] ?? category;
    return (
      page: await _innertube.searchVideos(query),
      source: 'search',
      seed: query
    );
  }

  Future<Set<String>> _suppressed(String category) async {
    if (!_personalized || category != 'Recommended') return {};
    return {
      if (!_storage.pauseWatchHistory)
        ..._storage
            .getWatchHistory()
            .where((h) => h.positionMs >= 30000 || h.completionRatio >= 0.85)
            .map((h) => h.video.id),
      if (!_storage.pauseWatchHistory)
        ..._storage
            .getWatchSignals()
            .where((s) =>
                s.watchDurationSeconds >= 30 || s.completionRatio >= 0.85)
            .map((s) => s.videoId),
      if (_db.isInitialized)
        ...await _db.getRecentlyShownIds(hours: 24, feedType: 'home'),
      if (_db.isInitialized && !_storage.pauseWatchHistory)
        ...await _db.getConsumedIds(),
    };
  }

  Future<TubeFeedPage> _continue(String category, String token) =>
      switch (_sources[category]) {
        'home' => _innertube.homeFeed(continuation: token),
        'next' =>
          _innertube.relatedFeed(_seeds[category] ?? '', continuation: token),
        _ =>
          _innertube.searchVideos(_seeds[category] ?? '', continuation: token),
      };

  Future<List<TubeVideoItem>> generateFreshCandidates(String category) async =>
      _visible((await _initialPage(category)).page.items, category);

  Future<List<TubeVideoItem>> getCategoryFeed(String category,
      {bool forceRefresh = false}) async {
    final privacy = _privacy;
    final epoch = _resetEpoch;
    if (!forceRefresh && !_refreshController.shouldRefreshHome()) {
      final cached = _cache.get('category_$category/$privacy');
      if (cached != null) return cached;
    }
    final generation = (_generations[category] ?? 0) + 1;
    _generations[category] = generation;
    _pendingPages.remove(category);
    final timer = Stopwatch()..start();
    final discovery = await _initialPage(category);
    if (_generations[category] != generation ||
        epoch != _resetEpoch ||
        privacy != _privacy) {
      return [];
    }
    _sources[category] = discovery.source;
    _seeds[category] = discovery.seed;
    _tokens[category] = discovery.page.continuationToken;
    _seen[category] = {};
    final suppressed = await _suppressed(category);
    var page = discovery.page;
    final candidates = <TubeVideoItem>[];
    for (var attempt = 0; attempt < 4; attempt++) {
      if (_generations[category] != generation ||
          epoch != _resetEpoch ||
          privacy != _privacy) {
        return [];
      }
      candidates.addAll(_visible(page.items, category).where(
          (v) => !suppressed.contains(v.id) && _seen[category]!.add(v.id)));
      if (candidates.isNotEmpty || !hasMore(category)) break;
      final token = _tokens[category]!;
      page = await _continue(category, token);
      if (_generations[category] != generation ||
          epoch != _resetEpoch ||
          privacy != _privacy) {
        return [];
      }
      _tokens[category] =
          page.continuationToken == token ? null : page.continuationToken;
    }
    if (_generations[category] != generation ||
        epoch != _resetEpoch ||
        privacy != _privacy) {
      return [];
    }
    final visible = category == 'Recommended' && !_innertube.isConnected
        ? _engine.rankHomeFeed(candidates)
        : candidates;
    if (_personalized && category == 'Recommended' && _db.isInitialized) {
      await _db.recordImpressions(visible.map((v) => v.id).toList(), 'home');
    }
    if (_generations[category] != generation ||
        epoch != _resetEpoch ||
        privacy != _privacy) {
      return [];
    }
    _cache.set('category_$category/$privacy', visible);
    _refreshController.recordHomeRefresh(
        candidateCount: candidates.length,
        suppressedCount: suppressed.length,
        freshCandidateCount: visible
            .where((v) =>
                v.effectiveUploadDate != null &&
                !v.effectiveUploadDate!.isAfter(DateTime.now()) &&
                DateTime.now().difference(v.effectiveUploadDate!).inHours <= 48)
            .length,
        generationDuration: timer.elapsed);
    return visible;
  }

  Future<List<TubeVideoItem>> getCategoryFeedNextPage(String category) async {
    final existing = _pendingPages[category];
    if (existing != null) return existing;
    final task = _nextPage(category);
    _pendingPages[category] = task;
    try {
      return await task;
    } finally {
      if (identical(_pendingPages[category], task)) {
        _pendingPages.remove(category);
      }
    }
  }

  Future<List<TubeVideoItem>> _nextPage(String category) async {
    final generation = _generations[category];
    final epoch = _resetEpoch;
    final privacy = _privacy;
    final suppressed = await _suppressed(category);
    final candidates = <TubeVideoItem>[];
    for (var attempt = 0; attempt < 4 && hasMore(category); attempt++) {
      final token = _tokens[category]!;
      final page = await _continue(category, token);
      if (_generations[category] != generation ||
          epoch != _resetEpoch ||
          privacy != _privacy) {
        return [];
      }
      _tokens[category] =
          page.continuationToken == token ? null : page.continuationToken;
      candidates.addAll(_visible(page.items, category).where((v) =>
          !suppressed.contains(v.id) &&
          _seen.putIfAbsent(category, () => {}).add(v.id)));
      if (candidates.isNotEmpty) break;
    }
    if (_generations[category] != generation ||
        epoch != _resetEpoch ||
        privacy != _privacy) {
      return [];
    }
    final fresh = category == 'Recommended' && !_innertube.isConnected
        ? _engine.rankHomeFeed(candidates)
        : candidates;
    if (_personalized && category == 'Recommended' && _db.isInitialized) {
      await _db.recordImpressions(fresh.map((v) => v.id).toList(), 'home');
    }
    if (_generations[category] != generation ||
        epoch != _resetEpoch ||
        privacy != _privacy) {
      return [];
    }
    _cache.set('category_$category/$privacy',
        [...?_cache.get('category_$category/$privacy'), ...fresh]);
    return fresh;
  }

  Future<List<TubeVideoItem>> getRelatedVideos(
      TubeVideoItem currentVideo) async {
    final epoch = _resetEpoch;
    final privacy = _privacy;
    final key = 'related_${currentVideo.id}/$privacy';
    final cached = _cache.get(key);
    if (cached != null) return cached;
    final page = await _innertube.relatedFeed(currentVideo.id);
    if (epoch != _resetEpoch || privacy != _privacy) return [];
    final items = _visible(page.items, 'Related')
        .where((v) => v.id != currentVideo.id)
        .toList();
    final ranked = _innertube.isConnected
        ? items
        : _engine.rankUpNext(currentVideo: currentVideo, candidates: items);
    if (ranked.isNotEmpty) _cache.set(key, ranked);
    return ranked;
  }
}
