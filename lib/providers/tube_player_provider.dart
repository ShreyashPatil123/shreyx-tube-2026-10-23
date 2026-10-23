import 'dart:async';
import '../services/tube_session_service.dart';
import '../services/tube_innertube_client.dart';
import '../services/tube_buffer_recovery.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/tube_models.dart';
import '../models/tube_stream.dart';
import '../services/tube_home_feed_service.dart';
import '../services/tube_player_service.dart';
import '../services/tube_storage_service.dart';
import '../services/tube_stream_resolver.dart';
import '../services/tube_subtitle_service.dart';
import '../services/tube_user_profile_service.dart';
import '../services/tube_database_service.dart';

/// Central state provider for normal video playback, queue management, subtitles,
/// position preservation, mini-player visibility, and local engagement actions.
class TubePlayerProvider extends ChangeNotifier {
  final TubeStreamResolver _resolver;
  final VoidCallback? onNormalPlayback;
  final TubePlayerService _playerService = TubePlayerService();
  final TubeSubtitleService _subtitleService = TubeSubtitleService();
  final TubeHomeFeedService _homeFeedService;
  final DateTime Function() _clock;
  final TubeStorageService _storageService = TubeStorageService();
  // Active Playback State & 10-State Lifecycle
  TubePlayerStatus _status = TubePlayerStatus.idle;
  TubeVideoItem? _currentVideoItem;
  TubeResolvedVideo? _resolvedVideo;
  TubeVideoStream? _currentStream;
  String _selectedQuality = 'Auto';
  String? _errorMessage;
  int _playGeneration = 0;
  bool _disposed = false;
  bool _acceptPlayerEvents = false;
  bool get isLive =>
      _resolvedVideo?.isLive == true || _currentVideoItem?.isLive == true;
  bool _memberAccessDenied = false;
  String? _authorizedIdentity;
  bool get isMembersOnly => _memberAccessDenied;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  final _bufferRecovery = TubeBufferRecovery();
  int _autoMaxHeight = 720;
  bool _adapting = false, _playRequested = false;
  double _aspectRatio = 16 / 9;
  // Stream Failure Recovery
  int _retryAttempts = 0;
  static const int _maxRetries = 2;
  String _lastRawInput = '';
  // Subtitles / Captions
  TubeSubtitle? _currentSubtitle;
  String? _activeCaptionText;
  // Mini-player & Shell Visibility
  bool _isPlayerVisible = false;
  bool _isExpanded = false;
  bool _isFullscreen = false;
  bool isInPip = false;
  double _videoZoom = 1;
  double get videoZoom => _videoZoom;
  void setVideoZoom(double zoom) {
    _videoZoom = zoom.clamp(1.0, 3.0);
    notifyListeners();
  }

