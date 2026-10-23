import 'package:flutter/foundation.dart';
import '../models/tube_stream.dart';

/// Manages video stream quality options and selection.
/// Extracted from TubePlayerProvider for single responsibility.
class TubeQualityController extends ChangeNotifier {
  TubeResolvedVideo? _resolvedVideo;
  String _selectedQuality = 'Auto';

  TubeResolvedVideo? get resolvedVideo => _resolvedVideo;
  String get selectedQuality => _selectedQuality;
  List<String> get availableQualities => _resolvedVideo?.availableQualities ?? ['Auto'];

  void setResolvedVideo(TubeResolvedVideo? video, {String? defaultQuality}) {
    _resolvedVideo = video;
    if (defaultQuality != null) {
      _selectedQuality = defaultQuality;
    } else if (_resolvedVideo != null && !_resolvedVideo!.availableQualities.contains(_selectedQuality)) {
      _selectedQuality = 'Auto';
    }
    notifyListeners();
  }

  void setSelectedQuality(String quality) {
    if (_selectedQuality != quality) {
      _selectedQuality = quality;
      notifyListeners();
    }
  }

  TubeVideoStream? getActiveStream() {
    return _resolvedVideo?.getBestStream(_selectedQuality);
  }
}
