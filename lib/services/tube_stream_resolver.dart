import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/tube_stream.dart';
import 'tube_cache_service.dart';
import 'tube_youtube_explode_pool.dart';
import 'tube_youtube_link.dart';
import 'tube_session_service.dart';
import 'tube_innertube_client.dart';
import 'tube_authorized_playback.dart';

class TubeMembersOnlyException implements Exception {
  const TubeMembersOnlyException(
      [this.message =
          'YouTube has not granted this account access to the members-only video. Connect an eligible account or open it in YouTube.']);
  final String message;
}

class TubeStreamResolver {
  static final TubeStreamResolver _instance = TubeStreamResolver._internal();
  factory TubeStreamResolver() => _instance;
  TubeStreamResolver._internal()
      : _loader = null,
        accountLoader = null;
  @visibleForTesting
  TubeStreamResolver.withLoader(this._loader, {this.accountLoader});
  final Future<TubeResolvedVideo> Function(String)? _loader;
  final Future<TubeResolvedVideo> Function(String)? accountLoader;

  static const MethodChannel _extractorChannel =
      MethodChannel('com.shreyx.tube/native_extractor');
  final TubeYoutubeExplodePool _ytPool = TubeYoutubeExplodePool.instance;
  final Map<String, Future<TubeResolvedVideo>> _pending = {};

  int _epoch = 0;
  void clearCache() {
    _epoch++;
    _streamCache.clear();
    _pending.clear();
  }

  // Ephemeral stream cache (YouTube stream URLs remain valid for ~6 hours; 2h TTL provides high hit rate with safety)
  final TubeMemoryCache<TubeResolvedVideo> _streamCache =
      TubeMemoryCache(defaultTtl: const Duration(hours: 2), maxCapacity: 25);

  /// Extracts the 11-character YouTube video ID from various URL patterns
  String extractVideoId(String input) {
    final trimmed = input.trim();
    if (trimmed.length == 11 &&
        RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(trimmed)) {
      return trimmed;
    }

    return TubeYoutubeLink.parse(trimmed)?.videoId ?? trimmed;
  }

  /// Multi-tier stream resolution:
  /// 1. Android NewPipeExtractor (Tier 1)
  /// 2. youtube_explode_dart fallback (Tier 2)
  /// 3. In-memory ephemeral stream caching (2-hour TTL)
  Future<TubeResolvedVideo> resolve(String rawUrlOrId,
      {bool forceRefresh = false, bool requireAccount = false}) async {
    final videoId = extractVideoId(rawUrlOrId);
    if (requireAccount) {
      if (!TubeYoutubeLink.isVideoId(videoId)) {
        throw ArgumentError('Invalid video ID');
      }
      if (!TubeSessionService().usesPrivateFeed) {
        throw const TubeMembersOnlyException();
      }
      // Account streams never enter the public/prefetch cache and cannot survive
      // a logout, Incognito switch or account change during the request.
      final identity = TubeInnertubeClient().requestIdentity;
      final result = await (accountLoader?.call(videoId) ??
          TubeAuthorizedPlayback().resolve(videoId));
      if (identity != TubeInnertubeClient().requestIdentity) {
        throw StateError('Account changed during playback resolution.');
      }
      return result;
    }
    if (forceRefresh) _streamCache.remove(videoId);
    final existing = _pending[videoId];
    if (existing != null) return existing;
    final task = _resolve(videoId, forceRefresh: forceRefresh);
    _pending[videoId] = task;
    try {
      return await task;
    } finally {
      if (identical(_pending[videoId], task)) _pending.remove(videoId);
    }
  }