  void setBrightness(double value) => _playerService.setBrightness(value);
  void setVolume(double value) => _playerService.setVolume(value);
  int _watchedMs = 0;
  Duration? _lastProgress;
  bool _wasRewatch = false;
  Future<void> _signalSave = Future.value();
  // Queue & Related Content
  final List<TubeVideoItem> _queue = [];
  int _currentQueueIndex = -1;
  bool _autoPlayNext = true;
  List<TubeVideoItem> _relatedVideos = [];
  bool _isLoadingRelated = false;
  // Throttled History Position Saving & Metrics
  DateTime _lastPositionSaveTime = DateTime.now();
  DateTime? _videoStartTime;
  // Telemetry logs (for on-screen debugging & stream inspection)
  final List<String> _telemetryLogs = [];
  final List<StreamSubscription> _subscriptions = [];
  // Getters
  TubePlayerStatus get status => _status;
  TubeVideoItem? get currentVideoItem => _currentVideoItem;
  TubeResolvedVideo? get resolvedVideo => _resolvedVideo;
  TubeVideoStream? get currentStream => _currentStream;
  String get selectedQuality => _selectedQuality;
  String? get errorMessage => _errorMessage;
  Duration get position => _position;
  Duration get duration => _duration;
  Duration get buffered => _buffered;
  double get aspectRatio => _aspectRatio;
  // Convenience state getters
  bool get isLoading =>
      _status == TubePlayerStatus.loadingMetadata ||
      _status == TubePlayerStatus.resolvingStream ||
      _status == TubePlayerStatus.preparingPlayer;
  bool get isBuffering => _status == TubePlayerStatus.buffering;
  bool get isPlaying => _status == TubePlayerStatus.playing;
  bool get isPaused => _status == TubePlayerStatus.paused;
  bool get isRetrying => _status == TubePlayerStatus.retrying;
  TubeSubtitle? get currentSubtitle => _currentSubtitle;
  String? get activeCaptionText => _activeCaptionText;
  bool get isPlayerVisible => _isPlayerVisible;
  bool get isExpanded => _isExpanded;
  bool get isFullscreen => _isFullscreen;
  List<TubeVideoItem> get queue => List.unmodifiable(_queue);
  int get currentQueueIndex => _currentQueueIndex;
  bool get autoPlayNext => _autoPlayNext;
  List<TubeVideoItem> get relatedVideos => List.unmodifiable(_relatedVideos);
  bool get isLoadingRelated => _isLoadingRelated;
  List<String> get telemetryLogs => List.unmodifiable(_telemetryLogs);
  // Local Actions
  bool get isLikedLocally =>
      _currentVideoItem != null &&
      _storageService.isLikedLocally(_currentVideoItem!.id);
  bool get isInWatchLater =>
      _currentVideoItem != null &&
      _storageService.isInWatchLater(_currentVideoItem!.id);
  bool get isChannelFollowed =>
      _currentVideoItem != null &&
      _storageService.isChannelFollowed(_currentVideoItem!.channelId);
  TubePlayerProvider(
      {this.onNormalPlayback,
      TubeStreamResolver? resolver,
      TubeHomeFeedService? homeFeedService,
      DateTime Function()? clock})
      : _resolver = resolver ?? TubeStreamResolver(),
        _clock = clock ?? DateTime.now,
        _homeFeedService = homeFeedService ?? TubeHomeFeedService() {
    _initSubscriptions();
    _recommendationIdentity = _homeFeedService.requestIdentity;
    _storageService.addListener(_privacyChanged);
    TubeSessionService().addListener(_accountChanged);
  }
  Future<void> restoreNativePlayback() async {
    final generation = _playGeneration;
    try {
      final status = await _playerService.getStatus();
      if (_disposed ||
          generation != _playGeneration ||
          _isPlayerVisible ||
          status['hasMedia'] != true) {
        return;
      }
      if (status['requiresAccount'] == true) {
        await TubeSessionService().init();
        if (_disposed || generation != _playGeneration || _isPlayerVisible) {
          return;
        }
        if (!TubeSessionService().usesPrivateFeed) {
          await _playerService.stop();
          return;
        }
        _authorizedIdentity = TubeInnertubeClient().requestIdentity;
      }
      _currentVideoItem = TubeVideoItem(
          channelId: '',
          id: status['videoId'] as String? ?? '',
          title: status['title'] as String? ?? 'Playing video',
          channelTitle: status['channelTitle'] as String? ?? '',
          thumbnailUrl: status['thumbnailUrl'] as String? ?? '',
          isMembersOnly: status['requiresAccount'] == true,
          isLive: status['isLive'] == true);
      _position =
          Duration(milliseconds: (status['positionMs'] as num?)?.toInt() ?? 0);
      _duration =
          Duration(milliseconds: (status['durationMs'] as num?)?.toInt() ?? 0);
      final width = (status['videoWidth'] as num?)?.toDouble() ?? 0;
      final height = (status['videoHeight'] as num?)?.toDouble() ?? 0;
      if (width > 0 && height > 0) _aspectRatio = width / height;
      _status = status['isPlaying'] == true
          ? TubePlayerStatus.playing
          : TubePlayerStatus.paused;
      _isPlayerVisible = true;
      _isExpanded = false;
      _acceptPlayerEvents = true;
      _videoStartTime = DateTime.now();
      _watchedMs = 0;
      _lastProgress = null;
      notifyListeners();
    } catch (_) {/* No native session on non-Android/test hosts. */}
  }

  Future<void> flushSignals() => _signalSave;
  Future<void> resetLocalState() async {
    _videoStartTime = null;
    _watchedMs = 0;
    _lastProgress = null;
    final stopping = closePlayer(strict: true);
    clearQueue();
    _relatedVideos = [];
    _telemetryLogs.clear();
    _subtitleService.clearTrack();
    _currentSubtitle = null;
    _activeCaptionText = null;
    _position = _duration = _buffered = Duration.zero;
    _errorMessage = null;
    _lastRawInput = '';
    _selectedQuality = 'Auto';
    _autoPlayNext = true;
    notifyListeners();
    await stopping;
  }

  void _privacyChanged() {
    _watchedMs = 0;
    _lastProgress = null;
    _videoStartTime = _currentVideoItem == null ? null : DateTime.now();
    if (_recommendationIdentity != _homeFeedService.requestIdentity) {
      _accountChanged();
    }
  }

