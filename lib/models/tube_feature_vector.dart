/// 12-feature vector calculated per video candidate.
/// All features are normalized into the range [0.0, 1.0].
class TubeFeatureVector {
  final double topicSimilarity;
  final double channelAffinity;
  final double searchInterestAlignment;
  final double watchHistoryAlignment;
  final double currentVideoSimilarity;
  final double completionLikelihood;
  final double satisfactionLikelihood;
  final double freshness;
  final double popularity;
  final double novelty;
  final double diversity;
  final double explorationValue;

  final String topReason;

  const TubeFeatureVector({
    this.topicSimilarity = 0.0,
    this.channelAffinity = 0.0,
    this.searchInterestAlignment = 0.0,
    this.watchHistoryAlignment = 0.0,
    this.currentVideoSimilarity = 0.0,
    this.completionLikelihood = 0.5,
    this.satisfactionLikelihood = 0.5,
    this.freshness = 0.5,
    this.popularity = 0.5,
    this.novelty = 0.5,
    this.diversity = 0.5,
    this.explorationValue = 0.1,
    this.topReason = 'Discovered for you',
  });

  Map<String, double> toMap() => {
        'topicSimilarity': topicSimilarity,
        'channelAffinity': channelAffinity,
        'searchInterestAlignment': searchInterestAlignment,
        'watchHistoryAlignment': watchHistoryAlignment,
        'currentVideoSimilarity': currentVideoSimilarity,
        'completionLikelihood': completionLikelihood,
        'satisfactionLikelihood': satisfactionLikelihood,
        'freshness': freshness,
        'popularity': popularity,
        'novelty': novelty,
        'diversity': diversity,
        'explorationValue': explorationValue,
      };

  Map<String, dynamic> toFullMap() => {
        ...toMap(),
        'topReason': topReason,
      };

  double dotProduct(Map<String, double> weights) {
    double score = 0.0;
    score += topicSimilarity * (weights['topicSimilarity'] ?? 0.20);
    score += channelAffinity * (weights['channelAffinity'] ?? 0.15);
    score += searchInterestAlignment * (weights['searchInterestAlignment'] ?? 0.15);
    score += watchHistoryAlignment * (weights['watchHistoryAlignment'] ?? 0.0);
    score += currentVideoSimilarity * (weights['currentVideoSimilarity'] ?? 0.0);
    score += completionLikelihood * (weights['completionLikelihood'] ?? 0.0);
    score += satisfactionLikelihood * (weights['satisfactionLikelihood'] ?? 0.0);
    score += freshness * (weights['freshness'] ?? 0.15);
    score += popularity * (weights['popularity'] ?? 0.15);
    score += novelty * (weights['novelty'] ?? 0.10);
    score += explorationValue * (weights['diversity'] ?? 0.10);
    return score;
  }
}