  Future<TubeResolvedVideo> _resolve(String rawUrlOrId,
      {bool forceRefresh = false}) async {
    final epoch = _epoch;
    final videoId = extractVideoId(rawUrlOrId);
    if (!TubeYoutubeLink.isVideoId(videoId)) {
      throw Exception('Invalid YouTube Video ID or URL: "$rawUrlOrId"');
    }

    if (!forceRefresh) {
      final cached = _streamCache.get(videoId);
      if (cached != null) {
        debugPrint(
            '[TubeStreamResolver] ⚡ Cache HIT for $videoId (skipping extraction)');
        return cached;
      }
    }

    debugPrint('[TubeStreamResolver] Resolving stream for videoId: $videoId');
    final loader = _loader;
    if (loader != null) {
      final result = await loader(videoId);
      if (epoch == _epoch) _streamCache.set(videoId, result);
      return result;
    }

    // Tier 1: Android Native NewPipeExtractor
    if (Platform.isAndroid) {
      try {
        final nativeResult = await _resolveNative(videoId);
        if (nativeResult != null) {
          if (epoch == _epoch) _streamCache.set(videoId, nativeResult);
          return nativeResult;
        }
      } catch (e) {
        if (isMembershipFailure(e)) {
          if (TubeSessionService().usesPrivateFeed) {
            return resolve(videoId, requireAccount: true);
          }
          throw const TubeMembersOnlyException();
        }
        debugPrint(
            '[TubeStreamResolver] Native NewPipe failed: $e, trying Tier 2 (youtube_explode_dart)...');
      }
    }

    // Tier 2: youtube_explode_dart Fallback
    try {
      final fallbackResult = await _resolveYoutubeExplode(videoId);
      if (epoch == _epoch) _streamCache.set(videoId, fallbackResult);
      return fallbackResult;
    } catch (e) {
      if (isMembershipFailure(e)) {
        if (TubeSessionService().usesPrivateFeed) {
          return resolve(videoId, requireAccount: true);
        }
        throw const TubeMembersOnlyException();
      }
      debugPrint('[TubeStreamResolver] youtube_explode_dart failed: $e');
      if (e is SocketException ||
          e is TimeoutException ||
          e is TransientFailureException) {
        throw Exception(
            'Network request failed. Check your connection and retry.');
      }
      if (e is VideoUnavailableException) {
        throw Exception(
            'This video is unavailable, private or has been removed. You can try opening it in YouTube.');
      }
      if (e is VideoUnplayableException) {
        throw Exception(
            'YouTube restricts access to this video. Open it in YouTube with an eligible account.');
      }
      throw Exception(
          'Could not extract a playable stream. Retry, or open the original video in YouTube.');
    }
  }

  /// A title, HTTP 403, network error or generic extractor message is not membership evidence.
  static bool isMembershipFailure(Object error) {
    if (error is TubeMembersOnlyException) return true;
    if (error is PlatformException) return error.code == 'members_only';
    if (error is! VideoUnplayableException) return false;
    final message = error.toString().toLowerCase();
    return message.contains('members-only') ||
        message.contains('members only') ||
        message.contains('only available to members');
  }

  Future<TubeResolvedVideo?> _resolveNative(String videoId) async {
    final dynamic res =
        await _extractorChannel.invokeMethod('extractVideoStreams', {
      'videoId': videoId,
    }).timeout(const Duration(seconds: 18));

    if (res is Map && res['ok'] != true && res['reason'] == 'members_only') {
      throw const TubeMembersOnlyException();
    }
    if (res is Map && res['ok'] == true) {
      final rawProg = (res['progressiveStreams'] as List<dynamic>?) ?? [];
      final rawVideoOnly = (res['videoOnlyStreams'] as List<dynamic>?) ?? [];
      final rawAudio = (res['audioStreams'] as List<dynamic>?) ?? [];
      final rawSubtitles = (res['subtitles'] as List<dynamic>?) ?? [];

      final progressive =
          rawProg.map((e) => TubeVideoStream.fromMap(e as Map)).toList();
      final videoOnly =
          rawVideoOnly.map((e) => TubeVideoStream.fromMap(e as Map)).toList();
      final audio =
          rawAudio.map((e) => TubeAudioStream.fromMap(e as Map)).toList();
      final subtitles =
          rawSubtitles.map((e) => TubeSubtitle.fromMap(e as Map)).toList();

      // Pair best audio stream (Opus 160kbps / AAC) with adaptive video-only streams
      TubeAudioStream? bestAudio;
      if (audio.isNotEmpty) {
        // Prefer Opus audio >= 140kbps, then AAC
        bestAudio = audio.firstWhere(
          (a) => a.codec.toLowerCase().contains('opus') && a.bitrate >= 140000,
          orElse: () => audio.reduce((a, b) => a.bitrate > b.bitrate ? a : b),
        );
      }

      for (final vs in videoOnly) {
        vs.pairedAudioUrl = bestAudio?.url;
      }

      final allVideoStreams = [...progressive, ...videoOnly];
      allVideoStreams.sort((a, b) {
        final hDiff = b.height.compareTo(a.height);
        if (hDiff != 0) return hDiff;
        return b.bitrate.compareTo(a.bitrate);
      });

      return TubeResolvedVideo(
        videoId: videoId,
        title: res['title']?.toString() ?? 'YouTube Video',
        uploader: res['uploader']?.toString() ?? 'Unknown Creator',
        uploaderUrl: res['uploaderUrl']?.toString() ?? '',
        uploaderAvatarUrl: res['uploaderAvatarUrl']?.toString() ?? '',
        durationSeconds: (res['durationSeconds'] as num?)?.toInt() ?? 0,
        thumbnailUrl: res['thumbnailUrl']?.toString() ??
            'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
        videoStreams: allVideoStreams,
        audioStreams: audio,
        subtitles: subtitles,
        hlsUrl: res['hlsUrl']?.toString(),
        dashMpdUrl: res['dashMpdUrl']?.toString(),
        extractorSource: res['extractor']?.toString() ?? 'NewPipeExtractor',
        isLive: res['isLive'] == true,
      );
    }
    return null;
  }