  String? _recommendationIdentity;
  void _accountChanged() {
    if (_authorizedIdentity != null &&
        _authorizedIdentity != TubeInnertubeClient().requestIdentity) {
      ++_playGeneration;
      _acceptPlayerEvents = false;
      _memberAccessDenied = true;
      _resolvedVideo = null;
      _currentStream = null;
      _authorizedIdentity = null;
      _status = TubePlayerStatus.paused;
      _errorMessage =
          'The connected account changed. Retry with an eligible account or open in YouTube.';
      unawaited(_playerService.stop());
    }
    _recommendationIdentity = _homeFeedService.requestIdentity;
    _relatedVideos = [];
    final video = _currentVideoItem;
    if (video != null) {
      unawaited(_loadRelatedVideos(video));
    } else {
      notifyListeners();
    }
  }

  void _log(String msg) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final logLine = '[$timestamp] $msg';
    _telemetryLogs.insert(0, logLine);
    if (_telemetryLogs.length > 50) _telemetryLogs.removeLast();
    debugPrint('[TubePlayerProvider] $msg');
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _initSubscriptions() {
    _subscriptions.add(_playerService.pipStream.listen((value) {
      isInPip = value;
      notifyListeners();
    }));
    _subscriptions.add(_playerService.progressStream.listen((prog) {
      if (isMembersOnly || !_acceptPlayerEvents) return;
      if (_lastProgress != null &&
          prog.isPlaying &&
          !_storageService.isIncognito &&
          !_storageService.pauseWatchHistory &&
          !_storageService.pausePersonalization) {
        final delta =
            prog.position.inMilliseconds - _lastProgress!.inMilliseconds;
        if (delta > 0 && delta <= 2000) _watchedMs += delta;
      }
      _lastProgress = prog.position;
      _position = prog.position;
      if (prog.duration > Duration.zero) {
        _duration = prog.duration;
      }
      _buffered = prog.buffered;
      if (prog.isBuffering) {
        _status = TubePlayerStatus.buffering;
        _recoverBuffering();
      } else if (prog.isPlaying) {
        _status = TubePlayerStatus.playing;
        _bufferRecovery.playing();
      }
      // Update subtitle cue if active
      if (_subtitleService.hasActiveTrack) {
        final cue = _subtitleService.getActiveCueText(_position);
        if (cue != _activeCaptionText) {
          _activeCaptionText = cue;
        }
      }
      // Throttled local history saving (every 5 seconds)
      final now = DateTime.now();
      if (_currentVideoItem != null &&
          now.difference(_lastPositionSaveTime).inSeconds >= 5) {
        _lastPositionSaveTime = now;
        _storageService.saveWatchPosition(
          _currentVideoItem!,
          _position.inMilliseconds,
          _duration.inMilliseconds,
        );
      }
      notifyListeners();
    }));
    _subscriptions.add(_playerService.isPlayingStream.listen((playing) {
      if (isMembersOnly || !_acceptPlayerEvents) return;
      if (playing) {
        _status = TubePlayerStatus.playing;
      } else if (_status != TubePlayerStatus.completed &&
          _status != TubePlayerStatus.error &&
          _status != TubePlayerStatus.retrying &&
          !isLoading) {
        _status = TubePlayerStatus.paused;
      }
      notifyListeners();
    }));
    _subscriptions.add(_playerService.stateStream.listen((state) {
      if (isMembersOnly || !_acceptPlayerEvents) return;
      _log('Player state: $state');
      if (state == 'BUFFERING') {
        _status = TubePlayerStatus.buffering;
        _recoverBuffering();
      } else if (state == 'READY') {
        _status =
            isPlaying ? TubePlayerStatus.playing : TubePlayerStatus.paused;
        _retryAttempts = 0;
      } else if (state == 'ENDED') {
        _status = TubePlayerStatus.completed;
        _handlePlaybackEnded();
      }
      notifyListeners();
    }));
    _subscriptions.add(_playerService.videoSizeStream.listen((map) {
      final width = (map['width'] as num?)?.toDouble() ?? 16.0;
      final height = (map['height'] as num?)?.toDouble() ?? 9.0;
      if (width > 0 && height > 0) {
        _aspectRatio = width / height;
        _log(
            'Video size updated: ${width.toInt()}x${height.toInt()} (aspect: ${_aspectRatio.toStringAsFixed(2)})');
        notifyListeners();
      }
    }));
    // Stream failure & automatic position-preserving recovery
    _subscriptions.add(_playerService.errorStream.listen((errMap) {
      if (isMembersOnly || !_acceptPlayerEvents) return;
      final isHttp = errMap['isHttpError'] == true;
      final httpCode = (errMap['httpCode'] as num?)?.toInt() ?? -1;
      final lastPosMs = (errMap['lastPositionMs'] as num?)?.toInt() ??
          _position.inMilliseconds;
      final msg = errMap['message']?.toString() ?? 'Playback error';
      _log(
          'Media3 error: $msg (http: $isHttp, code: $httpCode, pos: ${lastPosMs}ms)');
      if ((isHttp || httpCode == 403 || httpCode == 410 || httpCode == 404) &&
          _retryAttempts < _maxRetries) {
        _retryAttempts++;
        _status = TubePlayerStatus.retrying;
        _log(
            '🔄 Stream token expired. Auto-recovering (attempt $_retryAttempts/$_maxRetries) from ${lastPosMs}ms...');
        notifyListeners();
        _reResolveAndResume(Duration(milliseconds: lastPosMs));
      } else {
        _status = TubePlayerStatus.error;
        _errorMessage = 'Playback error ($msg). Tap Retry.';
        notifyListeners();
      }
    }));
  }

