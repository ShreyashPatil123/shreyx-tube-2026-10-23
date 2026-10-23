import 'dart:async';
import '../services/tube_session_service.dart';
import '../services/tube_innertube_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/tube_models.dart';
import '../models/tube_stream.dart';
import '../services/tube_database_service.dart';
import '../services/tube_home_feed_service.dart';
import '../services/tube_shorts_service.dart';
import '../services/tube_storage_service.dart';
import '../services/tube_stream_resolver.dart';
import '../services/tube_user_profile_service.dart';
import 'tube_player_provider.dart';

/// Dedicated controller for the vertical Shorts feed.
/// Features:
/// - Single active short playback enforcement (stops previous short immediately)
/// - Pauses main video player so only one audio/video stream ever plays
/// - Bounded N+1 prefetching
/// - Continuous pagination before reaching bottom
/// - Mute/unmute volume control
/// - Tap to play/pause with ripple HUD
/// - On-device fast-skip and completion behavioral tracking
class TubeShortsController extends ChangeNotifier {
  final TubeShortsService _shortsService = TubeShortsService();
  final TubeStreamResolver _resolver = TubeStreamResolver();
  final TubeStorageService _storage = TubeStorageService();

  static const MethodChannel _channel =
      MethodChannel('com.shreyx.tube/shorts_player_channel');

  List<TubeVideoItem> _shorts = [];
  int _activeIndex = 0;
  bool _isLoadingFeed = false;
  bool _isLoadingActiveShort = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isMuted = false;
  String? _errorMessage;
  int _feedPage = 0;
  bool _isFetchingMore = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Active watch metrics for local recommendation scoring
  DateTime? _activeShortStartTime;
  bool _isScreenActive = false;
  int _generation = 0;
  int _linkStartMs = 0;
  bool _channelFeed = false;
  int _watchedMs = 0;
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// Seed the real clicked channel Short before the route activates playback.
  void selectChannelShorts(List<TubeVideoItem> items, int index,
      {int startPositionMs = 0}) {
    deactivateScreen();
    _linkStartMs = startPositionMs;
    _shorts = List.of(items.where((v) => v.isShort));
    _activeIndex = index.clamp(0, _shorts.isEmpty ? 0 : _shorts.length - 1);
    _channelFeed = true;
    _isLoadingFeed = _isLoadingActiveShort = _isFetchingMore = false;
    _errorMessage = null;
    _position = _duration = Duration.zero;
    _watchedMs = 0;
    notifyListeners();
  }

  Future<void> _signalSave = Future.value();
  Future<void> resetLocalState() async {
    ++_generation;
    _linkStartMs = 0;
    _isScreenActive = false;
    _activeShortStartTime = null;
    await _channel.invokeMethod('stop');
    await _signalSave;
    _channelFeed = false;
    _watchedMs = 0;
    _shorts = [];
    _activeIndex = 0;
    _feedPage = 0;
    _errorMessage = null;
    _position = _duration = Duration.zero;
    _isPlaying = _isBuffering = _isLoadingFeed =
        _isLoadingActiveShort = _isFetchingMore = _isMuted = false;
    notifyListeners();
  }

  // Getters
  List<TubeVideoItem> get shorts => List.unmodifiable(_shorts);
  int get activeIndex => _activeIndex;
  TubeVideoItem? get activeShort =>
      _shorts.isNotEmpty && _activeIndex < _shorts.length
          ? _shorts[_activeIndex]
          : null;
  bool get isLoadingFeed => _isLoadingFeed;
  bool get isLoadingActiveShort => _isLoadingActiveShort;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  bool get isMuted => _isMuted;
  bool get isScreenActive => _isScreenActive;
  String? get errorMessage => _errorMessage;
  Duration get position => _position;
  Duration get duration => _duration;
  double get progressRatio => _duration.inMilliseconds > 0
      ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;

