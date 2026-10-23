/// On-device adaptive user interest profile.
/// All user profile signals remain strictly on the device.
/// Features dynamic learning across short-term (7-day) and long-term (30+ day) models.
class TubeUserProfile {
  Map<String, double> topicScores;
  Map<String, double> channelScores;

  Map<String, double> shortTermTopics;
  Map<String, double> shortTermChannels;

  Map<String, double> longTermTopics;
  Map<String, double> longTermChannels;

  Map<String, double> searchInterests;
  Map<String, double> negativeTopics;
  Map<String, double> negativeChannels;

  List<String> recentlyShownIds;
  List<String> recentlyWatchedIds;

  Map<String, double> homeWeights;
  Map<String, double> upNextWeights;
  Map<String, double> shortsWeights;

  /// Accumulated feature evidence for multi-session gradual weight adaptation
  /// { featureName: { 'impressions': count, 'successes': count } }
  Map<String, Map<String, double>> featureEvidence;

  DateTime lastUpdated;
  int totalWatchSessions;

  TubeUserProfile({
    Map<String, double>? topicScores,
    Map<String, double>? channelScores,
    Map<String, double>? shortTermTopics,
    Map<String, double>? shortTermChannels,
    Map<String, double>? longTermTopics,
    Map<String, double>? longTermChannels,
    Map<String, double>? searchInterests,
    Map<String, double>? negativeTopics,
    Map<String, double>? negativeChannels,
    List<String>? recentlyShownIds,
    List<String>? recentlyWatchedIds,
    Map<String, double>? homeWeights,
    Map<String, double>? upNextWeights,
    Map<String, double>? shortsWeights,
    Map<String, Map<String, double>>? featureEvidence,
    DateTime? lastUpdated,
    this.totalWatchSessions = 0,
  })  : topicScores = topicScores ?? {},
        channelScores = channelScores ?? {},
        shortTermTopics = shortTermTopics ?? {},
        shortTermChannels = shortTermChannels ?? {},
        longTermTopics = longTermTopics ?? {},
        longTermChannels = longTermChannels ?? {},
        searchInterests = searchInterests ?? {},
        negativeTopics = negativeTopics ?? {},
        negativeChannels = negativeChannels ?? {},
        recentlyShownIds = recentlyShownIds ?? [],
        recentlyWatchedIds = recentlyWatchedIds ?? [],
        homeWeights = homeWeights ?? _defaultHomeWeights(),
        upNextWeights = upNextWeights ?? _defaultUpNextWeights(),
        shortsWeights = shortsWeights ?? _defaultShortsWeights(),
        featureEvidence = featureEvidence ?? {},
        lastUpdated = lastUpdated ?? DateTime.now();

  static Map<String, double> _defaultHomeWeights() => {
        'topicSimilarity': 0.25,
        'channelAffinity': 0.20,
        'freshness': 0.30,
        'popularity': 0.05,
        'novelty': 0.12,
        'diversity': 0.08,
      };

  static Map<String, double> _defaultUpNextWeights() => {
        'currentVideoSimilarity': 0.35,
        'channelAffinity': 0.25,
        'topicSimilarity': 0.20,
        'freshness': 0.10,
        'novelty': 0.10,
      };

  static Map<String, double> _defaultShortsWeights() => {
        'completionLikelihood': 0.30,
        'channelAffinity': 0.20,
        'topicSimilarity': 0.20,
        'novelty': 0.15,
        'freshness': 0.15,
      };

  static const int maxTopicEntries = 200;
  static const int maxChannelEntries = 200;
  static const int maxRecentlyShownIds = 500;
  static const int maxRecentlyWatchedIds = 250;

  void enforceCapacity() {
    _pruneMap(topicScores, maxTopicEntries);
    _pruneMap(shortTermTopics, maxTopicEntries);
    _pruneMap(longTermTopics, maxTopicEntries);
    _pruneMap(searchInterests, maxTopicEntries);
    _pruneMap(negativeTopics, maxTopicEntries);
    _pruneMap(channelScores, maxChannelEntries);
    _pruneMap(shortTermChannels, maxChannelEntries);
    _pruneMap(longTermChannels, maxChannelEntries);
    _pruneMap(negativeChannels, maxChannelEntries);

    if (recentlyShownIds.length > maxRecentlyShownIds) {
      recentlyShownIds = recentlyShownIds.take(maxRecentlyShownIds).toList();
    }
    if (recentlyWatchedIds.length > maxRecentlyWatchedIds) {
      recentlyWatchedIds =
          recentlyWatchedIds.take(maxRecentlyWatchedIds).toList();
    }
  }

  void _pruneMap(Map<String, double> map, int maxItems) {
    if (map.length <= maxItems) return;
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    map.clear();
    for (int i = 0; i < maxItems && i < entries.length; i++) {
      map[entries[i].key] = entries[i].value;
    }
  }

  double getEffectiveTopicScore(String topic) {
    final lower = topic.toLowerCase().trim();
    final st = shortTermTopics[lower] ?? 0.0;
    final lt = longTermTopics[lower] ?? 0.0;
    final base = topicScores[lower] ?? 0.0;

    // Blend: 60% short-term, 40% long-term / base
    return ((0.6 * st) + (0.4 * (lt > 0 ? lt : base))).clamp(0.0, 1.0);
  }

  double getEffectiveChannelScore(String channelId) {
    final st = shortTermChannels[channelId] ?? 0.0;
    final lt = longTermChannels[channelId] ?? 0.0;
    final base = channelScores[channelId] ?? 0.0;
    return ((0.6 * st) + (0.4 * (lt > 0 ? lt : base))).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'topicScores': topicScores,
        'channelScores': channelScores,
        'shortTermTopics': shortTermTopics,
        'shortTermChannels': shortTermChannels,
        'longTermTopics': longTermTopics,
        'longTermChannels': longTermChannels,
        'searchInterests': searchInterests,
        'negativeTopics': negativeTopics,
        'negativeChannels': negativeChannels,
        'recentlyShownIds': recentlyShownIds,
        'recentlyWatchedIds': recentlyWatchedIds,
        'homeWeights': homeWeights,
        'upNextWeights': upNextWeights,
        'shortsWeights': shortsWeights,
        'featureEvidence': featureEvidence,
        'lastUpdated': lastUpdated.toIso8601String(),
        'totalWatchSessions': totalWatchSessions,
      };

  factory TubeUserProfile.fromJson(Map<String, dynamic> json) =>
      TubeUserProfile(
        topicScores: (json['topicScores'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
        channelScores: (json['channelScores'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
        shortTermTopics: (json['shortTermTopics'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
        shortTermChannels: (json['shortTermChannels'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
        longTermTopics: (json['longTermTopics'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
        longTermChannels: (json['longTermChannels'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
        searchInterests: (json['searchInterests'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
        negativeTopics: (json['negativeTopics'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
        negativeChannels: (json['negativeChannels'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
        recentlyShownIds: (json['recentlyShownIds'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList(),
        recentlyWatchedIds: (json['recentlyWatchedIds'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList(),
        homeWeights: (json['homeWeights'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
        upNextWeights: (json['upNextWeights'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
        shortsWeights: (json['shortsWeights'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
        featureEvidence:
            (json['featureEvidence'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(
              k,
              (v as Map<String, dynamic>)
                  .map((ik, iv) => MapEntry(ik, (iv as num).toDouble()))),
        ),
        lastUpdated: DateTime.tryParse(json['lastUpdated'] as String? ?? '') ??
            DateTime.now(),
        totalWatchSessions: (json['totalWatchSessions'] as num?)?.toInt() ?? 0,
      );
}