  // =========================================================================
  // PLAYBACK INITIATION (Instant Tap UX)
  // =========================================================================
  /// Plays a video item directly from Home, Search, History, or Queue.
  /// Instantly opens the Watch screen and displays the poster HUD without blocking on stream extraction.
  Future<void> playVideo(TubeVideoItem video,
      {int? startPositionMs, bool expand = true}) async {
    onNormalPlayback?.call();
    // Central Player Ownership: Stop Shorts player immediately so only one player runs
    const MethodChannel('com.shreyx.tube/shorts_player_channel')
        .invokeMethod('stop')
        .catchError((_) {});
    // 1. Record metrics for outgoing video if any
    _recordCurrentWatchSignal();
    _acceptPlayerEvents = false;
    unawaited(_playerService.stop());
    _position = Duration.zero;
    _duration = Duration(seconds: video.durationSeconds);
    _buffered = Duration.zero;
    _aspectRatio = 16 / 9;
    _relatedVideos = [];
    _currentSubtitle = null;
    _activeCaptionText = null;
    _retryAttempts = 0;
    // 2. SYNCHRONOUS: Instantly update state so Watch Screen opens immediately
    _currentVideoItem = video;
    _resolvedVideo = null;
    _currentStream = null;
    _memberAccessDenied = false;
    _authorizedIdentity = null;
    _autoMaxHeight = 720;
    _bufferRecovery.reset();
    _errorMessage = null;
    _status = TubePlayerStatus.loadingMetadata;
    _isPlayerVisible = true;
    if (expand) _isExpanded = true;
    _videoStartTime = DateTime.now();
    _watchedMs = 0;
    _lastProgress = null;
    _wasRewatch = _currentVideoItem != null &&
        _storageService.getHistoryItem(_currentVideoItem!.id) != null;
    if (video.isMembersOnly && !TubeSessionService().usesPrivateFeed) {
      _memberAccessDenied = true;
      ++_playGeneration;
      _status = TubePlayerStatus.paused;
      _videoStartTime = null;
      _position = Duration.zero;
      _duration = Duration(seconds: video.durationSeconds);
      _subtitleService.clearTrack();
      _activeCaptionText = null;
      notifyListeners();
      await _playerService.pause();
      return;
    }
    notifyListeners();
    // Check for saved resume position if none explicitly passed
    int resumeMs = startPositionMs ?? 0;
    if (startPositionMs == null) {
      final history = _storageService.getHistoryItem(video.id);
      if (history != null && history.isResumeAvailable) {
        resumeMs = history.positionMs;
        _log(
            'Resuming "${video.title}" from ${history.formattedResumePosition}');
      }
    }
    // 3. Asynchronously resolve stream in the background
    // Recommendations load independently of extraction and the first frame.
    _loadRelatedVideos(video);
    await resolveAndPlay(video.id,
        startPositionMs: video.isLive ? 0 : resumeMs);
  }