  TubeShortsController() {
    _feedIdentity = TubeInnertubeClient().requestIdentity;
    _initChannel();
    _storage.addListener(_privacyChanged);
    TubeSessionService().addListener(_accountChanged);
    // Do NOT load or play initial feed on construction.
    // Feed and playback are strictly initiated only when the Shorts screen becomes active.
  }

  void _privacyChanged() {
    _watchedMs = 0;
    _activeShortStartTime = _isScreenActive ? DateTime.now() : null;
    if (_feedIdentity != TubeInnertubeClient().requestIdentity) {
      _accountChanged();
    }
  }

  String? _feedIdentity;
  void _accountChanged() {
    _feedIdentity = TubeInnertubeClient().requestIdentity;
    final active = _isScreenActive;
    deactivateScreen();
    _shorts = [];
    _activeIndex = _feedPage = 0;
    _channelFeed = false;
    _isLoadingFeed = _isFetchingMore = _isLoadingActiveShort = false;
    _shortsService.reset();
    if (active) activateScreen();
    notifyListeners();
  }

  /// Explicitly called when user opens the Shorts tab
  void activateScreen({TubePlayerProvider? mainPlayerProvider}) {
    // Both the tab shell and screen lifecycle can announce the same activation.
    if (_isScreenActive) return;
    _isScreenActive = true;
    mainPlayerProvider?.pause();
    if (_shorts.isEmpty) {
      loadInitialFeed(autoPlay: true);
    } else if (!_isPlaying) {
      playShortAtIndex(_activeIndex);
    }
  }

  /// Explicitly called when user leaves the Shorts tab or app is backgrounded
  void deactivateScreen() {
    ++_generation;
    _isScreenActive = false;
    _recordPreviousShortMetrics();
    pause();
    _channel.invokeMethod('stop');
  }

