import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shreyx_tube/models/tube_models.dart';
import 'package:shreyx_tube/providers/tube_queue_controller.dart';
import 'package:shreyx_tube/services/tube_feed_refresh_controller.dart';
import 'package:shreyx_tube/theme/tube_theme.dart';

void main() {
  group('TubeFeedRefreshController Tests', () {
    late TubeFeedRefreshController controller;

    setUp(() {
      controller = TubeFeedRefreshController();
      controller.resetForTesting();
    });

    test('Home feed ALWAYS refreshes on cold app launch', () {
      expect(controller.shouldRefreshHome(), isTrue,
          reason: 'Cold launch must always trigger fresh feed generation');

      // After first check, it is no longer cold launch
      controller.recordHomeRefresh(
        candidateCount: 40,
        suppressedCount: 5,
        freshCandidateCount: 25,
        generationDuration: const Duration(milliseconds: 320),
      );

      expect(controller.shouldRefreshHome(), isFalse,
          reason: 'Immediately after refresh within same session, feed should not re-trigger');
    });

    test('Feed diagnostics accurately records generation statistics', () {
      controller.recordHomeRefresh(
        candidateCount: 50,
        suppressedCount: 10,
        freshCandidateCount: 35,
        generationDuration: const Duration(milliseconds: 450),
      );

      final diag = controller.latestDiagnostics;
      expect(diag, isNotNull);
      expect(diag!.feedType, 'home');
      expect(diag.candidateCount, 50);
      expect(diag.suppressedCount, 10);
      expect(diag.freshCandidateCount, 35);
      expect(diag.freshnessRatio, 0.7); // 35 / 50
      expect(diag.repeatedCandidatesRemoved, 10);
    });

    test('Daily epoch changes per calendar day', () {
      final epochId = controller.getCurrentEpochId();
      final now = DateTime.now();
      final expectedPrefix =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      expect(epochId.startsWith(expectedPrefix), isTrue);
    });
  });

  group('TubeQueueController Tests', () {
    late TubeQueueController queue;

    const v1 = TubeVideoItem(
      id: 'vid1',
      title: 'Video 1',
      channelTitle: 'Channel 1',
      channelId: 'ch1',
    );

    const v2 = TubeVideoItem(
      id: 'vid2',
      title: 'Video 2',
      channelTitle: 'Channel 2',
      channelId: 'ch2',
    );

    const v3 = TubeVideoItem(
      id: 'vid3',
      title: 'Video 3',
      channelTitle: 'Channel 3',
      channelId: 'ch3',
    );

    setUp(() {
      queue = TubeQueueController();
    });

    test('setCurrentVideo sets video at current index', () {
      queue.setCurrentVideo(v1);
      expect(queue.queueLength, 1);
      expect(queue.currentIndex, 0);
      expect(queue.currentVideo?.id, 'vid1');
    });

    test('addToQueue appends without duplicates', () {
      queue.setCurrentVideo(v1);
      queue.addToQueue(v2);
      queue.addToQueue(v2); // duplicate should be ignored

      expect(queue.queueLength, 2);
      expect(queue.queue[1].id, 'vid2');
    });

    test('playNext inserts video immediately after current index', () {
      queue.setCurrentVideo(v1);
      queue.addToQueue(v3);
      queue.playNext(v2);

      expect(queue.queueLength, 3);
      expect(queue.queue[0].id, 'vid1');
      expect(queue.queue[1].id, 'vid2'); // inserted next
      expect(queue.queue[2].id, 'vid3');
    });

    test('advanceToNext and goToPrevious update current index', () {
      queue.setCurrentVideo(v1);
      queue.addToQueue(v2);

      expect(queue.hasNext, isTrue);
      final next = queue.advanceToNext();
      expect(next?.id, 'vid2');
      expect(queue.currentIndex, 1);
      expect(queue.hasPrevious, isTrue);

      final prev = queue.goToPrevious();
      expect(prev?.id, 'vid1');
      expect(queue.currentIndex, 0);
    });

    test('removeFromQueue properly decrements index when removing item before current', () {
      queue.setCurrentVideo(v1);
      queue.addToQueue(v2);
      queue.addToQueue(v3);

      // Advance to v3 (index 2)
      queue.advanceToNext(); // index 1 (v2)
      queue.advanceToNext(); // index 2 (v3)
      expect(queue.currentIndex, 2);

      // Remove v1 (index 0)
      queue.removeFromQueue(0);
      expect(queue.queueLength, 2);
      expect(queue.currentIndex, 1,
          reason: 'Removing an item before currentIndex must decrement currentIndex');
      expect(queue.currentVideo?.id, 'vid3');
    });

    test('reorder updates list order and tracks current index', () {
      queue.setCurrentVideo(v1);
      queue.addToQueue(v2);
      queue.addToQueue(v3);

      // Current is v1 at 0. Move v3 (index 2) to 0.
      queue.reorder(2, 0);
      expect(queue.queue[0].id, 'vid3');
      expect(queue.queue[1].id, 'vid1');
      expect(queue.queue[2].id, 'vid2');
      expect(queue.currentIndex, 1,
          reason: 'v1 moved from 0 to 1, currentIndex must update accordingly');
    });
  });

  group('TubeTheme Tests', () {
    test('TubeTheme provides YouTube dark surface hierarchy and valid ThemeData', () {
      expect(TubeTheme.background, const Color(0xFF0F0F0F));
      expect(TubeTheme.surface, const Color(0xFF1A1A1A));
      expect(TubeTheme.surfaceVariant, const Color(0xFF272727));
      expect(TubeTheme.progressRed, const Color(0xFFFF0000));

      final themeData = TubeTheme.buildThemeData();
      expect(themeData.brightness, Brightness.dark);
      expect(themeData.scaffoldBackgroundColor, TubeTheme.background);
      expect(themeData.colorScheme.surface, TubeTheme.surface);
    });
  });
}