  /// Plays a locally downloaded video without network extraction.
  Future<void> playOfflineVideo(
      TubeVideoItem video, TubeVideoStream stream) async {
    onNormalPlayback?.call();
    final generation = ++_playGeneration;
    const MethodChannel('com.shreyx.tube/shorts_player_channel')
        .invokeMethod('stop')
        .catchError((_) {});
    _recordCurrentWatchSignal();
    _currentVideoItem = video;
    _resolvedVideo = null;
    _currentStream = stream;
    _memberAccessDenied = false;
    _authorizedIdentity = null;
    _errorMessage = null;
    _status = TubePlayerStatus.loadingMetadata;
    _isPlayerVisible = true;
    _isExpanded = true;
    _videoStartTime = DateTime.now();
    _watchedMs = 0;
    _lastProgress = null;
    _wasRewatch = _currentVideoItem != null &&
        _storageService.getHistoryItem(_currentVideoItem!.id) != null;
    notifyListeners();
    await _applyStream(stream, autoPlay: true);
    if (generation != _playGeneration) return;
    _status = TubePlayerStatus.playing;
    notifyListeners();
  }

  /// Resolves and plays arbitrary YouTube URL or 11-char ID.
  Future<void> resolveAndPlay(String rawUrlOrId,
      {String? targetQuality, int startPositionMs = 0}) async {
    final generation = ++_playGeneration;
    _acceptPlayerEvents = false;
    final requestedId = _resolver.extractVideoId(rawUrlOrId);
    if (isMembersOnly &&
        _currentVideoItem?.id == requestedId &&
        !TubeSessionService().usesPrivateFeed) {
      return;
    }
    _memberAccessDenied = false;
    _lastRawInput = rawUrlOrId;
    _status = TubePlayerStatus.resolvingStream;
    _errorMessage = null;
    notifyListeners();
    try {
      _log('Resolving YouTube video: $rawUrlOrId');
      final resolved = await _resolver.resolve(rawUrlOrId,
          requireAccount: _currentVideoItem?.id == requestedId &&
              _currentVideoItem?.isMembersOnly == true);
      if (generation != _playGeneration) return;
      if (_disposed) return;
      _resolvedVideo = resolved;
      _authorizedIdentity = resolved.extractorSource == 'youtube_account'
          ? TubeInnertubeClient().requestIdentity
          : null;
      _duration = Duration(seconds: resolved.durationSeconds);
      _log('Extraction OK: "${resolved.title}" by ${resolved.uploader}');
      final openedFromUrl = _currentVideoItem == null ||
          _currentVideoItem!.id != resolved.videoId;
      if (openedFromUrl) {
        _currentVideoItem = TubeVideoItem(
          id: resolved.videoId,
          title: resolved.title,
          channelTitle: resolved.uploader,
          channelId: '',
          thumbnailUrl: resolved.thumbnailUrl,
          durationSeconds: resolved.durationSeconds,
          isLive: resolved.isLive,
        );
      }
      _currentVideoItem = _currentVideoItem!.copyWith(
        isMembersOnly: _currentVideoItem!.isMembersOnly ||
            resolved.extractorSource == 'youtube_account',
        channelTitle: resolved.uploader,
        channelId: RegExp(r'/channel/(UC[\w-]+)')
                .firstMatch(resolved.uploaderUrl)
                ?.group(1) ??
            _currentVideoItem!.channelId,
        channelAvatarUrl: resolved.uploaderAvatarUrl.isNotEmpty
            ? resolved.uploaderAvatarUrl
            : _currentVideoItem!.channelAvatarUrl,
        isLive: resolved.isLive,
      );
      _isPlayerVisible = true;
      _isExpanded = true;
      if (openedFromUrl) _loadRelatedVideos(_currentVideoItem!);
      final qualityToUse = targetQuality ?? _selectedQuality;
      final stream =
          resolved.getBestStream(qualityToUse, maxAutoHeight: _autoMaxHeight);
      if (stream == null) {
        throw Exception('No playable video stream found.');
      }
      // Reset subtitles for new video
      _subtitleService.clearTrack();
      _currentSubtitle = null;
      _activeCaptionText = null;
      _status = TubePlayerStatus.preparingPlayer;
      notifyListeners();
      await _applyStream(stream,
          startPosition: Duration(milliseconds: startPositionMs));
    } catch (e) {
      if (generation != _playGeneration) return;
      if (e is TubeMembersOnlyException) {
        final existing = _currentVideoItem;
        _currentVideoItem = existing?.id == requestedId
            ? existing!.copyWith(isMembersOnly: true)
            : TubeVideoItem(
                id: requestedId,
                title: 'Members-only video',
                channelTitle: '',
                channelId: '',
                isMembersOnly: true,
                thumbnailUrl:
                    'https://i.ytimg.com/vi/$requestedId/hqdefault.jpg');
        _memberAccessDenied = true;
        _authorizedIdentity = null;
        _resolvedVideo = null;
        _currentStream = null;
        _acceptPlayerEvents = false;
        _status = TubePlayerStatus.paused;
        _errorMessage = e.message;
        _videoStartTime = null;
        notifyListeners();
        await _playerService.stop();
        return;
      }
      _status = TubePlayerStatus.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _log('Resolution error: $_errorMessage');
      notifyListeners();
    }
  }