  void _initChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPlaybackStateChanged':
          final args = call.arguments as Map<dynamic, dynamic>?;
          final state = args?['state']?.toString();
          if (state == 'BUFFERING') {
            _isBuffering = true;
          } else if (state == 'READY') {
            _isBuffering = false;
            _errorMessage = null;
          }
          notifyListeners();
          break;
        case 'onIsPlayingChanged':
          _isPlaying = call.arguments as bool? ?? false;
          notifyListeners();
          break;
        case 'onProgressUpdate':
          final data = call.arguments as Map<dynamic, dynamic>?;
          if (data != null && _isScreenActive) {
            final nextMs = (data['positionMs'] as num?)?.toInt() ?? 0;
            final delta = nextMs - _position.inMilliseconds;
            if (_isPlaying &&
                delta > 0 &&
                delta <= 2000 &&
                !_storage.isIncognito &&
                !_storage.pausePersonalization &&
                !_storage.pauseWatchHistory) {
              _watchedMs += delta;
            }
            _position = Duration(
                milliseconds: (data['positionMs'] as num?)?.toInt() ?? 0);
            final durMs = (data['durationMs'] as num?)?.toInt() ?? 0;
            if (durMs > 0) _duration = Duration(milliseconds: durMs);
            _isPlaying = data['isPlaying'] as bool? ?? false;
            _isBuffering = data['isBuffering'] as bool? ?? false;
            notifyListeners();
          }
          break;
        case 'onPlaybackError':
          final errMap = call.arguments as Map<dynamic, dynamic>?;
          _errorMessage =
              errMap?['message']?.toString() ?? 'Failed to play short';
          _isBuffering = false;
          _isLoadingActiveShort = false;
          notifyListeners();
          break;
      }
    });
  }

  Future<void> loadInitialFeed({bool autoPlay = false}) async {
    final generation = ++_generation;
    _channelFeed = false;
    _feedPage = 0;
    _isLoadingFeed = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final list = await _shortsService.getShortsFeed(page: 0);
      if (generation != _generation) return;
      _shorts = list;
      _isLoadingFeed = false;
      notifyListeners();

      if (_shorts.isNotEmpty && autoPlay && _isScreenActive) {
        // Start playing the first short only if screen is explicitly active
        await playShortAtIndex(0);
      }
    } catch (e) {
      if (generation != _generation) return;
      _errorMessage = 'Failed to load Shorts feed. Tap Retry.';
      _isLoadingFeed = false;
      notifyListeners();
    }
  }

  Future<void> fetchMoreShorts() async {
    if (_isFetchingMore || _channelFeed) return;
    final generation = _generation;
    _isFetchingMore = true;
    _feedPage++;

    try {
      final more = await _shortsService.getShortsFeed(page: _feedPage);
      if (generation != _generation) return;
      if (more.isNotEmpty) {
        // Filter duplicates
        final existingIds = _shorts.map((s) => s.id).toSet();
        final newItems =
            more.where((s) => !existingIds.contains(s.id)).toList();
        _shorts.addAll(newItems);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[TubeShortsController] Fetch more error: $e');
    } finally {
      if (generation == _generation) _isFetchingMore = false;
    }
  }

  /// Paging handler when user swipes up or down
  Future<void> onPageChanged(int newIndex,
      {TubePlayerProvider? mainPlayerProvider}) async {
    if (newIndex == _activeIndex && _isPlaying) return;
    if (newIndex != _activeIndex) _linkStartMs = 0;

    // 1. Record metrics for the previous short before leaving
    _recordPreviousShortMetrics();

    final generation = ++_generation;
    // 2. Stop previous short immediately
    await _channel.invokeMethod('stop');
    if (generation != _generation || !_isScreenActive) return;
    _watchedMs = 0;
    _isLoadingActiveShort = true;
    _activeIndex = newIndex;
    _errorMessage = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();

    // 3. Ensure main video player is paused so never two playbacks run
    mainPlayerProvider?.pause();

    // 4. Play the new active short
    await playShortAtIndex(newIndex);

    // 5. Trigger bounded N+1 prefetch
    if (newIndex + 1 < _shorts.length) {
      _shortsService.prefetchNextShort(_shorts[newIndex + 1]);
    }

    // 6. Paginate if approaching end (within 3 items)
    if (newIndex >= _shorts.length - 3) {
      fetchMoreShorts();
    }
  }

  Future<void> playShortAtIndex(int index,
      {TubePlayerProvider? mainPlayerProvider}) async {
    if (index < 0 || index >= _shorts.length) return;
    if (!_isScreenActive) {
      debugPrint(
          '[TubeShortsController] Ignored playShortAtIndex($index) - screen not active');
      return;
    }
    mainPlayerProvider?.pause();
    final generation = ++_generation;
    final short = _shorts[index];
    if (short.isMembersOnly && !TubeSessionService().usesPrivateFeed) {
      await _channel.invokeMethod('stop');
      _activeIndex = index;
      _isLoadingActiveShort = false;
      _isPlaying = false;
      _isBuffering = false;
      _activeShortStartTime = null;
      _errorMessage =
          'Members-only Short. Connect an eligible YouTube account or open it in YouTube.';
      notifyListeners();
      return;
    }
    _activeIndex = index;
    _isLoadingActiveShort = true;
    _errorMessage = null;
    _activeShortStartTime = DateTime.now();
    notifyListeners();

    try {
      // 1. Check if stream was already prefetched
      TubeResolvedVideo? resolved =
          _shortsService.getPrefetchedStream(short.id);
      resolved ??= await _resolver.resolve(short.id,
          requireAccount: short.isMembersOnly);

      // Re-verify index has not changed and screen is still active after async resolve
      if (_activeIndex != index || !_isScreenActive) {
        debugPrint(
            '[TubeShortsController] Aborted playback: index $index superseded by $_activeIndex');
        return;
      }

      final stream =
          resolved.getBestStream('720p') ?? resolved.getBestStream('360p');
      if (stream == null) {
        throw Exception('No playable video stream found for this Short.');
      }

      if (generation != _generation || !_isScreenActive) return;
      final params =
          stream.toMediaParams(autoPlay: true, startPositionMs: _linkStartMs);
      _linkStartMs = 0;

      _shorts[index] = short.copyWith(
        channelTitle: resolved.uploader,
        channelId: RegExp(r'/channel/(UC[\w-]+)')
                .firstMatch(resolved.uploaderUrl)
                ?.group(1) ??
            short.channelId,
        channelAvatarUrl: resolved.uploaderAvatarUrl.isNotEmpty
            ? resolved.uploaderAvatarUrl
            : short.channelAvatarUrl,
      );

      await _channel.invokeMethod('loadMedia', params);
      if (generation != _generation) return;
      _isLoadingActiveShort = false;
      notifyListeners();
    } catch (e) {
      if (generation != _generation) return;
      debugPrint('[TubeShortsController] Error resolving/playing short: $e');
      _errorMessage = e is TubeMembersOnlyException
          ? e.message
          : 'Could not load Short. Check your connection or tap to retry.';
      _isLoadingActiveShort = false;
      notifyListeners();
    }
  }

  void togglePlayPause({TubePlayerProvider? mainPlayerProvider}) {
    if (!_isScreenActive) {
      activateScreen(mainPlayerProvider: mainPlayerProvider);
      return;
    }
    if (_isPlaying) {
      pause();
    } else {
      play(mainPlayerProvider: mainPlayerProvider);
    }
  }

  void play({TubePlayerProvider? mainPlayerProvider}) {
    if (!_isScreenActive) return;
    mainPlayerProvider?.pause();
    _channel.invokeMethod('play');
    _isPlaying = true;
    notifyListeners();
  }

  void pause() {
    _channel.invokeMethod('pause');
    _isPlaying = false;
    notifyListeners();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    _channel.invokeMethod('setMuted', {'muted': _isMuted});
    notifyListeners();
  }

  void retryActiveShort() {
    if (_shorts.isNotEmpty) {
      playShortAtIndex(_activeIndex);
    } else {
      loadInitialFeed();
    }
  }

  void _recordPreviousShortMetrics() {
    if (activeShort == null || _activeShortStartTime == null) return;
    final watchDurationSec = _watchedMs ~/ 1000;
    _watchedMs = 0;
    _activeShortStartTime = null;
    final durSec = _duration.inSeconds > 0 ? _duration.inSeconds : 45;
    final ratio = (watchDurationSec / durSec).clamp(0.0, 1.0);
    final isFastSkip = watchDurationSec < 3 && ratio < 0.15;

    final signal = TubeWatchSignal(
      videoId: activeShort!.id,
      title: activeShort!.title,
      channelId: activeShort!.channelId,
      channelTitle: activeShort!.channelTitle,
      completionRatio: ratio,
      watchDurationSeconds: watchDurationSec,
      isFastSkip: isFastSkip,
      timestamp: DateTime.now(),
    );

    _signalSave = _signalSave.then((_) async {
      await _storage.recordWatchSignal(signal);
      await TubeUserProfileService().updateFromWatchSignal(signal);
      if (TubeDatabaseService().isInitialized) {
        await TubeDatabaseService().insertWatchSignal({
          'video_id': signal.videoId,
          'channel_id': signal.channelId,
          'topics': '[]',
          'completion_ratio': ratio,
          'watch_duration_ms': watchDurationSec * 1000,
          'is_fast_skip': isFastSkip ? 1 : 0,
          'created_at': signal.timestamp.millisecondsSinceEpoch,
        });
      }
    }).catchError((Object e) {
      debugPrint('Could not save Shorts signal: $e');
    });
    TubeHomeFeedService().invalidateRecommendedFeed();
  }

  @override
  void dispose() {
    TubeSessionService().removeListener(_accountChanged);
    _storage.removeListener(_privacyChanged);
    _recordPreviousShortMetrics();
    ++_generation;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    _channel.invokeMethod('stop');
    super.dispose();
  }
}
