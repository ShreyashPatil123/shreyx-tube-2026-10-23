import 'dart:math';
import '../models/tube_feature_vector.dart';
import '../models/tube_models.dart';
import '../models/tube_user_profile.dart';
import 'tube_storage_service.dart';
import 'tube_user_profile_service.dart';

/// Single, Unified Multi-Stage Adaptive Recommendation Engine for ShreyX Tube.
/// Operates 100% on-device. No telemetry, no external accounts.
///
/// Features:
/// 1. Freshness-First Ranking: Strong prioritization for uploads in the last 24h/48h/7d with evergreen preservation.
/// 2. Multi-Signal Scoring: Topic affinity, channel affinity, search alignment, freshness, novelty, popularity, exploration.
/// 3. Repetition Suppression: In-session impression penalties with time-based decay.
/// 4. Series Continuation Detection: Up Next continuation boosts for multi-part videos.
/// 5. Post-Ranking Diversification: Creator and topic caps to prevent monopolies.
class TubeRecommendationEngine {
  static final TubeRecommendationEngine _instance =
      TubeRecommendationEngine._internal();
  factory TubeRecommendationEngine() => _instance;
  TubeRecommendationEngine._internal();

  final TubeStorageService _storage = TubeStorageService();
  final TubeUserProfileService _profileService = TubeUserProfileService();

  // In-memory frequency tracking for active session repetition suppression
  final Map<String, int> _sessionImpressions = {};

  /// Diagnostic record of the latest feed generation
  Map<String, dynamic>? lastDiagnostics;

  /// Records an impression for a video to apply repetition penalty
  void recordImpression(String videoId) {
    _sessionImpressions[videoId] = (_sessionImpressions[videoId] ?? 0) + 1;
  }

  TubeUserProfile get _activeProfile {
    if (!_storage.pauseWatchHistory) {
      if (!_storage.pauseSearchHistory) return _profileService.profile;
      final profile =
          TubeUserProfile.fromJson(_profileService.profile.toJson());
      // Earlier versions also mixed search tokens into short-term topics.
      // Ignore that ambiguous legacy evidence while search history is paused.
      for (final topic in profile.searchInterests.keys) {
        profile.shortTermTopics.remove(topic);
      }
      profile.searchInterests.clear();
      return profile;
    }
    final profile = TubeUserProfile();
    for (final topic in [
      ..._profileService.interests,
      ..._profileService.feedTypes
    ]) {
      for (final word in _profileService.extractTopics(topic)) {
        profile.topicScores[word] = 0.8;
      }
    }
    for (final creator in List<Map<String, dynamic>>.from(
        _profileService.identity['creators'] ?? [])) {
      profile.channelScores[creator['id'] as String] = 0.9;
    }
    if (!_storage.pauseSearchHistory) {
      profile.searchInterests = _profileService.profile.searchInterests;
    }
    return profile;
  }

  void reset() {
    _sessionImpressions.clear();
    lastDiagnostics = null;
  }

  // =========================================================================
  // 1. HOME DISCOVERY FEED RANKING
  // =========================================================================

  /// Ranks candidates for the main Home feed.
  List<TubeVideoItem> rankHomeFeed(List<TubeVideoItem> candidates) {
    if (candidates.isEmpty) return [];
    if (_storage.isIncognito || _storage.pausePersonalization) {
      return List.from(candidates);
    }

    final profile = _activeProfile;
    final startTime = DateTime.now();

    // Stage 1: Candidate Filtering (Not Interested, Blocked Channels)
    final filtered = candidates.where((v) {
      if (_storage.isNotInterested(v.id, v.channelTitle)) return false;
      if (profile.negativeChannels.containsKey(v.channelId) &&
          (profile.negativeChannels[v.channelId]! > 0.6)) {
        return false;
      }
      return true;
    }).toList();

    // Stage 2 & 3: Feature Extraction & Scoring
    final scored = filtered.map((v) {
      final features = _extractFeatures(v, profile: profile);
      double score = _computeScore(features, profile.homeWeights);

      // Apply Repetition Penalties
      final impressions = _sessionImpressions[v.id] ?? 0;
      if (impressions == 1) {
        score -= 0.15;
      } else if (impressions == 2) {
        score -= 0.35;
      } else if (impressions >= 3) {
        score -= 0.60;
      }

      // Strong age penalty to keep recommendations fresh and modern
      if (v.uploadDate != null) {
        final ageDays = DateTime.now().difference(v.uploadDate!).inDays;
        if (ageDays > 730) {
          score -= 0.35; // Heavy suppression for > 2 years old
        } else if (ageDays > 365) {
          score -= 0.15; // Moderate suppression for > 1 year old
        }
      }

      for (final topic in _profileService.extractTopics(v.title)) {
        score -= (profile.negativeTopics[topic] ?? 0.0) * 0.18;
      }
      score -= (profile.negativeChannels[v.channelId] ?? 0.0) * 0.25;
      if (_storage.getLocalLikes().any((liked) =>
          liked.channelId.isNotEmpty && liked.channelId == v.channelId)) {
        score += 0.12;
      }
      return (video: v, score: score, features: features);
    }).toList();

    // Sort descending by score
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Stage 4: Post-Ranking Diversification
    final diversified = _applyDiversification(
        scored.map((s) => s.video).toList(),
        maxPerCreator: 2);

    // Diagnostics
    lastDiagnostics = {
      'feedType': 'home',
      'totalCandidates': candidates.length,
      'filteredCandidates': filtered.length,
      'diversifiedCount': diversified.length,
      'durationMs': DateTime.now().difference(startTime).inMilliseconds,
    };

    return diversified;
  }