  Future<void> _applyStream(TubeVideoStream stream,
      {Duration startPosition = Duration.zero, bool autoPlay = true}) async {
    // Central Player Ownership: Ensure Shorts is stopped
    const MethodChannel('com.shreyx.tube/shorts_player_channel')
        .invokeMethod('stop')
        .catchError((_) {});
    _playRequested = autoPlay;
    _bufferRecovery.seeking(_clock());
    _currentStream = stream;
    _acceptPlayerEvents = true;
    _log(
        'Applying stream: ${stream.resolution} (${stream.container}/${stream.codec}, ${stream.deliveryMethod})');
    final success = await _playerService.loadStream(
      stream,
      videoId: _currentVideoItem?.id,
      thumbnailUrl: _currentVideoItem?.thumbnailUrl,
      startPositionMs: startPosition.inMilliseconds,
      autoPlay: autoPlay,
      title: _currentVideoItem?.title,
      channelTitle: _currentVideoItem?.channelTitle,
      requiresAccount: _authorizedIdentity != null,
    );
    if (!success) {
      _status = TubePlayerStatus.error;
      _errorMessage = 'Failed to load media into native Media3 player.';
      _log(_errorMessage!);
      notifyListeners();
    }
  }

  // =========================================================================
  // DYNAMIC QUALITY SWITCHING (Preserving Position & Playing State)
  // =========================================================================
  void _recoverBuffering() {
    final current = _currentStream;
    if (_adapting ||
        !_playRequested ||
        _selectedQuality != 'Auto' ||
        isLive ||
        current == null ||
        _resolvedVideo == null ||
        current.deliveryMethod == 'HLS' ||
        current.deliveryMethod == 'DASH_MPD') {
      return;
    }
    if (!_bufferRecovery.buffering(_clock(), ahead: _buffered - _position)) {
      return;
    }
    final next = _resolvedVideo!.lowerStream(current);
    if (next == null) return;
    final generation = _playGeneration;
    final resume = _position;
    _adapting = true;
    _autoMaxHeight = next.height;
    _log(
        'Auto quality adapting ${current.resolution} → ${next.resolution} after buffer starvation; preserving ${resume.inMilliseconds}ms');
    unawaited(() async {
      try {
        if (generation == _playGeneration && _playRequested && !_disposed) {
          await _applyStream(next, startPosition: resume, autoPlay: true);
        }
      } finally {
        _adapting = false;
        if (generation == _playGeneration && !_disposed) notifyListeners();
      }
    }());
  }

  Future<void> changeQuality(String qualityLabel) async {
    _selectedQuality = qualityLabel;
    if (_resolvedVideo == null) return;
    if (qualityLabel == 'Auto') _autoMaxHeight = 720;
    final targetStream = _resolvedVideo!
        .getBestStream(qualityLabel, maxAutoHeight: _autoMaxHeight);
    if (targetStream != null && targetStream != _currentStream) {
      final currentPos = _position;
      final wasPlaying = isPlaying;
      _log(
          'Switching quality to $qualityLabel (preserving position ${currentPos.inSeconds}s, autoPlay: $wasPlaying)');
      await _applyStream(targetStream,
          startPosition: currentPos, autoPlay: wasPlaying);
    }
    notifyListeners();
  }

  // =========================================================================
  // STREAM FAILURE RECOVERY & RETRY
  // =========================================================================
  Future<void> _reResolveAndResume(Duration resumePosition) async {
    if (_lastRawInput.isEmpty || isMembersOnly) return;
    final generation = _playGeneration;
    try {
      _log('Re-extracting fresh stream tokens for $_lastRawInput...');
      final resolved = await _resolver.resolve(_lastRawInput,
          forceRefresh: true,
          requireAccount: _currentVideoItem?.isMembersOnly == true);
      if (generation != _playGeneration || isMembersOnly) return;
      _resolvedVideo = resolved;
      final stream = resolved.getBestStream(_selectedQuality,
          maxAutoHeight: _autoMaxHeight);
      if (stream != null) {
        await _applyStream(stream,
            startPosition: resumePosition, autoPlay: true);
      }
    } catch (e) {
      if (generation != _playGeneration || isMembersOnly) return;
      _status = TubePlayerStatus.error;
      _errorMessage = 'Stream auto-recovery failed. Tap Retry.';
      _log('Auto-recovery exception: $e');
      notifyListeners();
    }
  }

