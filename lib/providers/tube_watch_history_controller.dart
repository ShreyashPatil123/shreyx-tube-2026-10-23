import 'dart:async';
import '../models/tube_models.dart';

/// Manages local watch history tracking, position saving, and telemetry signals.
/// Ensures both normal video and Shorts watch events update the user profile.
class TubeWatchHistoryController {
  Timer? _positionSaveTimer;
  TubeVideoItem? _currentVideo;

  DateTime? _watchStartTime;
  bool _isPaused = false;  // privacy: pause history recording
  
  // Callbacks to be set by the parent
  Future<void> Function(String videoId, int positionMs, double completionPct)? onSavePosition;
  Future<void> Function(TubeWatchSignal signal)? onRecordSignal;
  Future<void> Function(TubeVideoItem video, int positionMs)? onUpdateHistory;
  
  /// Start tracking a video playback session
  void startTracking(TubeVideoItem video, {int startPositionMs = 0}) {
    stopTracking(); // Stop any previous tracking
    
    _currentVideo = video;
    _watchStartTime = DateTime.now();
    
    // Save position every 5 seconds (throttled)
    _positionSaveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _saveCurrentPosition(),
    );
    
    // Record initial history entry
    if (!_isPaused) {
      onUpdateHistory?.call(video, startPositionMs);
    }
  }
  
  /// Update current position (called from player progress)
  int _lastPositionMs = 0;
  int _lastDurationMs = 0;
  
  void updatePosition(int positionMs, int durationMs) {
    _lastPositionMs = positionMs;
    _lastDurationMs = durationMs;
  }
  
  /// Stop tracking and record final watch signal
  Future<void> stopTracking({bool recordSignal = true}) async {
    _positionSaveTimer?.cancel();
    _positionSaveTimer = null;
    
    if (recordSignal && _currentVideo != null && _watchStartTime != null && !_isPaused) {
      await _recordWatchSignal();
    }
    
    _currentVideo = null;
    _watchStartTime = null;
  }
  
  void _saveCurrentPosition() {
    if (_currentVideo == null || _isPaused) return;
    if (_lastDurationMs <= 0) return;
    
    final completionPct = _lastDurationMs > 0 
        ? (_lastPositionMs / _lastDurationMs).clamp(0.0, 1.0) 
        : 0.0;
    
    onSavePosition?.call(_currentVideo!.id, _lastPositionMs, completionPct);
  }
  
  Future<void> _recordWatchSignal() async {
    if (_currentVideo == null || _watchStartTime == null) return;
    
    final watchDurationMs = DateTime.now().difference(_watchStartTime!).inMilliseconds;
    final completionRatio = _lastDurationMs > 0 
        ? (_lastPositionMs / _lastDurationMs).clamp(0.0, 1.0) 
        : 0.0;
    final isFastSkip = completionRatio < 0.15 && watchDurationMs < 30000;
    
    final signal = TubeWatchSignal(
      videoId: _currentVideo!.id,
      title: _currentVideo!.title,
      channelId: _currentVideo!.channelId,
      channelTitle: _currentVideo!.channelTitle,
      completionRatio: completionRatio,
      watchDurationSeconds: watchDurationMs ~/ 1000,
      isRewatch: false, // TODO: check history
      isFastSkip: isFastSkip,
      timestamp: DateTime.now(),
    );
    
    await onRecordSignal?.call(signal);
  }
  
  /// Set privacy mode
  void setPauseHistory(bool paused) {
    _isPaused = paused;
  }
  
  void dispose() {
    _positionSaveTimer?.cancel();
  }
}
