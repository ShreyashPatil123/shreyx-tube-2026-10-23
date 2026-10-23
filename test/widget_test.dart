import 'package:flutter_test/flutter_test.dart';
import 'package:shreyx_tube/models/tube_models.dart';
import 'package:shreyx_tube/services/tube_cache_service.dart';
import 'package:shreyx_tube/services/tube_recommendation_service.dart';
import 'package:shreyx_tube/services/tube_search_service.dart';

void main() {
  group('ShreyX Tube Unit Tests', () {
    test('TubeSearchService parses URLs and text correctly', () {
      final searchService = TubeSearchService();

      // Normal text
      final textResult = searchService.parseInput('Python tutorial');
      expect(textResult.type, TubeInputType.textQuery);
      expect(textResult.rawInput, 'Python tutorial');

      // Video watch URL
      final watchUrl = searchService.parseInput('https://www.youtube.com/watch?v=aqz-KE-bpKQ');
      expect(watchUrl.type, TubeInputType.videoUrl);
      expect(watchUrl.extractedId, 'aqz-KE-bpKQ');

      // Short URL
      final youtuBe = searchService.parseInput('https://youtu.be/aqz-KE-bpKQ');
      expect(youtuBe.type, TubeInputType.videoUrl);
      expect(youtuBe.extractedId, 'aqz-KE-bpKQ');

      // Shorts URL
      final shorts = searchService.parseInput('https://youtube.com/shorts/aqz-KE-bpKQ');
      expect(shorts.type, TubeInputType.shortsUrl);
      expect(shorts.extractedId, 'aqz-KE-bpKQ');

      // Raw 11-char ID
      final rawId = searchService.parseInput('aqz-KE-bpKQ');
      expect(rawId.type, TubeInputType.videoUrl);
      expect(rawId.extractedId, 'aqz-KE-bpKQ');

      // Channel URL
      final channel = searchService.parseInput('https://www.youtube.com/@Veritasium');
      expect(channel.type, TubeInputType.channelUrl);
      expect(channel.extractedId, 'Veritasium');
    });

    test('TubeVideoItem formats durations, views, and flags properly', () {
      const video = TubeVideoItem(
        id: 'test1234567',
        title: 'Test Video',
        channelTitle: 'Test Channel',
        channelId: 'ch123',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        durationSeconds: 3723, // 1h 2m 3s
        viewCount: 1540000,
        isShort: true,
        isMembersOnly: true,
      );

      expect(video.formattedDuration, '1:02:03');
      expect(video.formattedViews, '1.5M views');
      expect(video.isShort, isTrue);
      expect(video.isMembersOnly, isTrue);
      expect(video.watchUrl, 'https://www.youtube.com/watch?v=test1234567');

      // Published timing and relative date tests
      final videoWithTiming = video.copyWith(
        publishedTimeText: '3 days ago',
      );
      expect(videoWithTiming.formattedDate, '3 days ago');
      expect(videoWithTiming.effectiveUploadDate, isNotNull);
      expect(DateTime.now().difference(videoWithTiming.effectiveUploadDate!).inDays, 3);

      expect(TubeVideoItem.parseRelativeTime('Streamed 2 days ago'), isNotNull);
      expect(TubeVideoItem.parseRelativeTime('5 hours ago'), isNotNull);
      expect(TubeVideoItem.parseRelativeTime('1 year ago'), isNotNull);

      // View count parser tests
      expect(TubeVideoItem.parseViewCount('1.4M views'), 1400000);
      expect(TubeVideoItem.parseViewCount('850K views'), 850000);
      expect(TubeVideoItem.parseViewCount('2.5B views'), 2500000000);
      expect(TubeVideoItem.parseViewCount('12,345 views'), 12345);

      // JSON roundtrip
      final json = videoWithTiming.toJson();
      final roundtrip = TubeVideoItem.fromJson(json);
      expect(roundtrip.id, video.id);
      expect(roundtrip.title, video.title);
      expect(roundtrip.publishedTimeText, '3 days ago');
      expect(roundtrip.durationSeconds, video.durationSeconds);
      expect(roundtrip.isMembersOnly, isTrue);
    });

    test('TubeRecommendationService scores Up Next based on current video keywords', () {
      final recService = TubeRecommendationService();

      const currentVideo = TubeVideoItem(
        id: 'curr_vid',
        title: 'Flutter Advanced State Management Architecture',
        channelTitle: 'Flutter Devs',
        channelId: 'ch_flutter',
        thumbnailUrl: '',
        durationSeconds: 600,
      );

      final candidates = [
        const TubeVideoItem(
          id: 'v1',
          title: 'Cooking Italian Pizza at Home',
          channelTitle: 'Chef John',
          channelId: 'c1',
          thumbnailUrl: '',
          durationSeconds: 400,
        ),
        const TubeVideoItem(
          id: 'v2',
          title: 'Flutter Architecture Best Practices & Testing',
          channelTitle: 'Flutter Devs',
          channelId: 'ch_flutter',
          thumbnailUrl: '',
          durationSeconds: 500,
        ),
      ];

      final ranked = recService.rankUpNext(currentVideo: currentVideo, candidates: candidates);
      expect(ranked.length, 2);
      // v2 should be ranked first because it matches channel and title keywords
      expect(ranked.first.id, 'v2');
    });

    test('TubeMemoryCache caches and respects TTL eviction', () {
      final cache = TubeMemoryCache<String>(
        defaultTtl: const Duration(milliseconds: 50),
        maxCapacity: 2,
      );

      cache.set('k1', 'val1');
      cache.set('k2', 'val2');
      expect(cache.get('k1'), 'val1');
      expect(cache.get('k2'), 'val2');

      // Capacity eviction
      cache.set('k3', 'val3');
      expect(cache.size, 2);
    });

    test('TubeWatchSignal serializes correctly', () {
      final signal = TubeWatchSignal(
        videoId: 'v123',
        channelTitle: 'Tech Channel',
        completionRatio: 0.92,
        watchDurationSeconds: 120,
        isRewatch: true,
        isFastSkip: false,
        timestamp: DateTime(2026, 9, 23),
      );

      final map = signal.toJson();
      final restored = TubeWatchSignal.fromJson(map);

      expect(restored.videoId, 'v123');
      expect(restored.channelTitle, 'Tech Channel');
      expect(restored.completionRatio, 0.92);
      expect(restored.isRewatch, isTrue);
    });

    test('TubeHistoryItem computes completion and resume availability', () {
      const video = TubeVideoItem(
        id: 'v1',
        title: 'Video',
        channelTitle: 'Channel',
        channelId: 'c1',
        thumbnailUrl: '',
        durationSeconds: 100,
      );

      final item = TubeHistoryItem(
        video: video,
        watchedAt: DateTime.now(),
        positionMs: 50000, // 50 seconds in (50%)
        durationMs: 100000,
      );

      expect(item.completionRatio, 0.5);
      expect(item.isResumeAvailable, isTrue);
      expect(item.formattedResumePosition, '00:50');
    });
  });
}
