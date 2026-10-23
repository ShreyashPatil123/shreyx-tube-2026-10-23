import 'package:flutter/foundation.dart';
import '../models/tube_models.dart';

/// Manages the video playback queue (Up Next, user queue, autoplay).
/// Extracted from TubePlayerProvider to maintain single responsibility.
class TubeQueueController extends ChangeNotifier {
  final List<TubeVideoItem> _queue = [];
  int _currentIndex = -1;
  bool _autoplayEnabled = true;
  List<TubeVideoItem> _upNextSuggestions = [];  // Recommendation-generated
  
  // === Getters ===
  List<TubeVideoItem> get queue => List.unmodifiable(_queue);
  List<TubeVideoItem> get upNextSuggestions => List.unmodifiable(_upNextSuggestions);
  int get currentIndex => _currentIndex;
  int get queueLength => _queue.length;
  bool get autoplayEnabled => _autoplayEnabled;
  bool get hasNext => _currentIndex < _queue.length - 1 || _upNextSuggestions.isNotEmpty;
  bool get hasPrevious => _currentIndex > 0;
  
  TubeVideoItem? get currentVideo => 
    _currentIndex >= 0 && _currentIndex < _queue.length ? _queue[_currentIndex] : null;
  
  TubeVideoItem? get nextVideo {
    if (_currentIndex < _queue.length - 1) {
      return _queue[_currentIndex + 1];
    }
    if (_upNextSuggestions.isNotEmpty) {
      return _upNextSuggestions.first;
    }
    return null;
  }
  
  // === Queue Management ===
  
  /// Set a video as currently playing (resets queue position)
  void setCurrentVideo(TubeVideoItem video) {
    final existingIndex = _queue.indexWhere((v) => v.id == video.id);
    if (existingIndex >= 0) {
      _currentIndex = existingIndex;
    } else {
      // Insert at current position
      if (_currentIndex < 0) {
        _queue.insert(0, video);
        _currentIndex = 0;
      } else {
        _queue.insert(_currentIndex + 1, video);
        _currentIndex = _currentIndex + 1;
      }
    }
    notifyListeners();
  }
  
  /// Add a video to play next (after current)
  void playNext(TubeVideoItem video) {
    // Remove if already in queue
    _queue.removeWhere((v) => v.id == video.id);
    final insertAt = _currentIndex >= 0 ? _currentIndex + 1 : 0;
    _queue.insert(insertAt, video);
    notifyListeners();
  }
  
  /// Add a video to the end of the queue
  void addToQueue(TubeVideoItem video) {
    if (_queue.any((v) => v.id == video.id)) return; // No duplicates
    _queue.add(video);
    notifyListeners();
  }
  
  /// Remove a video from the queue by index
  /// FIX: Properly adjusts currentIndex when removing items before current position
  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    
    // Adjust current index if we removed an item before it
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex) {
      // Removed currently playing item
      if (_currentIndex >= _queue.length) {
        _currentIndex = _queue.length - 1;
      }
    }
    notifyListeners();
  }
  
  /// Reorder queue items
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex--;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    
    // Recalculate current index
    if (oldIndex == _currentIndex) {
      _currentIndex = newIndex;
    } else {
      if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
        _currentIndex--;
      } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
        _currentIndex++;
      }
    }
    notifyListeners();
  }
  
  /// Advance to next video, returns the video or null
  TubeVideoItem? advanceToNext() {
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      notifyListeners();
      return _queue[_currentIndex];
    }
    // Pull from up-next suggestions
    if (_upNextSuggestions.isNotEmpty) {
      final next = _upNextSuggestions.removeAt(0);
      _queue.add(next);
      _currentIndex = _queue.length - 1;
      notifyListeners();
      return next;
    }
    return null;
  }
  
  /// Go back to previous video
  TubeVideoItem? goToPrevious() {
    if (_currentIndex > 0) {
      _currentIndex--;
      notifyListeners();
      return _queue[_currentIndex];
    }
    return null;
  }
  
  /// Update the Up Next suggestions (from recommendation engine)
  void setUpNextSuggestions(List<TubeVideoItem> suggestions) {
    _upNextSuggestions = List.of(suggestions);
    notifyListeners();
  }
  
  /// Toggle autoplay
  void toggleAutoplay() {
    _autoplayEnabled = !_autoplayEnabled;
    notifyListeners();
  }
  
  /// Clear entire queue
  void clear() {
    _queue.clear();
    _upNextSuggestions.clear();
    _currentIndex = -1;
    notifyListeners();
  }
}
