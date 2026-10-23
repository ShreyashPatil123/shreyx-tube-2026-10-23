import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/tube_stream.dart';

class PlaybackProgress {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool isPlaying;
  final bool isBuffering;

  const PlaybackProgress({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.isPlaying,
    required this.isBuffering,
  });

  static const zero = PlaybackProgress(
    position: Duration.zero,
    duration: Duration.zero,
    buffered: Duration.zero,
    isPlaying: false,
    isBuffering: false,
  );
}

class TubePlayerService {
  static final TubePlayerService _instance = TubePlayerService._internal();
  factory TubePlayerService() => _instance;
  TubePlayerService._internal() {
    _playerChannel.setMethodCallHandler(_handleNativeMethodCall);
  }

  static const MethodChannel _playerChannel =
      MethodChannel('com.shreyx.tube/player_channel');

  final _progressController = StreamController<PlaybackProgress>.broadcast();
  Stream<PlaybackProgress> get progressStream => _progressController.stream;

  final _isPlayingController = StreamController<bool>.broadcast();
  Stream<bool> get isPlayingStream => _isPlayingController.stream;

  final _stateController = StreamController<String>.broadcast();
  Stream<String> get stateStream => _stateController.stream;

  final _videoSizeController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get videoSizeStream =>
      _videoSizeController.stream;

  final _errorController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get errorStream => _errorController.stream;

  final _pipController = StreamController<bool>.broadcast();
  Stream<bool> get pipStream => _pipController.stream;
  Future<Map<String, dynamic>> getStatus() async {
    final value = await _playerChannel.invokeMethod('getStatus');
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  Future<bool> loadStream(
    TubeVideoStream stream, {
    int startPositionMs = 0,
    bool autoPlay = true,
    String? title,
    String? channelTitle,
    String? videoId,
    String? thumbnailUrl,
    bool requiresAccount = false,
  }) async {
    try {
      final params = stream.toMediaParams(
        startPositionMs: startPositionMs,
        autoPlay: autoPlay,
      );
      if (title != null && title.isNotEmpty) params['title'] = title;
      if (channelTitle != null && channelTitle.isNotEmpty) {
        params['channelTitle'] = channelTitle;
      }
      params['videoId'] = videoId;
      params['thumbnailUrl'] = thumbnailUrl;
      params['requiresAccount'] = requiresAccount;
      final res = await _playerChannel.invokeMethod('loadMedia', params);
      return res is Map && res['ok'] == true;
    } catch (e) {
      debugPrint('[TubePlayerService] loadStream error: $e');
      return false;
    }
  }

  Future<void> setBrightness(double value) async {
    try {
      await _playerChannel
          .invokeMethod('setBrightness', {'value': value.clamp(0.0, 1.0)});
    } catch (_) {}
  }

  Future<void> setVolume(double value) async {
    try {
      await _playerChannel
          .invokeMethod('setVolume', {'value': value.clamp(0.0, 1.0)});
    } catch (_) {}
  }

  Future<void> play() async {
    try {
      await _playerChannel.invokeMethod('play');
    } catch (_) {}
  }

  Future<void> pause() async {
    try {
      await _playerChannel.invokeMethod('pause');
    } catch (_) {}
  }

  Future<void> stop({bool strict = false}) async {
    try {
      await _playerChannel.invokeMethod('stop');
    } catch (_) {
      if (strict) rethrow;
    }
  }

  Future<void> seekToLive() async {
    try {
      await _playerChannel.invokeMethod('seekToLive');
    } catch (_) {}
  }

  Future<void> seekTo(Duration position) async {
    try {
      await _playerChannel
          .invokeMethod('seekTo', {'positionMs': position.inMilliseconds});
    } catch (_) {}
  }

  Future<void> setSpeed(double speed) async {
    try {
      await _playerChannel.invokeMethod('setSpeed', {'speed': speed});
    } catch (_) {}
  }

  Future<bool> enterPip() async {
    try {
      final res = await _playerChannel.invokeMethod('enterPip');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPipModeChanged':
        _pipController.add(call.arguments == true);
        break;
      case 'onProgressUpdate':
        if (call.arguments is Map) {
          final map = call.arguments as Map;
          final posMs = (map['positionMs'] as num?)?.toInt() ?? 0;
          final durMs = (map['durationMs'] as num?)?.toInt() ?? 0;
          final bufMs = (map['bufferedMs'] as num?)?.toInt() ?? 0;
          final isPlaying = map['isPlaying'] == true;
          final isBuffering = map['isBuffering'] == true;

          _progressController.add(PlaybackProgress(
            position: Duration(milliseconds: posMs),
            duration: Duration(milliseconds: durMs),
            buffered: Duration(milliseconds: bufMs),
            isPlaying: isPlaying,
            isBuffering: isBuffering,
          ));
        }
        break;

      case 'onPlaybackStateChanged':
        if (call.arguments is Map) {
          final state =
              (call.arguments as Map)['state']?.toString() ?? 'UNKNOWN';
          _stateController.add(state);
        }
        break;

      case 'onIsPlayingChanged':
        if (call.arguments is bool) {
          _isPlayingController.add(call.arguments as bool);
        }
        break;

      case 'onVideoSizeChanged':
        if (call.arguments is Map) {
          _videoSizeController
              .add(Map<String, dynamic>.from(call.arguments as Map));
        }
        break;

      case 'onPlaybackError':
        if (call.arguments is Map) {
          debugPrint(
              '[TubePlayerService] Native Media3 error reported: ${call.arguments}');
          _errorController
              .add(Map<String, dynamic>.from(call.arguments as Map));
        }
        break;
    }
  }

  void dispose() {
    _progressController.close();
    _isPlayingController.close();
    _stateController.close();
    _videoSizeController.close();
    _errorController.close();
  }
}