  void retry() {
    _retryAttempts = 0;
    if (_currentVideoItem != null) {
      _resolver.invalidateCache(_currentVideoItem!.id);
    }
    if (_currentVideoItem != null) {
      resolveAndPlay(_currentVideoItem!.id,
          startPositionMs: _position.inMilliseconds);
    } else if (_lastRawInput.isNotEmpty) {
      resolveAndPlay(_lastRawInput);
    }
  }

  // =========================================================================
  // PLAYBACK CONTROLS
  // =========================================================================
  void play() {
    _playRequested = !isMembersOnly;
    onNormalPlayback?.call();
    const MethodChannel('com.shreyx.tube/shorts_player_channel')
        .invokeMethod('stop')
        .catchError((_) {});
    if (!isMembersOnly) _playerService.play();
  }

  void pause() {
    _playRequested = false;
    _bufferRecovery.seeking(_clock());
    _playerService.pause();
  }

  void togglePlayPause() {
    if (isPlaying) {
      pause();
    } else {
      play();
    }
  }

  void seekTo(Duration position) {
    _bufferRecovery.seeking(_clock());
    _playerService.seekTo(position);
  }

  void seek(Duration position) => seekTo(position);
  void goLive() => _playerService.seekToLive();
  void seekRelative(int seconds) {
    final newSecs =
        (_position.inSeconds + seconds).clamp(0, _duration.inSeconds);
    seekTo(Duration(seconds: newSecs));
  }

  void setSpeed(double speed) {
    _playerService.setSpeed(speed);
  }

  void enterPip() {
    _playerService.enterPip();
  }

  // =========================================================================
  // SUBTITLES / CAPTIONS
  // =========================================================================
  Future<void> toggleSubtitle(TubeSubtitle? sub) async {
    if (sub == null || sub == _currentSubtitle) {
      _subtitleService.clearTrack();
      _currentSubtitle = null;
      _activeCaptionText = null;
    } else {
      _currentSubtitle = sub;
      await _subtitleService.loadSubtitleTrack(sub);
    }
    notifyListeners();
  }

  Future<void> setSubtitleTrack(TubeSubtitle? sub) async {
    await toggleSubtitle(sub);
  }

  // =========================================================================
  // MINI-PLAYER & SHELL VISIBILITY
  // =========================================================================
  void expandPlayer() {
    _isExpanded = true;
    notifyListeners();
  }

  void exitFullscreen() {
    if (_isFullscreen) {
      _isFullscreen = false;
      _videoZoom = 1;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      notifyListeners();
    }
  }

  void collapsePlayer() {
    exitFullscreen();
    _isExpanded = false;
    notifyListeners();
  }

  void dismissPlayer() => closePlayer();
  void toggleFullscreen() {
    _isFullscreen = !_isFullscreen;
    _videoZoom = 1;
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    notifyListeners();
  }

  Future<void> closePlayer({bool strict = false}) async {
    ++_playGeneration;
    _playRequested = false;
    _bufferRecovery.reset();
    _acceptPlayerEvents = false;
    _recordCurrentWatchSignal();
    final stopping = _playerService.stop(strict: strict);
    exitFullscreen();
    _isPlayerVisible = false;
    _isExpanded = false;
    _currentVideoItem = null;
    _resolvedVideo = null;
    _currentStream = null;
    _status = TubePlayerStatus.idle;
    notifyListeners();
    await stopping;
  }

  // =========================================================================
  // QUEUE & RELATED CONTENT
  // =========================================================================
  Future<void> _loadRelatedVideos(TubeVideoItem video) async {
    final identity = _homeFeedService.requestIdentity;
    _recommendationIdentity = identity;
    _isLoadingRelated = true;
    notifyListeners();
    try {
      final related = await _homeFeedService.getRelatedVideos(video);
      if (_currentVideoItem?.id == video.id &&
          !_disposed &&
          identity == _homeFeedService.requestIdentity) {
        _relatedVideos = related;
      }
    } catch (e) {
      _log('Error loading related: $e');
    } finally {
      if (_currentVideoItem?.id == video.id &&
          identity == _homeFeedService.requestIdentity) {
        _isLoadingRelated = false;
      }
      notifyListeners();
    }
  }

