import 'dart:convert';
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class TubeDatabaseService {
  static final TubeDatabaseService instance = TubeDatabaseService._internal();
  factory TubeDatabaseService() => instance;
  TubeDatabaseService._internal();

  Database? _db;
  bool get isInitialized => _db != null;
  bool _incognito = false;
  bool _pauseWatchHistory = false;
  bool _pauseSearchHistory = false;
  bool _pausePersonalization = false;

  Future<Database>? _opening;
  Future<Database> get database => init();
  Future<Database> init() => _db != null
      ? Future.value(_db!)
      : (_opening ??=
          _open().then((db) => _db = db).whenComplete(() => _opening = null));

  Future<Database> _open() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'shreyx_tube.db');

    return await openDatabase(
      path,
      version: 3,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createIndexes(db);
        if (oldVersion < 3) await _createIntelligenceTable(db);
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE watch_history (
            video_id TEXT PRIMARY KEY,
            title TEXT,
            channel_title TEXT,
            channel_id TEXT,
            channel_avatar_url TEXT,
            thumbnail_url TEXT,
            duration_ms INTEGER,
            position_ms INTEGER,
            completion_pct REAL,
            play_count INTEGER,
            last_watched_at INTEGER,
            created_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE watch_signals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            video_id TEXT,
            channel_id TEXT,
            topics TEXT,
            completion_ratio REAL,
            watch_duration_ms INTEGER,
            is_rewatch INTEGER,
            is_fast_skip INTEGER,
            created_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE feed_impressions (
            video_id TEXT,
            feed_type TEXT,
            shown_at INTEGER,
            was_clicked INTEGER,
            was_skipped INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE feed_state (
            feed_type TEXT PRIMARY KEY,
            generation_id TEXT,
            last_refresh_at INTEGER,
            candidate_count INTEGER,
            suppressed_count INTEGER,
            fresh_candidate_count INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE feedback (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            video_id TEXT,
            channel_id TEXT,
            action TEXT,
            created_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE search_history (
            query TEXT PRIMARY KEY,
            searched_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE followed_channels (
            channel_id TEXT PRIMARY KEY,
            channel_title TEXT,
            channel_avatar_url TEXT,
            followed_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE local_playlists (
            id TEXT PRIMARY KEY,
            name TEXT,
            created_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE playlist_items (
            playlist_id TEXT,
            video_id TEXT,
            video_json TEXT,
            added_at INTEGER,
            sort_order INTEGER,
            PRIMARY KEY(playlist_id, video_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE watch_later (
            video_id TEXT PRIMARY KEY,
            video_json TEXT,
            added_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE liked_videos (
            video_id TEXT PRIMARY KEY,
            video_json TEXT,
            liked_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE downloads (
            video_id TEXT PRIMARY KEY,
            download_json TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE user_profile (
            key TEXT PRIMARY KEY,
            value_json TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        await _createIndexes(db);
        await _createIntelligenceTable(db);
      },
    );
  }

  static Future<void> _createIndexes(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS impressions_shown ON feed_impressions(feed_type, shown_at, video_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS signals_created ON watch_signals(created_at)');
  }

  static Future<void> _createIntelligenceTable(Database db) async {
    await db.execute(
        'CREATE TABLE IF NOT EXISTS video_intelligence (video_id TEXT PRIMARY KEY, title TEXT NOT NULL, notes TEXT NOT NULL, responses TEXT NOT NULL, digest TEXT NOT NULL, updated_at INTEGER NOT NULL)');
  }

  /// Identity/preferences and completion commit together. Never mark a failed save complete.
  Future<void> saveIdentity(Map<String, dynamic> identity,
      {bool complete = false}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('user_profile',
          {'key': 'identity', 'value_json': jsonEncode(identity)},
          conflictAlgorithm: ConflictAlgorithm.replace);
      if (complete) {
        await txn.insert(
            'settings', {'key': 'onboarding_completed', 'value': 'true'},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<bool> isMigrated() async {
    final val = await getSetting('is_migrated');
    return val == 'true';
  }

  Future<void> markMigrated() async {
    await setSetting('is_migrated', 'true');
  }

  // Watch History
  Future<void> upsertWatchHistory(
      String videoId, Map<String, dynamic> data) async {
    if (_incognito || _pauseWatchHistory) return;
    final db = await database;
    await db.insert(
        'watch_history',
        {
          'video_id': videoId,
          ...data,
          'last_watched_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getWatchHistory(
      {int limit = 50, int offset = 0}) async {
    final db = await database;
    return await db.query('watch_history',
        orderBy: 'last_watched_at DESC', limit: limit, offset: offset);
  }

  Future<int> getResumePosition(String videoId) async {
    final db = await database;
    final res = await db.query('watch_history',
        columns: ['position_ms'], where: 'video_id = ?', whereArgs: [videoId]);
    if (res.isNotEmpty) {
      return (res.first['position_ms'] as int?) ?? 0;
    }
    return 0;
  }

  Future<List<Map<String, dynamic>>> getResumeItems({int limit = 10}) async {
    final db = await database;
    return await db.query('watch_history',
        where: 'completion_pct > 0 AND completion_pct < 0.95',
        orderBy: 'last_watched_at DESC',
        limit: limit);
  }

  Future<void> clearWatchHistory() async {
    final db = await database;
    await db.delete('watch_history');
  }

  // Watch Signals
  Future<void> insertWatchSignal(Map<String, dynamic> signal) async {
    if (_incognito || _pausePersonalization || _pauseWatchHistory) return;
    final db = await database;
    await db.insert('watch_signals', signal);
  }

  Future<List<Map<String, dynamic>>> getRecentSignals({int limit = 100}) async {
    final db = await database;
    return await db.query('watch_signals',
        orderBy: 'created_at DESC', limit: limit);
  }

  Future<List<String>> getConsumedIds() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT DISTINCT video_id FROM watch_signals WHERE watch_duration_ms >= 30000 OR completion_ratio >= 0.85');
    return rows.map((row) => row['video_id'] as String).toList();
  }

  Future<List<String>> getTopChannelIds({int limit = 10, int days = 30}) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final res = await db.rawQuery('''
      SELECT channel_id, COUNT(*) as count 
      FROM watch_signals 
      WHERE created_at > ? 
      GROUP BY channel_id 
      ORDER BY count DESC 
      LIMIT ?
    ''', [cutoff, limit]);
    return res.map((r) => r['channel_id'] as String).toList();
  }

  Future<List<String>> getTopTopics({int limit = 10, int days = 30}) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final res = await db.query('watch_signals',
        columns: ['topics'], where: 'created_at > ?', whereArgs: [cutoff]);
    final Map<String, int> topicCounts = {};
    for (final r in res) {
      final topicsJson = r['topics'] as String?;
      if (topicsJson != null) {
        final topics = List<String>.from(jsonDecode(topicsJson));
        for (final t in topics) {
          topicCounts[t] = (topicCounts[t] ?? 0) + 1;
        }
      }
    }
    final sorted = topicCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList();
  }

  // Feed Impressions
  Future<void> recordImpressions(List<String> videoIds, String feedType) async {
    if (_incognito || _pausePersonalization) return;
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final id in videoIds) {
      batch.insert('feed_impressions', {
        'video_id': id,
        'feed_type': feedType,
        'shown_at': now,
        'was_clicked': 0,
        'was_skipped': 0,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<int> getImpressionCount(String videoId, {int hours = 24}) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(Duration(hours: hours)).millisecondsSinceEpoch;
    final res = await db.rawQuery(
        'SELECT COUNT(*) as count FROM feed_impressions WHERE video_id = ? AND shown_at > ?',
        [videoId, cutoff]);
    return (res.first['count'] as int?) ?? 0;
  }

  Future<List<String>> getRecentlyShownIds(
      {int hours = 24, String? feedType}) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(Duration(hours: hours)).millisecondsSinceEpoch;
    final res = await db.query('feed_impressions',
        columns: ['video_id'],
        where: 'shown_at > ?${feedType == null ? '' : ' AND feed_type = ?'}',
        whereArgs: [cutoff, if (feedType != null) feedType]);
    return res.map((r) => r['video_id'] as String).toSet().toList();
  }

  // Feed State
  Future<Map<String, dynamic>?> getFeedState(String feedType) async {
    final db = await database;
    final res = await db
        .query('feed_state', where: 'feed_type = ?', whereArgs: [feedType]);
    if (res.isNotEmpty) return res.first;
    return null;
  }

  Future<void> upsertFeedState(
      String feedType, Map<String, dynamic> state) async {
    final db = await database;
    await db.insert(
        'feed_state',
        {
          'feed_type': feedType,
          ...state,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Feedback
  Future<void> addFeedback(
      String videoId, String channelId, String action) async {
    final db = await database;
    await db.insert('feedback', {
      'video_id': videoId,
      'channel_id': channelId,
      'action': action,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<String>> getNotInterestedVideoIds() async {
    final db = await database;
    final res = await db.query('feedback',
        columns: ['video_id'],
        where: 'action = ?',
        whereArgs: ['not_interested']);
    return res.map((r) => r['video_id'] as String).toList();
  }

  Future<List<String>> getBlockedChannelIds() async {
    final db = await database;
    final res = await db.query('feedback',
        columns: ['channel_id'],
        where: 'action = ?',
        whereArgs: ['dont_recommend_channel']);
    return res.map((r) => r['channel_id'] as String).toList();
  }

  // Search History
  Future<void> addSearchQuery(String query) async {
    if (_incognito || _pauseSearchHistory) return;
    final db = await database;
    await db.insert(
        'search_history',
        {
          'query': query,
          'searched_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<String>> getSearchHistory({int limit = 20}) async {
    final db = await database;
    final res = await db.query('search_history',
        orderBy: 'searched_at DESC', limit: limit);
    return res.map((r) => r['query'] as String).toList();
  }

  Future<void> deleteSearchQuery(String query) async {
    final db = await database;
    await db.delete('search_history', where: 'query = ?', whereArgs: [query]);
  }

  Future<void> clearSearchHistory() async {
    final db = await database;
    await db.delete('search_history');
  }

  // Followed Channels
  Future<void> toggleFollowChannel(
      String channelId, String channelTitle, String channelAvatarUrl) async {
    final db = await database;
    final exists = await isFollowing(channelId);
    if (exists) {
      await db.delete('followed_channels',
          where: 'channel_id = ?', whereArgs: [channelId]);
    } else {
      await db.insert('followed_channels', {
        'channel_id': channelId,
        'channel_title': channelTitle,
        'channel_avatar_url': channelAvatarUrl,
        'followed_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getFollowedChannels() async {
    final db = await database;
    return await db.query('followed_channels', orderBy: 'channel_title ASC');
  }

  Future<bool> isFollowing(String channelId) async {
    final db = await database;
    final res = await db.query('followed_channels',
        columns: ['channel_id'],
        where: 'channel_id = ?',
        whereArgs: [channelId]);
    return res.isNotEmpty;
  }

  // Local Playlists
  Future<void> createPlaylist(String id, String name) async {
    final db = await database;
    await db.insert('local_playlists', {
      'id': id,
      'name': name,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deletePlaylist(String id) async {
    final db = await database;
    await db.delete('local_playlists', where: 'id = ?', whereArgs: [id]);
    await db
        .delete('playlist_items', where: 'playlist_id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getPlaylists() async {
    final db = await database;
    return await db.query('local_playlists', orderBy: 'created_at DESC');
  }

  Future<void> addToPlaylist(String playlistId, String videoId,
      Map<String, dynamic> videoJson, int sortOrder) async {
    final db = await database;
    await db.insert(
        'playlist_items',
        {
          'playlist_id': playlistId,
          'video_id': videoId,
          'video_json': jsonEncode(videoJson),
          'added_at': DateTime.now().millisecondsSinceEpoch,
          'sort_order': sortOrder,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeFromPlaylist(String playlistId, String videoId) async {
    final db = await database;
    await db.delete('playlist_items',
        where: 'playlist_id = ? AND video_id = ?',
        whereArgs: [playlistId, videoId]);
  }

  Future<List<Map<String, dynamic>>> getPlaylistItems(String playlistId) async {
    final db = await database;
    return await db.query('playlist_items',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
        orderBy: 'sort_order ASC');
  }

  // Watch Later
  Future<void> toggleWatchLater(
      String videoId, Map<String, dynamic> videoJson) async {
    final db = await database;
    final exists = await isInWatchLater(videoId);
    if (exists) {
      await db
          .delete('watch_later', where: 'video_id = ?', whereArgs: [videoId]);
    } else {
      await db.insert('watch_later', {
        'video_id': videoId,
        'video_json': jsonEncode(videoJson),
        'added_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getWatchLater() async {
    final db = await database;
    return await db.query('watch_later', orderBy: 'added_at DESC');
  }

  Future<bool> isInWatchLater(String videoId) async {
    final db = await database;
    final res = await db.query('watch_later',
        columns: ['video_id'], where: 'video_id = ?', whereArgs: [videoId]);
    return res.isNotEmpty;
  }

  // Liked Videos
  Future<void> toggleLike(
      String videoId, Map<String, dynamic> videoJson) async {
    final db = await database;
    final exists = await isLiked(videoId);
    if (exists) {
      await db
          .delete('liked_videos', where: 'video_id = ?', whereArgs: [videoId]);
    } else {
      await db.insert('liked_videos', {
        'video_id': videoId,
        'video_json': jsonEncode(videoJson),
        'liked_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getLikedVideos() async {
    final db = await database;
    return await db.query('liked_videos', orderBy: 'liked_at DESC');
  }

  Future<bool> isLiked(String videoId) async {
    final db = await database;
    final res = await db.query('liked_videos',
        columns: ['video_id'], where: 'video_id = ?', whereArgs: [videoId]);
    return res.isNotEmpty;
  }

  // Downloads
  Future<void> saveDownload(
      String videoId, Map<String, dynamic> downloadJson) async {
    final db = await database;
    await db.insert(
        'downloads',
        {
          'video_id': videoId,
          'download_json': jsonEncode(downloadJson),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getDownloads() async {
    final db = await database;
    return await db.query('downloads');
  }

  Future<void> deleteDownload(String videoId) async {
    final db = await database;
    await db.delete('downloads', where: 'video_id = ?', whereArgs: [videoId]);
  }

  // User Profile
  Future<void> saveProfileData(String key, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
        'user_profile',
        {
          'key': key,
          'value_json': jsonEncode(data),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getProfileData(String key) async {
    final db = await database;
    final res =
        await db.query('user_profile', where: 'key = ?', whereArgs: [key]);
    if (res.isNotEmpty) {
      return jsonDecode(res.first['value_json'] as String);
    }
    return null;
  }

  // Settings
  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
        'settings',
        {
          'key': key,
          'value': value,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final res = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (res.isNotEmpty) {
      return res.first['value'] as String;
    }
    return null;
  }

  // Privacy Context
  void setIncognito(bool val) => _incognito = val;
  bool isIncognito() => _incognito;

  void setPauseWatchHistory(bool val) => _pauseWatchHistory = val;
  bool isPauseWatchHistory() => _pauseWatchHistory;

  void setPauseSearchHistory(bool val) => _pauseSearchHistory = val;
  bool isPauseSearchHistory() => _pauseSearchHistory;

  void setPausePersonalization(bool val) => _pausePersonalization = val;
  bool isPausePersonalization() => _pausePersonalization;

  // Diagnostics
  Future<Map<String, int>> getStorageBreakdown() async {
    final db = await database;
    final tables = [
      'watch_history',
      'watch_signals',
      'feed_impressions',
      'feed_state',
      'feedback',
      'search_history',
      'followed_channels',
      'local_playlists',
      'playlist_items',
      'watch_later',
      'liked_videos',
      'downloads',
      'video_intelligence',
      'user_profile',
      'settings'
    ];
    Map<String, int> breakdown = {};
    for (final table in tables) {
      final res = await db.rawQuery('SELECT COUNT(*) as count FROM $table');
      breakdown[table] = (res.first['count'] as int?) ?? 0;
    }
    return breakdown;
  }

  Future<void> clearAllData() async {
    final db = await database;
    final tables = [
      'watch_history',
      'watch_signals',
      'feed_impressions',
      'feed_state',
      'feedback',
      'search_history',
      'followed_channels',
      'local_playlists',
      'playlist_items',
      'watch_later',
      'liked_videos',
      'downloads',
      'video_intelligence',
      'user_profile',
      'settings'
    ];
    await db.transaction((txn) async {
      for (final table in tables) {
        await txn.delete(table);
      }
    });
    _incognito = _pauseWatchHistory =
        _pauseSearchHistory = _pausePersonalization = false;
  }
}
