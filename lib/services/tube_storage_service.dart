import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tube_models.dart';
import 'tube_database_service.dart';

/// 100% on-device atomic storage service.
/// All user data stays on this device using native on-device SharedPreferences.
/// NEVER sends any user data to external servers.
/// Respects Incognito Mode and individual privacy pause toggles.
class TubeStorageService extends ChangeNotifier {
  static final TubeStorageService _instance = TubeStorageService._internal();
  factory TubeStorageService() => _instance;
  TubeStorageService._internal();

  SharedPreferences? _prefs;
  bool _initialized = false;

  // In-memory cache for ultra-fast, synchronous reads
  List<TubeHistoryItem> _historyCache = [];
  List<String> _searchHistoryCache = [];
  List<TubeVideoItem> _watchLaterCache = [];
  List<TubeVideoItem> _localLikesCache = [];
  List<TubeLocalPlaylist> _playlistsCache = [];
  List<TubeChannelInfo> _followedChannelsCache = [];
  Map<String, int> _channelAffinities = {};
  List<TubeWatchSignal> _watchSignals = [];
  Set<String> _notInterestedVideoIds = {};
  Set<String> _notInterestedChannels = {};

  // Privacy toggles
  bool _isIncognito = false;
  bool _pauseWatchHistory = false;
  bool _pauseSearchHistory = false;
  bool _pausePersonalization = false;

  bool get isIncognito => _isIncognito;
  bool get pauseWatchHistory => _pauseWatchHistory;
  bool get pauseSearchHistory => _pauseSearchHistory;
  bool get pausePersonalization => _pausePersonalization;

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();

    // Load privacy preferences
    _isIncognito = _prefs?.getBool('pref_incognito') ?? false;
    _pauseWatchHistory = _prefs?.getBool('pref_pause_watch_history') ?? false;
    _pauseSearchHistory = _prefs?.getBool('pref_pause_search_history') ?? false;
    _pausePersonalization =
        _prefs?.getBool('pref_pause_personalization') ?? false;