  void addToQueue(TubeVideoItem item) {
    _queue.add(item);
    notifyListeners();
  }

  void playNextInQueue(TubeVideoItem item) {
    if (_currentQueueIndex + 1 < _queue.length) {
      _queue.insert(_currentQueueIndex + 1, item);
    } else {
      _queue.add(item);
    }
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
      if (index < _currentQueueIndex) {
        _currentQueueIndex--;
      } else if (_currentQueueIndex >= _queue.length) {
        _currentQueueIndex = _queue.length - 1;
      }
      notifyListeners();
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _queue.length ||
        newIndex < 0 ||
        newIndex > _queue.length) {
      return;
    }
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    notifyListeners();
  }

  void clearQueue() {
    _queue.clear();
    _currentQueueIndex = -1;
    notifyListeners();
  }

  void toggleAutoPlayNext() {
    _autoPlayNext = !_autoPlayNext;
    notifyListeners();
  }

  void _handlePlaybackEnded() {
    _recordCurrentWatchSignal();
    if (_queue.isNotEmpty && _currentQueueIndex + 1 < _queue.length) {
      _currentQueueIndex++;
      final next = _queue[_currentQueueIndex];
      _log('Queue Auto-Advance: playing "${next.title}"');
      playVideo(next);
      return;
    }
    if (_autoPlayNext && _relatedVideos.isNotEmpty) {
      final next = _relatedVideos.first;
      _log('Up Next Auto-Advance: playing "${next.title}"');
      playVideo(next);
    }
  }

  void _recordCurrentWatchSignal() {
    if (_currentVideoItem == null || isMembersOnly || _videoStartTime == null) {
      return;
    }
    final watchSecs = _watchedMs ~/ 1000;
    _videoStartTime =
        null; // Exactly one signal per session, never count paused/loading wall time.
    final durSecs = _duration.inSeconds > 0
        ? _duration.inSeconds
        : _currentVideoItem!.durationSeconds;
    final ratio = durSecs > 0 ? (watchSecs / durSecs).clamp(0.0, 1.0) : 0.0;
    final isFastSkip = watchSecs < 15 && ratio < 0.15;
    final signal = TubeWatchSignal(
      videoId: _currentVideoItem!.id,
      title: _currentVideoItem!.title,
      channelId: _currentVideoItem!.channelId,
      channelTitle: _currentVideoItem!.channelTitle,
      completionRatio: ratio,
      watchDurationSeconds: watchSecs,
      isRewatch: _wasRewatch,
      isFastSkip: isFastSkip,
      timestamp: DateTime.now(),
    );
    _signalSave = _signalSave.then((_) async {
      await _storageService.recordWatchSignal(signal);
      await TubeUserProfileService().updateFromWatchSignal(signal);
      if (TubeDatabaseService().isInitialized) {
        await TubeDatabaseService().insertWatchSignal({
          'video_id': signal.videoId,
          'channel_id': signal.channelId,
          'topics': '[]',
          'completion_ratio': signal.completionRatio,
          'watch_duration_ms': signal.watchDurationSeconds * 1000,
          'is_rewatch': signal.isRewatch ? 1 : 0,
          'is_fast_skip': signal.isFastSkip ? 1 : 0,
          'created_at': signal.timestamp.millisecondsSinceEpoch,
        });
      }
    }).catchError((Object e) {
      _log('Could not save watch signal: $e');
    });
    _homeFeedService.invalidateRecommendedFeed();
  }

  // =========================================================================
  // LOCAL ENGAGEMENT ACTIONS
  // =========================================================================
  Future<void> toggleLocalLike() async {
    if (_currentVideoItem == null) return;
    await _storageService.toggleLocalLike(_currentVideoItem!);
    notifyListeners();
  }

  Future<void> toggleWatchLater() async {
    if (_currentVideoItem == null) return;
    await _storageService.toggleWatchLater(_currentVideoItem!);
    notifyListeners();
  }

  Future<void> toggleFollowChannel() async {
    if (_currentVideoItem == null) return;
    final channel = TubeChannelInfo(
      id: _currentVideoItem!.channelId,
      title: _currentVideoItem!.channelTitle,
      avatarUrl: _currentVideoItem!.channelAvatarUrl,
    );
    await _storageService.toggleFollowChannel(channel);
    notifyListeners();
  }

  @override
  void dispose() {
    TubeSessionService().removeListener(_accountChanged);
    _storageService.removeListener(_privacyChanged);
    _disposed = true;
    ++_playGeneration;
    _recordCurrentWatchSignal();
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }
}
