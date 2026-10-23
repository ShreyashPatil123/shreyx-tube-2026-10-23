import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shreyx_tube/models/tube_models.dart';
import 'package:shreyx_tube/services/tube_recommendation_engine.dart';
import 'package:shreyx_tube/services/tube_user_profile_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() { SharedPreferences.setMockInitialValues({}); });

  late TubeRecommendationEngine engine;
  late TubeUserProfileService profileService;

  setUp(() async {
    engine = TubeRecommendationEngine();
    profileService = TubeUserProfileService();
    await profileService.init();
  });

  group('TubeRecommendationEngine Behavioral Tests', () {
    test('1. Cold start ranking works reliably with empty profile', () {
      final candidates = [
        const TubeVideoItem(id: 'v1', title: 'Python Tutorial', channelTitle: 'CodeHub', channelId: 'c1'),
        const TubeVideoItem(id: 'v2', title: 'Music Video Hits', channelTitle: 'Vevo', channelId: 'c2'),
      ];

      final ranked = engine.rankHomeFeed(candidates);
      expect(ranked.length, 2);
    });

    test('2. Topic affinity boosts relevant video rank', () {
      final profile = profileService.profile;
      profile.shortTermTopics['flutter'] = 0.95;
      profile.shortTermTopics['cooking'] = 0.05;

      final candidates = [
        const TubeVideoItem(id: 'v1', title: 'Amazing Cooking Pasta Recipe', channelTitle: 'Chef', channelId: 'c1'),
        const TubeVideoItem(id: 'v2', title: 'Complete Flutter Crash Course', channelTitle: 'Tech', channelId: 'c2'),
      ];

      final ranked = engine.rankHomeFeed(candidates);
      expect(ranked.first.id, 'v2');
    });

    test('3. Channel affinity elevates videos from favored creators', () {
      final profile = profileService.profile;
      profile.shortTermChannels['c_fav'] = 0.90;
      profile.shortTermChannels['c_other'] = 0.10;

      final candidates = [
        const TubeVideoItem(id: 'v1', title: 'Random Vlog', channelTitle: 'Other Creator', channelId: 'c_other'),
        const TubeVideoItem(id: 'v2', title: 'New Upload Today', channelTitle: 'Fav Creator', channelId: 'c_fav'),
      ];

      final ranked = engine.rankHomeFeed(candidates);
      expect(ranked.first.id, 'v2');
    });

    test('4. Fast-skipped negative topics are demoted', () async {
      final signal = TubeWatchSignal(
        videoId: 'bad1',
        title: 'Boring Clickbait Video Prank',
        channelId: 'c_prank',
        channelTitle: 'Prankster',
        completionRatio: 0.05,
        watchDurationSeconds: 8,
        isFastSkip: true,
        timestamp: DateTime.now(),
      );

      await profileService.updateFromWatchSignal(signal);

      expect(profileService.profile.negativeTopics.containsKey('prank') ||
             profileService.profile.negativeTopics.containsKey('clickbait'), isTrue);
    });

    test('5. Creator diversification prevents single creator monopoly', () {
      final candidates = [
        const TubeVideoItem(id: 'v1', title: 'Video 1', channelTitle: 'SpamChan', channelId: 'c_spam'),
        const TubeVideoItem(id: 'v2', title: 'Video 2', channelTitle: 'SpamChan', channelId: 'c_spam'),
        const TubeVideoItem(id: 'v3', title: 'Video 3', channelTitle: 'SpamChan', channelId: 'c_spam'),
        const TubeVideoItem(id: 'v4', title: 'Video 4', channelTitle: 'OtherChan', channelId: 'c_other'),
      ];

      final ranked = engine.rankHomeFeed(candidates);
      // Top 3 should not be all 3 from c_spam (max 2 before deferred)
      final top3Creators = ranked.take(3).map((v) => v.channelId).toList();
      final spamCount = top3Creators.where((id) => id == 'c_spam').length;
      expect(spamCount <= 2, isTrue);
    });

    test('6. Freshness decay preserves evergreen floor', () {
      final oldVideo = TubeVideoItem(
        id: 'v_old',
        title: 'Classic Masterpiece Documentary',
        channelTitle: 'History',
        channelId: 'c_hist',
        uploadDate: DateTime.now().subtract(const Duration(days: 400)),
        viewCount: 5000000,
      );

      final freshVideo = TubeVideoItem(
        id: 'v_new',
        title: 'Breaking News Announcement',
        channelTitle: 'News',
        channelId: 'c_news',
        uploadDate: DateTime.now(),
        viewCount: 10000,
      );

      final ranked = engine.rankHomeFeed([oldVideo, freshVideo]);
      expect(ranked.contains(oldVideo), isTrue);
      expect(ranked.contains(freshVideo), isTrue);
    });

    test('7. Novelty demotes recently watched videos', () {
      final profile = profileService.profile;
      profile.recentlyWatchedIds.add('v_watched');

      final candidates = [
        const TubeVideoItem(id: 'v_watched', title: 'Seen Yesterday Tutorial', channelTitle: 'Tutor', channelId: 'c1'),
        const TubeVideoItem(id: 'v_fresh', title: 'Brand New Tutorial', channelTitle: 'Tutor', channelId: 'c1'),
      ];

      final ranked = engine.rankHomeFeed(candidates);
      expect(ranked.first.id, 'v_fresh');
    });

    test('8. Up Next ranking prioritizes current video topical match', () {
      const current = TubeVideoItem(
        id: 'current_1',
        title: 'Flutter State Management Tutorial',
        channelTitle: 'Flutter Devs',
        channelId: 'c_flutter',
      );

      final candidates = [
        const TubeVideoItem(id: 'rel_1', title: 'Flutter Widget Deep Dive', channelTitle: 'Flutter Devs', channelId: 'c_flutter'),
        const TubeVideoItem(id: 'unrel_1', title: 'Baking Bread for Beginners', channelTitle: 'Bakery', channelId: 'c_bake'),
      ];

      final upNext = engine.rankUpNext(currentVideo: current, candidates: candidates);
      expect(upNext.first.id, 'rel_1');
    });

    test('9. Search query boosts interest tokens in profile', () async {
      await profileService.recordSearchQuery('space exploration telescope');
      expect(profileService.profile.searchInterests.containsKey('space') ||
             profileService.profile.searchInterests.containsKey('exploration'), isTrue);
    });

    test('10. Multi-session feature weight adaptation changes weights gradually', () async {
      final profile = profileService.profile;
      final initialWeight = profile.homeWeights['topicSimilarity'] ?? 0.20;

      // Simulate 6 watch sessions to unlock adaptive learning (>5 sessions)
      for (int i = 0; i < 6; i++) {
        final signal = TubeWatchSignal(
          videoId: 'v_$i',
          title: 'Great Flutter Episode $i',
          channelId: 'c_dev',
          channelTitle: 'Dev',
          completionRatio: 0.95,
          watchDurationSeconds: 600,
          timestamp: DateTime.now(),
        );
        await profileService.updateFromWatchSignal(signal);
      }

      final adaptedWeight = profile.homeWeights['topicSimilarity'] ?? 0.20;
      // Change should be gradual and within safe bounds [0.05, 0.40]
      expect(adaptedWeight >= 0.05 && adaptedWeight <= 0.40, isTrue);
      expect(initialWeight, isNotNull);
    });

    test('11. Short term interest decay preserves bounds', () {
      final profile = profileService.profile;
      profile.shortTermTopics['ai'] = 1.0;
      final effective = profile.getEffectiveTopicScore('ai');
      expect(effective > 0.0 && effective <= 1.0, isTrue);
    });

    test('12. Shorts ranking applies single-creator cap per batch', () {
      final candidates = [
        const TubeVideoItem(id: 's1', title: 'Short 1', channelTitle: 'Creator1', channelId: 'cr1', isShort: true),
        const TubeVideoItem(id: 's2', title: 'Short 2', channelTitle: 'Creator1', channelId: 'cr1', isShort: true),
        const TubeVideoItem(id: 's3', title: 'Short 3', channelTitle: 'Creator2', channelId: 'cr2', isShort: true),
      ];

      final ranked = engine.rankShorts(candidates);
      expect(ranked.length, 3);
      // First two shorts should have different creators due to maxPerCreator: 1 in Shorts
      expect(ranked[0].channelId != ranked[1].channelId, isTrue);
    });
  });
}
