import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shreyx_tube/services/tube_session_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shreyx_tube/models/tube_models.dart';
import 'package:shreyx_tube/main.dart';
import 'package:flutter/foundation.dart';
import 'package:shreyx_tube/providers/tube_player_provider.dart';
import 'package:shreyx_tube/providers/tube_shorts_controller.dart';
import 'package:shreyx_tube/screens/tube_onboarding_screen.dart';
import 'package:shreyx_tube/screens/tube_privacy_settings_screen.dart';
import 'package:shreyx_tube/services/tube_channel_service.dart';
import 'package:shreyx_tube/services/tube_database_service.dart';
import 'package:shreyx_tube/services/tube_home_feed_service.dart';
import 'package:shreyx_tube/services/tube_innertube_client.dart';
import 'package:shreyx_tube/services/tube_local_reset_service.dart';
import 'package:shreyx_tube/services/tube_recommendation_engine.dart';
import 'package:shreyx_tube/services/tube_storage_service.dart';
import 'package:shreyx_tube/services/tube_shorts_service.dart';
import 'package:shreyx_tube/services/tube_user_profile_service.dart';
import 'package:shreyx_tube/widgets/tube_mini_player.dart';
import 'package:shreyx_tube/widgets/tube_player_gestures.dart';

class _Paths extends PathProviderPlatform {
  final String path;
  _Paths(this.path);
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Map<String, dynamic> _card(String id,
        {String title = 'Public video', bool shorts = false}) =>
    {
      'videoId': id,
      'title': {'simpleText': title},
      'ownerText': {
        'runs': [
          {
            'text': 'Creator',
            'navigationEndpoint': {
              'browseEndpoint': {'browseId': 'creator'}
            }
          }
        ]
      },
      if (shorts)
        'navigationEndpoint': {
          'commandMetadata': {
            'webCommandMetadata': {'url': '/shorts/$id'}
          }
        },
    };
Map<String, dynamic> _feed(List<Map<String, dynamic>> cards, {String? token}) =>
    {
      'contents': {
        'items': [
          for (final c in cards) {'videoRenderer': c},
          if (token != null)
            {
              'continuationItemRenderer': {
                'continuationEndpoint': {
                  'continuationCommand': {'token': token}
                }
              }
            }
        ]
      }
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  final db = TubeDatabaseService();
  final storage = TubeStorageService();
  final profile = TubeUserProfileService();
  late Directory root;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('tube-upgrade-');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(root.path);
    PathProviderPlatform.instance = _Paths(root.path);
    SharedPreferences.setMockInitialValues({});
    await db.init();
    await storage.init();
    await profile.init();
    for (final name in [
      'com.shreyx.tube/player_channel',
      'com.shreyx.tube/shorts_player_channel'
    ]) {
      messenger.setMockMethodCallHandler(
          MethodChannel(name), (_) async => true);
    }
  });
  setUp(() async {
    await db.clearAllData();
    await storage.clearAllLocalData();
    profile.reset();
    TubeRecommendationEngine().reset();
    TubeHomeFeedService().reset();
  });
  tearDownAll(() async {
    await (await db.database).close();
    await root.delete(recursive: true);
  });

  test('SQLite v2 migration indexes exist; no destructive schema reset',
      () async {
    final rows = await (await db.database)
        .rawQuery("SELECT name FROM sqlite_master WHERE type='index'");
    expect(rows.map((r) => r['name']),
        containsAll(['impressions_shown', 'signals_created']));
  });
  test(
      'First launch is incomplete, successful save persists identity/preferences/completion',
      () async {
    await profile.loadIdentity();
    expect(profile.onboardingCompleted, isFalse);
    await profile.saveIdentity({
      'displayName': 'Shrey',
      'username': 'shrey',
      'feedTypes': ['Music'],
      'interests': ['Space']
    }, complete: true);
    await profile.loadIdentity();
    expect(profile.onboardingCompleted, isTrue);
    expect(profile.displayName, 'Shrey');
    expect(profile.interests, ['Space']);
    expect(profile.profile.getEffectiveTopicScore('space'), greaterThan(0));
  });
  test('Editing profile preserves watch history and learned interests',
      () async {
    await storage.saveWatchPosition(
        const TubeVideoItem(
            id: 'watched',
            title: 'Video',
            channelId: 'c',
            channelTitle: 'Creator'),
        35000,
        50000);
    profile.profile.shortTermTopics['coding'] = 0.9;
    await profile
        .saveIdentity({'displayName': 'Edited', 'username': 'new_name'});
    expect(storage.getWatchHistory().single.video.id, 'watched');
    expect(profile.profile.shortTermTopics['coding'], 0.9);
    expect((await db.getProfileData('identity'))!['username'], 'new_name');
  });
  test(
      'Failed SQLite completion rolls back identity and never completes onboarding',
      () async {
    final database = await db.database;
    await database.execute(
        "CREATE TRIGGER reject_completion BEFORE INSERT ON settings WHEN NEW.key='onboarding_completed' BEGIN SELECT RAISE(ABORT, 'save failed'); END");
    try {
      await expectLater(
          profile.saveIdentity({'displayName': 'Fail'}, complete: true),
          throwsA(isA<DatabaseException>()));
      expect(await db.getSetting('onboarding_completed'), isNull);
      expect(await db.getProfileData('identity'), isNull);
      expect(profile.onboardingCompleted, isFalse);
    } finally {
      await database.execute('DROP TRIGGER reject_completion');
    }
  });
  test('Invalid names/handles do not commit onboarding', () async {
    await expectLater(
        profile.saveIdentity({'displayName': ' '}, complete: true),
        throwsArgumentError);
    await expectLater(
        profile.saveIdentity({'displayName': 'Name', 'username': 'bad handle'},
            complete: true),
        throwsArgumentError);
    expect(await db.getSetting('onboarding_completed'), isNull);
  });
  testWidgets('Onboarding validates a required name and offers optional skip',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TubeOnboardingScreen()));
    await tester.scrollUntilVisible(find.text('Start watching'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Start watching'));
    await tester.pump();
    expect(profile.onboardingCompleted, isFalse);
    await tester.scrollUntilVisible(find.text('Display name'), -400,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Enter a display name'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test('Local watch completion and rewatch adapt topic/creator scores',
      () async {
    await profile.updateFromWatchSignal(TubeWatchSignal(
        videoId: 'x',
        title: 'Space telescope',
        channelId: 'c',
        channelTitle: 'Science',
        completionRatio: 0.95,
        watchDurationSeconds: 100,
        timestamp: DateTime.now()));
    expect(profile.profile.shortTermTopics['space'], greaterThan(0));
    expect(profile.profile.shortTermChannels['c'], greaterThan(0));
    final before = profile.profile.shortTermChannels['c']!;
    await profile.updateFromWatchSignal(TubeWatchSignal(
        videoId: 'x',
        title: 'Space telescope',
        channelId: 'c',
        channelTitle: 'Science',
        completionRatio: 0.1,
        watchDurationSeconds: 20,
        isRewatch: true,
        timestamp: DateTime.now()));
    expect(profile.profile.shortTermChannels['c'], greaterThan(before));
  });
  test('Repeated skips demote creators and topics', () async {
    for (var i = 0; i < 4; i++) {
      await profile.updateFromWatchSignal(TubeWatchSignal(
          videoId: '$i',
          title: 'Clickbait pranks',
          channelId: 'c',
          channelTitle: 'Pranks',
          completionRatio: 0.01,
          watchDurationSeconds: 2,
          isFastSkip: true,
          timestamp: DateTime.now()));
    }
    expect(profile.profile.negativeChannels['c'], greaterThan(0.5));
  });
  test('Incognito records neither signals, searches nor impressions', () async {
    await storage.setIncognito(true);
    await profile.recordSearchQuery('space telescope');
    await db.recordImpressions(['x'], 'home');
    await storage.recordWatchSignal(TubeWatchSignal(
        videoId: 'x',
        channelTitle: '',
        completionRatio: 1,
        watchDurationSeconds: 50,
        timestamp: DateTime.now()));
    expect(profile.profile.searchInterests, isEmpty);
    expect(storage.getWatchSignals(), isEmpty);
    expect(await db.getRecentlyShownIds(), isEmpty);
  });
  test('Paused watch/search history cannot train personalization', () async {
    await storage.setPauseWatchHistory(true);
    await storage.setPauseSearchHistory(true);
    await profile.recordSearchQuery('space telescope');
    await profile.updateFromWatchSignal(TubeWatchSignal(
        videoId: 'x',
        title: 'Space',
        channelId: 'c',
        channelTitle: '',
        completionRatio: 1,
        watchDurationSeconds: 50,
        timestamp: DateTime.now()));
    expect(profile.profile.shortTermTopics, isEmpty);
    expect(profile.profile.searchInterests, isEmpty);
  });
  test(
      'Paused personalization ignores saved interests and public order survives',
      () async {
    profile.profile.shortTermTopics['space'] = 1;
    await storage.setPausePersonalization(true);
    const items = [
      TubeVideoItem(
          id: 'a', title: 'Cooking', channelId: 'a', channelTitle: ''),
      TubeVideoItem(id: 'b', title: 'Space', channelId: 'b', channelTitle: '')
    ];
    expect(TubeRecommendationEngine().rankHomeFeed(items).map((v) => v.id),
        ['a', 'b']);
    expect(
        TubeRecommendationEngine()
            .rankUpNext(currentVideo: items.first, candidates: items)
            .map((v) => v.id),
        ['a', 'b']);
  });
  test('Paused search ignores legacy mixed search evidence without deleting it',
      () async {
    profile.profile.shortTermTopics['space'] = 1;
    profile.profile.searchInterests['space'] = 1;
    profile.profile.shortTermTopics['cooking'] = 0.4;
    const items = [
      TubeVideoItem(
          id: 'a', title: 'Cooking', channelId: 'a', channelTitle: ''),
      TubeVideoItem(id: 'b', title: 'Space', channelId: 'b', channelTitle: ''),
    ];
    expect(TubeRecommendationEngine().rankHomeFeed(items).first.id, 'b');
    await storage.setPauseSearchHistory(true);
    expect(TubeRecommendationEngine().rankHomeFeed(items).first.id, 'a');
    expect(profile.profile.shortTermTopics['space'], 1);
    expect(profile.profile.searchInterests['space'], 1);
  });
  test('Preferences seed public candidate queries and boost selected topics',
      () async {
    await profile.saveIdentity({
      'displayName': 'User',
      'interests': ['Space'],
      'feedTypes': ['Regular videos']
    }, complete: true);
    final queries = <String>[];
    final feed = TubeHomeFeedService.withClient(
        TubeInnertubeClient.withClient(MockClient((request) async {
      final body = jsonDecode(request.body);
      if (body['query'] != null) queries.add(body['query']);
      return http.Response(
          jsonEncode(body['query'] != null
              ? _feed([_card('space', title: 'Space telescope')])
              : _feed([_card('other', title: 'Cooking recipes')])),
          200);
    })));
    final result =
        await feed.getCategoryFeed('Recommended', forceRefresh: true);
    expect(queries, contains('Space'));
    expect(result.first.id, 'space');
  });
  test(
      'Consumed IDs and persisted Home impressions suppress candidates and trigger refill',
      () async {
    await db.insertWatchSignal({
      'video_id': 'used',
      'watch_duration_ms': 45000,
      'completion_ratio': 0.5,
      'created_at': 1
    });
    await db.recordImpressions(['shown'], 'home');
    var calls = 0;
    final feed = TubeHomeFeedService.withClient(
        TubeInnertubeClient.withClient(MockClient((request) async {
      calls++;
      return http.Response(
          jsonEncode(calls == 1
              ? _feed([_card('used'), _card('shown')], token: 'next')
              : _feed([_card('fresh'), _card('fresh')])),
          200);
    })));
    expect(
        (await feed.getCategoryFeed('Recommended', forceRefresh: true))
            .map((v) => v.id),
        ['fresh']);
    expect(calls, 2);
    expect(feed.hasMore('Recommended'), isFalse);
    final relaunched = TubeHomeFeedService.withClient(
        TubeInnertubeClient.withClient(MockClient((_) async =>
            http.Response(jsonEncode(_feed([_card('fresh')])), 200))));
    expect(await relaunched.getCategoryFeed('Recommended', forceRefresh: true),
        isEmpty);
  });
  test('Unknown upload dates stay unknown and real recent dates rank higher',
      () {
    const unknown = TubeVideoItem(
        id: 'unknown', title: 'Topic', channelId: 'a', channelTitle: '');
    final recent = TubeVideoItem(
        id: 'recent',
        title: 'Topic',
        channelId: 'b',
        channelTitle: '',
        uploadDate: DateTime.now().subtract(const Duration(hours: 1)));
    expect(unknown.effectiveUploadDate, isNull);
    expect(TubeRecommendationEngine().rankHomeFeed([unknown, recent]).first.id,
        'recent');
  });
  test('Refresh rejects stale response without replacing current cursor',
      () async {
    final old = Completer<http.Response>();
    var calls = 0;
    final feed = TubeHomeFeedService.withClient(
        TubeInnertubeClient.withClient(MockClient((_) async {
      calls++;
      if (calls == 1) return old.future;
      return http.Response(jsonEncode(_feed([_card('new')])), 200);
    })));
    final stale = feed.getCategoryFeed('Recommended', forceRefresh: true);
    await Future<void>.delayed(Duration.zero);
    expect(
        (await feed.getCategoryFeed('Recommended', forceRefresh: true))
            .single
            .id,
        'new');
    old.complete(http.Response(
        jsonEncode(_feed([_card('old')], token: 'old-token')), 200));
    expect(await stale, isEmpty);
    expect(feed.hasMore('Recommended'), isFalse);
  });
  test('Reset epoch discards pending feed response', () async {
    final response = Completer<http.Response>();
    final feed = TubeHomeFeedService.withClient(
        TubeInnertubeClient.withClient(MockClient((_) => response.future)));
    final pending = feed.getCategoryFeed('Recommended', forceRefresh: true);
    await Future<void>.delayed(Duration.zero);
    feed.reset();
    response.complete(http.Response(
        jsonEncode(_feed([_card('stale')], token: 'stale')), 200));
    expect(await pending, isEmpty);
    expect(feed.hasMore('Recommended'), isFalse);
  });
  testWidgets('Down swipe on expanded video collapses once', (tester) async {
    var collapsed = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 300,
                height: 250,
                child: TubePlayerGestures(
                    onSingleTap: () {},
                    onDoubleTapLeft: () {},
                    onDoubleTapRight: () {},
                    onCollapse: () => collapsed++,
                    child: const ColoredBox(color: Colors.black))))));
    await tester.fling(
        find.byType(TubePlayerGestures), const Offset(0, 160), 700);
    await tester.pump();
    expect(collapsed, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Mini swipe-up and title tap expand, play/pause tap does not',
      (tester) async {
    var expanded = 0;
    final player = TubePlayerProvider();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: player,
        child: MaterialApp(
            home: Scaffold(
                body: Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                        width: 300,
                        child: TubeMiniPlayer(
                            onExpand: () => expanded++,
                            videoSurface:
                                const ColoredBox(color: Colors.black))))))));
    await tester.fling(find.byKey(const ValueKey('floating-player')),
        const Offset(0, -120), 700);
    await tester.pump();
    expect(expanded, 1);
    await tester.tap(find.text('Playing video'));
    await tester.pump();
    expect(expanded, 2);
    await tester.tap(find.byTooltip('Play/Pause'));
    await tester.pump();
    expect(expanded, 2);
    await tester.pumpWidget(const SizedBox());
    player.dispose();
  });
  test('Profile and persisted suppression disappear after complete reset',
      () async {
    await profile.saveIdentity({
      'displayName': 'User',
      'interests': ['Space']
    }, complete: true);
    await const FlutterSecureStorage().write(
        key: 'tube_google_connection_v1',
        value: '{"accountId":"reset-fixture"}');
    await db.recordImpressions(['seen'], 'home');
    await storage.addSearchQuery('secret query');
    final files = Directory('${root.path}/shreyx_downloads');
    await files.create();
    await File('${files.path}/video.mp4').writeAsBytes([1, 2, 3]);
    final outside = File('${root.path}/unrelated.txt');
    await outside.writeAsString('keep');
    await TubeLocalResetService.clearStores();
    expect(TubeSessionService().isLoggedIn, isFalse);
    expect(TubeSessionService().getAuthHeaders(), isEmpty);
    expect(
        await const FlutterSecureStorage()
            .read(key: 'tube_google_connection_v1'),
        isNull);
    expect(await files.exists(), isFalse);
    expect(await outside.readAsString(), 'keep');
    expect((await db.getStorageBreakdown()).values.every((count) => count == 0),
        isTrue);
    expect(storage.getSearchHistory(), isEmpty);
    expect(profile.profile.topicScores, isEmpty);
    await profile.loadIdentity();
    expect(profile.onboardingCompleted, isFalse);
  });
  testWidgets('Cancel destructive confirmation preserves local data',
      (tester) async {
    await storage.addSearchQuery('keep');
    await tester
        .pumpWidget(const MaterialApp(home: TubePrivacySettingsScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Clear All Local Data'), 400);
    await tester.tap(find.text('Clear All Local Data'));
    await tester.pumpAndSettle();
    expect(find.text('Clear all local data?'), findsOneWidget);
    expect(find.text(tubeResetMessage), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(storage.getSearchHistory(), ['keep']);
    await tester.pumpWidget(const SizedBox());
  });
  test(
      'Native session restoration preserves position without stream extraction/load',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.shreyx.tube/player_channel'), (call) async {
      calls.add(call.method);
      return {
        'hasMedia': true,
        'videoId': 'abcdefghijk',
        'title': 'Session',
        'channelTitle': 'Creator',
        'positionMs': 42000,
        'durationMs': 120000,
        'isPlaying': true
      };
    });
    final player = TubePlayerProvider();
    await player.restoreNativePlayback();
    expect(player.position.inSeconds, 42);
    expect(player.isPlaying, isTrue);
    expect(player.isExpanded, isFalse);
    for (var i = 0; i < 5; i++) {
      player.expandPlayer();
      player.collapsePlayer();
    }
    expect(player.position.inSeconds, 42);
    expect(calls, ['getStatus']);
    await player.resetLocalState();
    await player.flushSignals();
    player.dispose();
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.shreyx.tube/player_channel'),
        (_) async => true);
  });
  test('Channel tabs are limited to public endpoints and no invented handle',
      () async {
    final service = TubeChannelService.withClient(
        TubeInnertubeClient.withClient(MockClient((_) async => http.Response(
            jsonEncode({
              'metadata': {
                'channelMetadataRenderer': {
                  'externalId': 'UCtest',
                  'title': 'Creator',
                  'description': 'Real description'
                }
              },
              'contents': {
                'twoColumnBrowseResultsRenderer': {
                  'tabs': [
                    {
                      'tabRenderer': {
                        'title': 'Videos',
                        'endpoint': {
                          'browseEndpoint': {'params': 'videos'}
                        }
                      }
                    },
                    {
                      'tabRenderer': {'title': 'Posts'}
                    }
                  ]
                }
              }
            }),
            200))));
    final info = await service.getChannel('UCtest');
    expect(info.handle, isEmpty);
    expect(info.description, 'Real description');
    expect(service.availableTabs('UCtest'), {'Home', 'Videos'});
  });
  test(
      'Channel Shorts uses dedicated endpoint; duration does not relabel regulars',
      () async {
    final service = TubeChannelService.withClient(
        TubeInnertubeClient.withClient(MockClient((request) async {
      final body = jsonDecode(request.body);
      return http.Response(
          jsonEncode(body['params'] == 'shorts'
              ? _feed([_card('short', shorts: true), _card('regular')])
              : {
                  'metadata': {
                    'channelMetadataRenderer': {'title': 'Creator'}
                  },
                  'contents': {
                    'tabs': [
                      {
                        'tabRenderer': {
                          'title': 'Shorts',
                          'endpoint': {
                            'browseEndpoint': {'params': 'shorts'}
                          }
                        }
                      }
                    ]
                  }
                }),
          200);
    })));
    expect((await service.getChannelShorts('channel')).map((s) => s.item.id),
        ['short']);
  });
  test('Channel Live preserves public archived/live cards and membership flags',
      () async {
    final client =
        TubeInnertubeClient.withClient(MockClient((_) async => http.Response(
            jsonEncode(_feed([
              {
                ..._card('restricted'),
                'badges': [
                  {
                    'metadataBadgeRenderer': {
                      'label': 'Members only',
                      'style': 'BADGE_STYLE_TYPE_MEMBERS_ONLY'
                    }
                  }
                ]
              },
              {
                ..._card('live'),
                'badges': [
                  {
                    'metadataBadgeRenderer': {
                      'label': 'LIVE',
                      'style': 'BADGE_STYLE_TYPE_LIVE_NOW'
                    }
                  }
                ]
              },
            ])),
            200)));
    final result = await client.channelSection('channel', 'live');
    expect(result.page.items.first.isMembersOnly, isTrue);
    expect(result.page.items.last.isLive, isTrue);
  });
  test('Public playlist cards expose a real ID and no fabricated count',
      () async {
    final client =
        TubeInnertubeClient.withClient(MockClient((_) async => http.Response(
            jsonEncode({
              'contents': {
                'items': [
                  {
                    'gridPlaylistRenderer': {
                      'playlistId': 'PLreal',
                      'title': {'simpleText': 'Public list'}
                    }
                  }
                ]
              }
            }),
            200)));
    final result = await client.channelSection('channel', 'playlists');
    expect(result.playlists.single.id, 'PLreal');
    expect(result.playlists.single.videoCount, 0);
  });
  test(
      'Clicked channel Shorts seed preserves selected item and gates membership before extraction',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.shreyx.tube/shorts_player_channel'),
        (call) async {
      calls.add(call.method);
      return true;
    });
    final controller = TubeShortsController();
    controller.selectChannelShorts([
      const TubeVideoItem(
          channelId: 'creator',
          id: 'first',
          title: 'First',
          channelTitle: 'Creator',
          thumbnailUrl: '',
          isShort: true),
      const TubeVideoItem(
          channelId: 'creator',
          id: 'restricted',
          title: 'Restricted',
          channelTitle: 'Creator',
          thumbnailUrl: '',
          isShort: true,
          isMembersOnly: true),
    ], 1);
    expect(controller.activeShort!.id, 'restricted');
    controller.activateScreen();
    await Future<void>.delayed(Duration.zero);
    expect(controller.errorMessage, contains('Members-only'));
    expect(calls, isNot(contains('loadMedia')));
    await controller.fetchMoreShorts();
    expect(controller.shorts.length, 2);
    await controller.resetLocalState();
    expect(controller.shorts, isEmpty);
    controller.dispose();
  });
  test(
      'Channel section retries failed pages and appends/deduplicates continuation',
      () async {
    var fail = true;
    final client = TubeInnertubeClient.withClient(MockClient((request) async {
      final body = jsonDecode(request.body);
      if (body['params'] == 'shorts' || body['continuation'] != null) {
        if (fail) return http.Response('Unavailable', 503);
        return http.Response(
            jsonEncode(body['continuation'] == 'next'
                ? _feed([_card('a', shorts: true), _card('b', shorts: true)])
                : _feed([_card('a', shorts: true)], token: 'next')),
            200);
      }
      return http.Response(
          jsonEncode({
            'contents': {
              'tabs': [
                {
                  'tabRenderer': {
                    'title': 'Shorts',
                    'endpoint': {
                      'browseEndpoint': {'params': 'shorts'}
                    }
                  }
                }
              ]
            }
          }),
          200);
    }));
    final service = TubeChannelService.withClient(client);
    await expectLater(service.getChannelShorts('creator'), throwsStateError);
    fail = false;
    expect((await service.getChannelShorts('creator')).map((v) => v.item.id),
        ['a']);
    expect(service.hasMoreSection('creator', 'Shorts'), isTrue);
    expect(
        (await service.getChannelShorts('creator', more: true))
            .map((v) => v.item.id),
        ['a', 'b']);
    expect(service.hasMoreSection('creator', 'Shorts'), isFalse);
  });
  test('Reset prevents pending channel metadata from restoring cleared caches',
      () async {
    final response = Completer<http.Response>();
    var count = 0;
    final service = TubeChannelService.withClient(
        TubeInnertubeClient.withClient(MockClient((_) async {
      ++count;
      if (count == 1) return response.future;
      return http.Response(
          jsonEncode({
            'metadata': {
              'channelMetadataRenderer': {'title': 'Fresh'}
            }
          }),
          200);
    })));
    final pending = service.getChannel('creator');
    await Future<void>.delayed(Duration.zero);
    service.clearCache();
    response.complete(http.Response(
        jsonEncode({
          'metadata': {
            'channelMetadataRenderer': {'title': 'Old'}
          }
        }),
        200));
    await pending;
    expect((await service.getChannel('creator')).title, 'Fresh');
    expect(count, 2);
  });
  test('Known members-only Shorts are not prefetched', () async {
    var extractions = 0;
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.shreyx.tube/native_extractor'), (_) async {
      ++extractions;
      return null;
    });
    await TubeShortsService().prefetchNextShort(const TubeVideoItem(
        id: 'restricted',
        title: 'Restricted',
        channelId: 'creator',
        channelTitle: 'Creator',
        thumbnailUrl: '',
        isShort: true,
        isMembersOnly: true));
    expect(extractions, 0);
  });
  test('Normal playback cancels pending Shorts ownership, including resume',
      () async {
    var transfers = 0;
    final player = TubePlayerProvider(onNormalPlayback: () => ++transfers);
    await player.playVideo(const TubeVideoItem(
        id: 'restricted',
        title: 'Restricted',
        channelId: 'creator',
        channelTitle: 'Creator',
        thumbnailUrl: '',
        isMembersOnly: true));
    expect(transfers, 1);
    player.play();
    expect(transfers, 2);
    await player.resetLocalState();
    await player.flushSignals();
    player.dispose();
  });
  test('Reset does not delete stores when native stop fails', () async {
    await profile.saveIdentity({'displayName': 'Keep'}, complete: true);
    final player = TubePlayerProvider();
    final shorts = TubeShortsController();
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.shreyx.tube/player_channel'), (call) async {
      if (call.method == 'stop') throw PlatformException(code: 'stop-failed');
      return true;
    });
    await expectLater(TubeLocalResetService.reset(player, shorts),
        throwsA(isA<PlatformException>()));
    expect(await db.getSetting('onboarding_completed'), 'true');
    expect(profile.displayName, 'Keep');
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.shreyx.tube/player_channel'),
        (_) async => true);
    player.dispose();
    shorts.dispose();
  });
  testWidgets(
      'Confirmed reset clears stores and returns the root to onboarding',
      (tester) async {
    await tester.runAsync(() =>
        profile.saveIdentity({'displayName': 'Reset fixture'}, complete: true));
    final player = TubePlayerProvider();
    final shorts = TubeShortsController();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: player),
          ChangeNotifierProvider.value(value: shorts),
        ],
        child: MaterialApp(
            home: ListenableBuilder(
                listenable: profile,
                builder: (context, _) => profile.onboardingCompleted
                    ? Scaffold(
                        body: Center(
                            child: FilledButton(
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const TubePrivacySettingsScreen())),
                                child: const Text('Privacy fixture'))))
                    : const TubeOnboardingScreen()))));
    await tester.tap(find.text('Privacy fixture'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Clear All Local Data'), 400);
    await tester.tap(find.text('Clear All Local Data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all data'));
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
      if (!profile.onboardingCompleted &&
          find.byType(TubePrivacySettingsScreen).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('Reset did not finish'), findsNothing);
    expect(profile.onboardingCompleted, isFalse);
    expect(find.text('Welcome to ShreyX Tube'), findsOneWidget);
    expect(profile.onboardingCompleted, isFalse);
    expect(await tester.runAsync(() => db.getSetting('onboarding_completed')),
        isNull);
    expect(player.currentVideoItem, isNull);
    expect(shorts.shorts, isEmpty);
    await tester.pumpWidget(const SizedBox());
    player.dispose();
    shorts.dispose();
  });
  testWidgets(
      'Root floating player and repeated reparenting build without layout/overlay errors',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.shreyx.tube/player_channel'),
        (call) async => call.method == 'getStatus'
            ? {
                'hasMedia': true,
                'videoId': 'abcdefghijk',
                'title': 'Fixture',
                'channelTitle': 'Creator',
                'positionMs': 42000,
                'durationMs': 120000,
                'isPlaying': false
              }
            : true);
    final player = TubePlayerProvider();
    final shorts = TubeShortsController();
    await player.restoreNativePlayback();
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: player),
      ChangeNotifierProvider.value(value: shorts)
    ], child: const ShreyXTubeApp()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 5; i++) {
      player.expandPlayer();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      player.collapsePlayer();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(player.position.inSeconds, 42);
    await tester.pumpWidget(const SizedBox());
    await player.resetLocalState();
    player.dispose();
    shorts.dispose();
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.shreyx.tube/player_channel'),
        (_) async => true);
    debugDefaultTargetPlatformOverride = null;
  });
}
