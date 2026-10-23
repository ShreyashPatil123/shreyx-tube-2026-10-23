import '../models/tube_models.dart';
import 'tube_recommendation_engine.dart';

/// Legacy recommendation service adapter.
/// Delegates all ranking logic to the unified TubeRecommendationEngine.
class TubeRecommendationService {
  static final TubeRecommendationService _instance = TubeRecommendationService._internal();
  factory TubeRecommendationService() => _instance;
  TubeRecommendationService._internal();

  final TubeRecommendationEngine _engine = TubeRecommendationEngine();

  void recordImpression(String videoId) {
    _engine.recordImpression(videoId);
  }

  List<TubeVideoItem> rankHomeFeed(List<TubeVideoItem> publicCandidates) {
    return _engine.rankHomeFeed(publicCandidates);
  }

  List<TubeVideoItem> rankUpNext({
    required TubeVideoItem currentVideo,
    required List<TubeVideoItem> candidates,
  }) {
    return _engine.rankUpNext(currentVideo: currentVideo, candidates: candidates);
  }

  List<TubeVideoItem> rankShortsFeed(List<TubeVideoItem> candidateShorts) {
    return _engine.rankShorts(candidateShorts);
  }

  List<TubeVideoItem> personalizeFeed(List<TubeVideoItem> publicCandidates) {
    return _engine.rankHomeFeed(publicCandidates);
  }
}