  // =========================================================================
  // 2. UP NEXT CONTEXTUAL RANKING
  // =========================================================================

  /// Ranks candidates for the Up Next shelf of an active video.
  List<TubeVideoItem> rankUpNext({
    required TubeVideoItem currentVideo,
    required List<TubeVideoItem> candidates,
  }) {
    if (candidates.isEmpty) return [];
    if (_storage.isIncognito || _storage.pausePersonalization) {
      return List.from(candidates);
    }

    final profile = _activeProfile;
    final currentTopics =
        _profileService.extractTopics(currentVideo.title).toSet();
    final currentKeywords = _extractKeywords(currentVideo.title);

    // Filter out current video itself
    final filtered = candidates.where((v) => v.id != currentVideo.id).toList();

    final scored = filtered.map((v) {
      final features = _extractFeatures(
        v,
        profile: profile,
        currentVideo: currentVideo,
        currentTopics: currentTopics,
      );
      double score = _computeScore(features, profile.upNextWeights);

      // Contextual Boost: Keyword match with current video
      final candidateKeywords = _extractKeywords(v.title);
      final overlap = candidateKeywords.intersection(currentKeywords).length;
      if (overlap > 0) {
        score += min(overlap * 0.15, 0.40);
      }

      // Contextual Boost: Potential series continuation ("Part 2", "Episode 3")
      if (_isPotentialContinuation(currentVideo.title, v.title)) {
        score += 0.35;
      }

      // Same creator boost
      if (v.channelId == currentVideo.channelId ||
          (v.channelTitle.isNotEmpty &&
              v.channelTitle.toLowerCase() ==
                  currentVideo.channelTitle.toLowerCase())) {
        score += 0.25;
      }

      return (video: v, score: score);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((s) => s.video).toList();
  }

  // =========================================================================
  // 3. SHORTS VERTICAL FEED RANKING
  // =========================================================================

  /// Ranks candidates for the Shorts vertical feed.
  List<TubeVideoItem> rankShorts(List<TubeVideoItem> candidates) {
    if (candidates.isEmpty) return [];
    if (_storage.isIncognito || _storage.pausePersonalization) {
      return List.from(candidates);
    }
    final profile = _activeProfile;

    final scored = candidates.map((v) {
      final features = _extractFeatures(v, profile: profile, isShort: true);
      double score = _computeScore(features, profile.shortsWeights);

      // Penalty for fast-skipped creators
      if (profile.negativeChannels.containsKey(v.channelId)) {
        score -= (profile.negativeChannels[v.channelId] ?? 0.0) * 0.30;
      }

      return (video: v, score: score);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return _applyDiversification(scored.map((s) => s.video).toList(),
        maxPerCreator: 1);
  }

  /// Compatibility alias for rankShorts
  List<TubeVideoItem> rankShortsFeed(List<TubeVideoItem> candidates) =>
      rankShorts(candidates);

  // =========================================================================
  // 4. FEATURE EXTRACTION & SCORING
  // =========================================================================

  TubeFeatureVector _extractFeatures(
    TubeVideoItem video, {
    required dynamic profile,
    TubeVideoItem? currentVideo,
    Set<String>? currentTopics,
    bool isShort = false,
  }) {
    final topics = _profileService.extractTopics(video.title);

    // 1. Topic Similarity
    double topicSim = 0.0;
    for (final t in topics) {
      final s = profile.getEffectiveTopicScore(t);
      if (s > topicSim) topicSim = s;
    }

    // 2. Channel Affinity
    double chanAffinity = profile.getEffectiveChannelScore(video.channelId);
    if (_storage.isChannelFollowed(video.channelId)) {
      chanAffinity = max(chanAffinity, 0.85);
    }

    // 3. Search Interest Alignment
    double searchAlign = 0.0;
    for (final t in topics) {
      final sa = _storage.pauseSearchHistory
          ? 0.0
          : (profile.searchInterests[t] ?? 0.0) as double;
      if (sa > searchAlign) searchAlign = sa;
    }

    // 4. Current Video Similarity (for Up Next)
    double currSim = 0.0;
    if (currentVideo != null && currentTopics != null) {
      if (video.channelId == currentVideo.channelId) currSim += 0.4;
      final matchCount = topics.where((t) => currentTopics.contains(t)).length;
      currSim += (matchCount / max(1, currentTopics.length)) * 0.6;
    }

    // 5. Freshness with distinct time bands & evergreen floor
    double freshness = 0.0;
    final uploaded = video.effectiveUploadDate;
    if (uploaded != null && !uploaded.isAfter(DateTime.now())) {
      final age = DateTime.now().difference(uploaded);
      if (age.inHours <= 24) {
        freshness = 1.0; // Last 24 hours
      } else if (age.inHours <= 48) {
        freshness = 0.90; // Last 48 hours
      } else if (age.inDays <= 7) {
        freshness = 0.80; // Last 7 days
      } else if (age.inDays <= 30) {
        freshness = 0.60; // Last month
      } else if (age.inDays <= 90) {
        freshness = 0.40; // Last quarter
      } else if (age.inDays <= 365) {
        freshness = 0.15; // Past year
      } else {
        freshness = 0.02; // Very old content floor
      }
    }

    // 6. Popularity (normalized log views)
    double pop = 0.5;
    if (video.viewCount != null && video.viewCount! > 0) {
      pop = (log(video.viewCount! + 1) / log(10000000)).clamp(0.1, 1.0);
    }

    // 7. Novelty
    double novelty = 1.0;
    if (profile.recentlyWatchedIds.contains(video.id)) {
      novelty = 0.15; // Strongly demote recently watched
    } else if (profile.recentlyShownIds.contains(video.id)) {
      novelty = 0.40;
    }

    // 8. Exploration Value (controlled random discovery jitter)
    final exploration = 0.05 + (Random(video.id.hashCode).nextDouble() * 0.15);

    return TubeFeatureVector(
      topicSimilarity: topicSim,
      channelAffinity: chanAffinity,
      searchInterestAlignment: searchAlign,
      currentVideoSimilarity: currSim,
      freshness: freshness,
      popularity: pop,
      novelty: novelty,
      diversity: 0.5,
      explorationValue: exploration,
    );
  }

  double _computeScore(TubeFeatureVector f, Map<String, double> weights) {
    return f.dotProduct(weights);
  }

  // =========================================================================
  // 5. DIVERSIFICATION & CONTINUATION
  // =========================================================================

  /// Diversifies the feed by enforcing creator caps and deferring duplicates.
  List<TubeVideoItem> _applyDiversification(
    List<TubeVideoItem> items, {
    int maxPerCreator = 2,
  }) {
    final creatorCount = <String, int>{};
    final diversified = <TubeVideoItem>[];
    final deferred = <TubeVideoItem>[];

    for (final v in items) {
      final key = v.channelId.isNotEmpty ? v.channelId : v.channelTitle;
      if (key.isEmpty) {
        diversified.add(v);
        continue;
      }
      final count = creatorCount[key] ?? 0;
      if (count < maxPerCreator) {
        creatorCount[key] = count + 1;
        diversified.add(v);
      } else {
        deferred.add(v);
      }
    }

    // Append deferred items towards the tail so they are not lost
    diversified.addAll(deferred);
    return diversified;
  }

  Set<String> _extractKeywords(String text) {
    final clean = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    final tokens = clean.split(RegExp(r'\s+'));
    const stopWords = {
      'the',
      'a',
      'an',
      'and',
      'or',
      'in',
      'on',
      'at',
      'to',
      'for',
      'of',
      'with',
      'is',
      'how',
      'what',
      'why',
      'video'
    };
    return tokens.where((t) => t.length > 2 && !stopWords.contains(t)).toSet();
  }

  bool _isPotentialContinuation(String titleA, String titleB) {
    final epRegex = RegExp(r'(ep|episode|part|vol|chapter|#)\s*(\d+)',
        caseSensitive: false);
    final matchA = epRegex.firstMatch(titleA);
    final matchB = epRegex.firstMatch(titleB);

    if (matchA != null && matchB != null) {
      final numA = int.tryParse(matchA.group(2) ?? '');
      final numB = int.tryParse(matchB.group(2) ?? '');
      if (numA != null && numB != null && numB == numA + 1) {
        return true;
      }
    }
    return false;
  }
}