    TubeDatabaseService().setIncognito(_isIncognito);
    TubeDatabaseService().setPauseWatchHistory(_pauseWatchHistory);
    TubeDatabaseService().setPauseSearchHistory(_pauseSearchHistory);
    TubeDatabaseService().setPausePersonalization(_pausePersonalization);
    // Load datasets from on-device persistence
    await _loadAllData();
    _initialized = true;
    debugPrint(
        '[TubeStorageService] Initialized. Incognito: $_isIncognito, Followed: ${_followedChannelsCache.length}');
  }

  // --- On-Device Storage Helpers ---

  Future<void> _writeStore(String key, String content) async {
    if (_prefs == null ||
        !await _prefs!.setString('tube_store_$key', content)) {
      throw StateError('Could not save local data');
    }
  }

  Future<String?> _readStore(String key) async {
    return _prefs?.getString('tube_store_$key');
  }

  Future<void> writeStoreFile(String key, String content) async {
    await init();
    await _writeStore(key, content);
  }

  Future<String?> readStoreFile(String key) async {
    await init();
    return _readStore(key);
  }

  Future<void> _loadAllData() async {
    try {
      // 1. History
      final histStr = await _readStore('history.json');
      if (histStr != null && histStr.isNotEmpty) {
        final list = jsonDecode(histStr) as List<dynamic>;
        _historyCache = list
            .map((e) => TubeHistoryItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      // 2. Search History
      final searchStr = await _readStore('search_history.json');
      if (searchStr != null && searchStr.isNotEmpty) {
        final list = jsonDecode(searchStr) as List<dynamic>;
        _searchHistoryCache = list.map((e) => e.toString()).toList();
      }

      // 3. Watch Later
      final wlStr = await _readStore('watch_later.json');
      if (wlStr != null && wlStr.isNotEmpty) {
        final list = jsonDecode(wlStr) as List<dynamic>;
        _watchLaterCache = list
            .map((e) => TubeVideoItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      // 4. Local Likes
      final likesStr = await _readStore('local_likes.json');
      if (likesStr != null && likesStr.isNotEmpty) {
        final list = jsonDecode(likesStr) as List<dynamic>;
        _localLikesCache = list
            .map((e) => TubeVideoItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      // 5. Playlists
      final plStr = await _readStore('playlists.json');
      if (plStr != null && plStr.isNotEmpty) {
        final list = jsonDecode(plStr) as List<dynamic>;
        _playlistsCache = list
            .map((e) => TubeLocalPlaylist.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      // 6. Followed Channels ("My Channels")
      final chStr = await _readStore('followed_channels.json');
      if (chStr != null && chStr.isNotEmpty) {
        final list = jsonDecode(chStr) as List<dynamic>;
        _followedChannelsCache = list
            .map((e) => TubeChannelInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      // 7. Channel Affinities
      final affStr = await _readStore('affinities.json');
      if (affStr != null && affStr.isNotEmpty) {
        final map = jsonDecode(affStr) as Map<String, dynamic>;
        _channelAffinities = map.map((k, v) => MapEntry(k, (v as num).toInt()));
      }

      // 8. Watch Behavioral Signals
      final sigStr = await _readStore('watch_signals.json');
      if (sigStr != null && sigStr.isNotEmpty) {
        final list = jsonDecode(sigStr) as List<dynamic>;
        _watchSignals = list
            .map((e) => TubeWatchSignal.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      // 9. Negative feedback ("Not interested")
      final niVidStr = await _readStore('not_interested_videos.json');
      if (niVidStr != null && niVidStr.isNotEmpty) {
        final list = jsonDecode(niVidStr) as List<dynamic>;
        _notInterestedVideoIds = list.map((e) => e.toString()).toSet();
      }

      final niChanStr = await _readStore('not_interested_channels.json');
      if (niChanStr != null && niChanStr.isNotEmpty) {
        final list = jsonDecode(niChanStr) as List<dynamic>;
        _notInterestedChannels =
            list.map((e) => e.toString().toLowerCase()).toSet();
      }
    } catch (e) {
      debugPrint('[TubeStorageService] Error loading local datasets: $e');
      rethrow;
    }
  }

  // =========================================================================
  // PRIVACY TOGGLES
  // =========================================================================

  Future<void> setIncognito(bool value) async {
    _isIncognito = value;
    TubeDatabaseService().setIncognito(value);
    notifyListeners();
    await _prefs?.setBool('pref_incognito', value);
  }

  Future<void> setPauseWatchHistory(bool value) async {
    _pauseWatchHistory = value;
    TubeDatabaseService().setPauseWatchHistory(value);
    notifyListeners();
    await _prefs?.setBool('pref_pause_watch_history', value);
  }

  Future<void> setPauseSearchHistory(bool value) async {
    _pauseSearchHistory = value;
    TubeDatabaseService().setPauseSearchHistory(value);
    notifyListeners();
    await _prefs?.setBool('pref_pause_search_history', value);
  }

  Future<void> setPausePersonalization(bool value) async {
    _pausePersonalization = value;
    TubeDatabaseService().setPausePersonalization(value);
    notifyListeners();
    await _prefs?.setBool('pref_pause_personalization', value);
  }

  // =========================================================================
  // WATCH HISTORY & RESUME POSITIONS
  // =========================================================================

  List<TubeHistoryItem> getWatchHistory() => List.unmodifiable(_historyCache);

  TubeHistoryItem? getHistoryItem(String videoId) {
    try {
      return _historyCache.firstWhere((item) => item.video.id == videoId);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveWatchPosition(
      TubeVideoItem video, int positionMs, int durationMs) async {
    if (_isIncognito || _pauseWatchHistory) return;

    // Remove existing entry for same video
    _historyCache.removeWhere((item) => item.video.id == video.id);

    final historyItem = TubeHistoryItem(
      video: video,
      watchedAt: DateTime.now(),
      positionMs: positionMs,
      durationMs: durationMs,
    );

    // Keep history sorted with newest on top
    _historyCache.insert(0, historyItem);

    // Limit on-device history items to 250
    if (_historyCache.length > 250) {
      _historyCache.removeLast();
    }

    // Record on-device channel affinity signal
    if (!_pausePersonalization && video.channelTitle.isNotEmpty) {
      _channelAffinities[video.channelTitle] =
          (_channelAffinities[video.channelTitle] ?? 0) + 1;
      _writeStore('affinities.json', jsonEncode(_channelAffinities));
    }

    await _writeStore('history.json',
        jsonEncode(_historyCache.map((e) => e.toJson()).toList()));
  }

  Future<void> removeHistoryItem(String videoId) async {
    _historyCache.removeWhere((item) => item.video.id == videoId);
    await _writeStore('history.json',
        jsonEncode(_historyCache.map((e) => e.toJson()).toList()));
  }

  List<TubeHistoryItem> getResumeItems() {
    return _historyCache.where((item) => item.isResumeAvailable).toList();
  }

  Future<void> clearWatchHistory() async {
    _historyCache.clear();
    await _writeStore('history.json', '[]');
  }

  // =========================================================================
  // SEARCH HISTORY
  // =========================================================================

  List<String> getSearchHistory() => List.unmodifiable(_searchHistoryCache);

  Future<void> addSearchQuery(String query) async {
    final clean = query.trim();
    if (clean.isEmpty || _isIncognito || _pauseSearchHistory) return;

    _searchHistoryCache.remove(clean);
    _searchHistoryCache.insert(0, clean);

    if (_searchHistoryCache.length > 50) {
      _searchHistoryCache.removeLast();
    }

    await _writeStore('search_history.json', jsonEncode(_searchHistoryCache));
  }

  Future<void> removeSearchQuery(String query) async {
    _searchHistoryCache.remove(query);
    await _writeStore('search_history.json', jsonEncode(_searchHistoryCache));
  }

  Future<void> clearSearchHistory() async {
    _searchHistoryCache.clear();
    await _writeStore('search_history.json', '[]');
  }

  // =========================================================================
  // WATCH LATER
  // =========================================================================

  List<TubeVideoItem> getWatchLater() => List.unmodifiable(_watchLaterCache);

  bool isInWatchLater(String videoId) {
    return _watchLaterCache.any((v) => v.id == videoId);
  }

  Future<bool> toggleWatchLater(TubeVideoItem video) async {
    final exists = isInWatchLater(video.id);
    if (exists) {
      _watchLaterCache.removeWhere((v) => v.id == video.id);
    } else {
      _watchLaterCache.insert(0, video);
    }
    await _writeStore('watch_later.json',
        jsonEncode(_watchLaterCache.map((e) => e.toJson()).toList()));
    return !exists;
  }

  // =========================================================================
  // LOCAL LIKES
  // =========================================================================

  List<TubeVideoItem> getLocalLikes() => List.unmodifiable(_localLikesCache);

  bool isLikedLocally(String videoId) {
    return _localLikesCache.any((v) => v.id == videoId);
  }

  Future<bool> toggleLocalLike(TubeVideoItem video) async {
    final exists = isLikedLocally(video.id);
    if (exists) {
      _localLikesCache.removeWhere((v) => v.id == video.id);
    } else {
      _localLikesCache.insert(0, video);
    }
    await _writeStore('local_likes.json',
        jsonEncode(_localLikesCache.map((e) => e.toJson()).toList()));
    return !exists;
  }

  // =========================================================================
  // LOCAL PLAYLISTS
  // =========================================================================

  List<TubeLocalPlaylist> getPlaylists() => List.unmodifiable(_playlistsCache);

  Future<TubeLocalPlaylist> createPlaylist(String title,
      {String description = ''}) async {
    final id = 'local_pl_${DateTime.now().millisecondsSinceEpoch}';
    final playlist = TubeLocalPlaylist(
      id: id,
      title: title,
      description: description,
      createdAt: DateTime.now(),
      videos: [],
    );
    _playlistsCache.insert(0, playlist);
    await _writeStore('playlists.json',
        jsonEncode(_playlistsCache.map((e) => e.toJson()).toList()));
    return playlist;
  }

  Future<void> deletePlaylist(String playlistId) async {
    _playlistsCache.removeWhere((p) => p.id == playlistId);
    await _writeStore('playlists.json',
        jsonEncode(_playlistsCache.map((e) => e.toJson()).toList()));
  }

  Future<void> addToPlaylist(String playlistId, TubeVideoItem video) async {
    final idx = _playlistsCache.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      final p = _playlistsCache[idx];
      if (!p.videos.any((v) => v.id == video.id)) {
        final updatedList = List<TubeVideoItem>.from(p.videos)
          ..insert(0, video);
        _playlistsCache[idx] = p.copyWith(videos: updatedList);
        await _writeStore('playlists.json',
            jsonEncode(_playlistsCache.map((e) => e.toJson()).toList()));
      }
    }
  }

  Future<void> removeFromPlaylist(String playlistId, String videoId) async {
    final idx = _playlistsCache.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      final p = _playlistsCache[idx];
      final updatedList = p.videos.where((v) => v.id != videoId).toList();
      _playlistsCache[idx] = p.copyWith(videos: updatedList);
      await _writeStore('playlists.json',
          jsonEncode(_playlistsCache.map((e) => e.toJson()).toList()));
    }
  }

  // =========================================================================
  // FOLLOWED CHANNELS ("MY CHANNELS" / "FOLLOWING")
  // =========================================================================

  List<TubeChannelInfo> getFollowedChannels() =>
      List.unmodifiable(_followedChannelsCache);

  bool isChannelFollowed(String channelId) {
    return _followedChannelsCache.any((c) => c.id == channelId);
  }

  Future<bool> toggleFollowChannel(TubeChannelInfo channel) async {
    final exists = isChannelFollowed(channel.id);
    if (exists) {
      _followedChannelsCache.removeWhere((c) => c.id == channel.id);
    } else {
      _followedChannelsCache.insert(
          0, channel.copyWith(isFollowed: true, followedAt: DateTime.now()));
    }
    await _writeStore('followed_channels.json',
        jsonEncode(_followedChannelsCache.map((e) => e.toJson()).toList()));
    return !exists;
  }

  // =========================================================================
  // BEHAVIORAL RECOMMENDATION SIGNALS & NEGATIVE FEEDBACK
  // =========================================================================

  Map<String, int> getChannelAffinities() =>
      Map.unmodifiable(_channelAffinities);

  List<TubeWatchSignal> getWatchSignals() => List.unmodifiable(_watchSignals);

  Set<String> getNotInterestedVideoIds() =>
      Set.unmodifiable(_notInterestedVideoIds);

  Set<String> getNotInterestedChannels() =>
      Set.unmodifiable(_notInterestedChannels);

  bool isNotInterested(String videoId, String channelTitle) {
    return _notInterestedVideoIds.contains(videoId) ||
        _notInterestedChannels.contains(channelTitle.toLowerCase());
  }

  Future<void> recordWatchSignal(TubeWatchSignal signal) async {
    if (_isIncognito || _pausePersonalization || _pauseWatchHistory) return;

    _watchSignals.insert(0, signal);
    if (_watchSignals.length > 200) {
      _watchSignals.removeLast();
    }
    await _writeStore('watch_signals.json',
        jsonEncode(_watchSignals.map((e) => e.toJson()).toList()));
  }

  Future<void> addNotInterestedVideo(String videoId) async {
    if (_isIncognito) return;
    _notInterestedVideoIds.add(videoId);
    await _writeStore('not_interested_videos.json',
        jsonEncode(_notInterestedVideoIds.toList()));
  }

  Future<void> addNotInterestedChannel(String channelTitle) async {
    if (_isIncognito || channelTitle.trim().isEmpty) return;
    _notInterestedChannels.add(channelTitle.trim().toLowerCase());
    await _writeStore('not_interested_channels.json',
        jsonEncode(_notInterestedChannels.toList()));
  }

  Future<void> markNotInterested(String videoId) =>
      addNotInterestedVideo(videoId);
  Future<void> blockChannel(String channelTitle) =>
      addNotInterestedChannel(channelTitle);

  // =========================================================================
  // PRIVACY CONTROLS & STORAGE BREAKDOWN
  // =========================================================================

  Future<void> clearAllLocalData() async {
    _historyCache.clear();
    _searchHistoryCache.clear();
    _watchLaterCache.clear();
    _localLikesCache.clear();
    _playlistsCache.clear();
    _followedChannelsCache.clear();
    _channelAffinities.clear();
    _watchSignals.clear();
    _notInterestedVideoIds.clear();
    _notInterestedChannels.clear();

    await _writeStore('history.json', '[]');
    await _writeStore('search_history.json', '[]');
    await _writeStore('watch_later.json', '[]');
    await _writeStore('local_likes.json', '[]');
    await _writeStore('playlists.json', '[]');
    await _writeStore('followed_channels.json', '[]');
    await _writeStore('affinities.json', '{}');
    await _writeStore('watch_signals.json', '[]');
    await _writeStore('not_interested_videos.json', '[]');
    await _writeStore('not_interested_channels.json', '[]');
    if (_prefs == null || !await _prefs!.clear()) {
      throw StateError('Could not clear preferences');
    }
    _isIncognito = _pauseWatchHistory =
        _pauseSearchHistory = _pausePersonalization = false;
  }

  Future<Map<String, dynamic>> getStorageUsageBreakdown() async {
    int totalBytes = 0;
    final keys = [
      'history.json',
      'search_history.json',
      'watch_later.json',
      'local_likes.json',
      'playlists.json',
      'followed_channels.json',
      'affinities.json',
      'watch_signals.json',
      'not_interested_videos.json',
      'not_interested_channels.json',
    ];

    final details = <String, int>{};
    for (final k in keys) {
      final str = _prefs?.getString('tube_store_$k');
      final len = str?.length ?? 0;
      totalBytes += len;
      details[k] = len;
    }

    return {
      'totalBytes': totalBytes,
      'formattedSize': '${(totalBytes / 1024).toStringAsFixed(1)} KB',
      'historyCount': _historyCache.length,
      'searchCount': _searchHistoryCache.length,
      'watchLaterCount': _watchLaterCache.length,
      'likesCount': _localLikesCache.length,
      'playlistsCount': _playlistsCache.length,
      'followedChannelsCount': _followedChannelsCache.length,
      'details': details,
    };
  }
}
