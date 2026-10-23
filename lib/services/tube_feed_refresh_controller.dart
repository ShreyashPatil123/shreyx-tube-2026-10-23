/// Controls feed freshness lifecycle for all feed types (Home, Shorts, Up Next).
///
/// Key policy: Home feed ALWAYS refreshes on every cold app launch.
/// In-session resume uses a 30-minute staleness threshold.
/// Daily calendar change forces full feed regeneration.
class TubeFeedRefreshController {
  bool _isColdLaunch = true;
  DateTime? _lastHomeRefresh;
  String? _currentFeedEpochId;
  final Map<String, DateTime> _feedRefreshTimestamps = {};

  /// Returns true if Home feed needs a fresh generation.
  /// ALWAYS true on cold app launch (non-negotiable requirement).
  bool shouldRefreshHome() {
    // ALWAYS refresh on every cold app launch
    if (_isColdLaunch) {
      _isColdLaunch = false;
      return true;
    }

    final lastRefresh = _lastHomeRefresh;
    if (lastRefresh == null) return true;

    final now = DateTime.now();

    // Force refresh on new calendar day
    if (lastRefresh.day != now.day ||
        lastRefresh.month != now.month ||
        lastRefresh.year != now.year) {
      return true;
    }

    // In-session: refresh if stale (>30 minutes)
    if (now.difference(lastRefresh).inMinutes > 30) return true;

    return false;
  }

  /// Returns true if Shorts feed needs refresh
  bool shouldRefreshShorts() {
    final lastRefresh = _feedRefreshTimestamps['shorts'];
    if (lastRefresh == null) return true;

    final now = DateTime.now();
    if (lastRefresh.day != now.day) return true;
    if (now.difference(lastRefresh).inMinutes > 20) return true;

    return false;
  }

  /// Returns true if Up Next needs refresh for a given video context
  bool shouldRefreshUpNext(String videoId) {
    final key = 'up_next_$videoId';
    final lastRefresh = _feedRefreshTimestamps[key];
    if (lastRefresh == null) return true;

    // Up Next is video-specific, refresh if older than 15 minutes
    if (DateTime.now().difference(lastRefresh).inMinutes > 15) return true;

    return false;
  }

  /// Generate a unique feed epoch ID for daily rotation
  String generateFeedEpochId() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.millisecondsSinceEpoch}';
  }

  /// Get current feed epoch ID (creates new one if day changed)
  String getCurrentEpochId() {
    final now = DateTime.now();
    final todayPrefix =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    if (_currentFeedEpochId == null ||
        !_currentFeedEpochId!.startsWith(todayPrefix)) {
      _currentFeedEpochId = generateFeedEpochId();
    }
    return _currentFeedEpochId!;
  }

  /// Record a successful Home feed refresh
  void recordHomeRefresh({
    required int candidateCount,
    required int suppressedCount,
    required int freshCandidateCount,
    required Duration generationDuration,
  }) {
    _lastHomeRefresh = DateTime.now();
    _latestDiagnostics = FeedDiagnostics(
      feedType: 'home',
      generatedAt: _lastHomeRefresh!,
      epochId: getCurrentEpochId(),
      candidateCount: candidateCount,
      suppressedCount: suppressedCount,
      freshCandidateCount: freshCandidateCount,
      generationDuration: generationDuration,
    );
  }

  /// Record a successful feed refresh for any feed type
  void recordFeedRefresh(String feedType) {
    _feedRefreshTimestamps[feedType] = DateTime.now();
  }

  /// Mark an app resume event (doesn't reset cold launch flag)
  void onAppResumed() {
    // Cold launch flag stays false after first use
    // Just triggers staleness check on next shouldRefreshHome()
  }

  /// Discard all generations and diagnostics after a local-data reset.
  void reset() {
    _isColdLaunch = true;
    _lastHomeRefresh = null;
    _currentFeedEpochId = null;
    _feedRefreshTimestamps.clear();
    _latestDiagnostics = null;
  }

  void resetForTesting() => reset();

  // === Diagnostics ===
  FeedDiagnostics? _latestDiagnostics;
  FeedDiagnostics? get latestDiagnostics => _latestDiagnostics;
}

/// Diagnostic information about a feed generation cycle
class FeedDiagnostics {
  final String feedType;
  final DateTime generatedAt;
  final String epochId;
  final int candidateCount;
  final int suppressedCount;
  final int freshCandidateCount;
  final Duration generationDuration;

  const FeedDiagnostics({
    required this.feedType,
    required this.generatedAt,
    required this.epochId,
    required this.candidateCount,
    required this.suppressedCount,
    required this.freshCandidateCount,
    required this.generationDuration,
  });

  int get repeatedCandidatesRemoved => candidateCount > 0 ? suppressedCount : 0;
  double get freshnessRatio =>
      candidateCount > 0 ? freshCandidateCount / candidateCount : 0.0;

  @override
  String toString() =>
      'FeedDiagnostics($feedType: epoch=$epochId, candidates=$candidateCount, '
      'suppressed=$suppressedCount, fresh=$freshCandidateCount, '
      'duration=${generationDuration.inMilliseconds}ms)';
}