  Future<TubeResolvedVideo> _resolveYoutubeExplode(String videoId) async {
    final videoFuture = _ytPool.yt.videos.get(videoId);
    final manifestFuture = _ytPool.yt.videos.streamsClient
        .getManifest(videoId)
        .then<StreamManifest?>((value) => value)
        .catchError((_) => null);
    final results = await Future.wait<dynamic>([videoFuture, manifestFuture]);
    final video = results[0] as Video;
    if (video.isLive) {
      final hls = await _ytPool.yt.videos.streamsClient
          .getHttpLiveStreamUrl(VideoId(videoId));
      return TubeResolvedVideo(
          videoId: videoId,
          title: video.title,
          uploader: video.author,
          durationSeconds: 0,
          thumbnailUrl: video.thumbnails.highResUrl,
          videoStreams: [],
          audioStreams: [],
          subtitles: [],
          hlsUrl: hls,
          extractorSource: 'youtube_explode_dart',
          isLive: true);
    }
    final manifest = results[1] as StreamManifest?;
    if (manifest == null) throw Exception('Video streams are unavailable');

    final List<TubeVideoStream> videoStreams = [];
    final List<TubeAudioStream> audioStreams = [];

    // Muxed progressive streams (360p / 720p)
    for (final s in manifest.muxed) {
      videoStreams.add(TubeVideoStream(
        url: s.url.toString(),
        resolution: '${s.videoResolution.height}p',
        width: s.videoResolution.width,
        height: s.videoResolution.height,
        container: s.container.name,
        mimeType: s.codec.mimeType,
        codec: s.videoCodec,
        fps: s.framerate.framesPerSecond.toInt(),
        bitrate: s.bitrate.bitsPerSecond.toInt(),
        isVideoOnly: false,
        deliveryMethod: 'PROGRESSIVE',
        manifestType: 'PROGRESSIVE',
      ));
    }

    // Audio-only streams
    for (final a in manifest.audioOnly) {
      audioStreams.add(TubeAudioStream(
        url: a.url.toString(),
        container: a.container.name,
        mimeType: a.codec.mimeType,
        codec: a.audioCodec,
        bitrate: a.bitrate.bitsPerSecond.toInt(),
      ));
    }

    // Pick best audio for merging
    TubeAudioStream? bestAudio;
    if (audioStreams.isNotEmpty) {
      bestAudio = audioStreams.reduce((a, b) => a.bitrate > b.bitrate ? a : b);
    }

    // Adaptive video-only streams (1080p, 1440p, 4K)
    for (final v in manifest.videoOnly) {
      videoStreams.add(TubeVideoStream(
        url: v.url.toString(),
        resolution: '${v.videoResolution.height}p',
        width: v.videoResolution.width,
        height: v.videoResolution.height,
        container: v.container.name,
        mimeType: v.codec.mimeType,
        codec: v.videoCodec,
        fps: v.framerate.framesPerSecond.toInt(),
        bitrate: v.bitrate.bitsPerSecond.toInt(),
        isVideoOnly: true,
        deliveryMethod: 'DASH_ADAPTIVE',
        manifestType: 'ADAPTIVE_VIDEO_ONLY',
        pairedAudioUrl: bestAudio?.url,
      ));
    }

    videoStreams.sort((a, b) => b.height.compareTo(a.height));

    // Captions arrive independently and never hold up the first video frame.
    final List<TubeSubtitle> subtitles = [];
    unawaited(_loadFallbackCaptions(videoId, subtitles));

    return TubeResolvedVideo(
      videoId: videoId,
      title: video.title,
      uploader: video.author,
      durationSeconds: video.duration?.inSeconds ?? 0,
      thumbnailUrl: video.thumbnails.highResUrl,
      videoStreams: videoStreams,
      audioStreams: audioStreams,
      subtitles: subtitles,
      extractorSource: 'youtube_explode_dart',
    );
  }

  Future<void> _loadFallbackCaptions(
      String videoId, List<TubeSubtitle> subtitles) async {
    try {
      final trackManifest = await _ytPool.yt.videos.closedCaptions
          .getManifest(VideoId(videoId))
          .timeout(const Duration(seconds: 6));
      for (final track in trackManifest.tracks) {
        subtitles.add(TubeSubtitle(
          url: track.url.toString(),
          languageName: track.language.name,
          languageCode: track.language.code,
          format: 'vtt',
          isAutoGenerated: track.isAutoGenerated,
        ));
      }
    } catch (_) {}
  }

  /// Invalidate cache for a specific video ID (e.g. on 403 or stream expiration)
  void invalidateCache(String videoId) {
    _streamCache.remove(videoId);
  }
}
