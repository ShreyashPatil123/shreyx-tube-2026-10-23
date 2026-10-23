import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shreyx_tube/models/tube_models.dart';
import 'package:shreyx_tube/models/tube_stream.dart';
import 'package:shreyx_tube/providers/tube_player_provider.dart';
import 'package:shreyx_tube/screens/tube_search_screen.dart';
import 'package:shreyx_tube/services/tube_home_feed_service.dart';
import 'package:shreyx_tube/services/tube_innertube_client.dart';
import 'package:shreyx_tube/services/tube_search_service.dart';
import 'package:shreyx_tube/services/tube_storage_service.dart';
import 'package:shreyx_tube/services/tube_stream_resolver.dart';
import 'package:shreyx_tube/services/tube_shorts_service.dart';
import 'package:shreyx_tube/widgets/tube_player_back_observer.dart';
import 'package:shreyx_tube/widgets/tube_watch_navigation_boundary.dart';

Map<String, dynamic> card(String id, {bool short = false, bool live = false}) =>
    {
      'videoId': id,
      'thumbnail': {
        'thumbnails': [
          {'url': ''}
        ]
      },
      'title': {'simpleText': 'Video $id'},
      'lengthText': {'simpleText': short ? '2:30' : '0:45'},
      'ownerText': {'runs': []},
      'longBylineText': {
        'runs': [
          {
            'text': 'Real Creator',
            'navigationEndpoint': {
              'browseEndpoint': {'browseId': 'UCcreator'}
            }
          }
        ]
      },
      'navigationEndpoint': {
        'commandMetadata': {
          'webCommandMetadata': {'url': short ? '/shorts/$id' : '/watch?v=$id'}
        }
      },
      if (live)
        'badges': [
          {
            'metadataBadgeRenderer': {
              'style': 'BADGE_STYLE_TYPE_LIVE_NOW',
              'label': 'LIVE'
            }
          }
        ],
    };

Map<String, dynamic> feed(List<Map<String, dynamic>> cards, {String? token}) =>
    {
      'contents': {
        'richGridRenderer': {
          'contents': <dynamic>[
            ...cards.map((v) => {
                  'richItemRenderer': {
                    'content': {'videoRenderer': v}
                  }
                }),
            if (token != null)
              {
                'continuationItemRenderer': {
                  'continuationEndpoint': {
                    'continuationCommand': {'token': token}
                  }
                }
              },
          ]
        }
      },
    };

TubeVideoStream stream(String url, int height,
        {bool adaptive = false, String codec = 'avc1'}) =>
    TubeVideoStream(
      url: url,
      resolution: '${height}p',
      width: height * 16 ~/ 9,
      height: height,
      container: 'mp4',
      mimeType: 'video/mp4',
      codec: codec,
      fps: 30,
      bitrate: 1000000,
      isVideoOnly: adaptive,
      deliveryMethod: 'PROGRESSIVE',
      manifestType: 'PROGRESSIVE',
      pairedAudioUrl: adaptive ? 'https://media.test/audio' : null,
    );

TubeResolvedVideo resolved(String id,
        {bool live = false,
        String? hls,
        String? dash,
        List<TubeVideoStream>? streams}) =>
    TubeResolvedVideo(
      videoId: id,
      title: id,
      uploader: 'Creator',
      durationSeconds: live ? 0 : 120,
      thumbnailUrl: '',
      videoStreams: streams ?? [stream('https://media.test/$id', 720)],
      audioStreams: [],
      subtitles: [],
      extractorSource: 'test',
      isLive: live,
      hlsUrl: hls,
      dashMpdUrl: dash,
    );

void main() {
  testWidgets(
      'closing the watch navigator preserves root Search and Android Back',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final root = GlobalKey<NavigatorState>();
    final showing = ValueNotifier(true);
    final observer = TubePlayerBackObserver(onPlayerBack: () {});
    observer.expanded = true;
    final backFlags = <bool>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
        backFlags.add(call.arguments as bool);
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(
      navigatorKey: root,
      navigatorObservers: [observer],
      builder: (_, child) => ValueListenableBuilder<bool>(
        valueListenable: showing,
        builder: (_, visible, __) => Stack(children: [
          child!,
          if (visible)
            TubeWatchNavigationBoundary(
                child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Watch route')),
              ),
            )),
        ]),
      ),
      home: const Scaffold(body: Text('Home route')),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(backFlags.last, isTrue);
    showing.value = false;
    observer.expanded = false;
    await tester.pumpAndSettle();
    root.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Search route')),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Search route'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    observer.dispose();
    showing.dispose();
  });

  testWidgets('Back minimizes an expanded player before popping Search',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    var minimized = 0;
    final observer = TubePlayerBackObserver(onPlayerBack: () => minimized++);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: [observer],
      home: const Scaffold(body: Text('Home route')),
    ));
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Search route')),
    ));
    await tester.pumpAndSettle();
    observer.expanded = true;
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(minimized, 1);
    expect(find.text('Search route'), findsOneWidget);
    observer.expanded = false;
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Home route'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    observer.dispose();
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await TubeStorageService().init();
  });

  test('Shorts classification uses the endpoint, not a sixty-second cutoff',
      () {
    final parser = TubeInnertubeClient();
    expect(
        parser.parseVideoRenderer(card('short', short: true))!.isShort, isTrue);
    expect(parser.parseVideoRenderer(card('trailer'))!.isShort, isFalse);
  });

  test('empty owner runs fall through to the real channel name and ID', () {
    final item = TubeInnertubeClient().parseVideoRenderer(card('creator'))!;
    expect(item.channelTitle, 'Real Creator');
    expect(item.channelId, 'UCcreator');
  });

  test('only a currently live badge marks a stream as live', () {
    final parser = TubeInnertubeClient();
    expect(parser.parseVideoRenderer(card('live', live: true))!.isLive, isTrue);
    final upcoming = card('upcoming')
      ..['badges'] = [
        {
          'metadataBadgeRenderer': {
            'label': 'Live tomorrow',
            'style': 'BADGE_STYLE_TYPE_SIMPLE'
          }
        }
      ];
    expect(parser.parseVideoRenderer(upcoming)!.isLive, isFalse);
  });

  test('Shorts feed never relabels ordinary search videos and follows cursors',
      () async {
    final bodies = <Map<String, dynamic>>[];
    final service = TubeShortsService.withClient(TubeInnertubeClient.withClient(
      MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
            jsonEncode({
              'contents': {
                'sectionListRenderer': {
                  'contents': [
                    {'videoRenderer': card('ordinary')},
                    {
                      'videoRenderer': card(
                          bodies.length == 1 ? 'short1' : 'short2',
                          short: true)
                    },
                    if (bodies.length == 1)
                      {
                        'continuationItemRenderer': {
                          'continuationEndpoint': {
                            'continuationCommand': {'token': 'shortCursor'}
                          }
                        }
                      },
                  ]
                }
              }
            }),
            200);
      }),
    ));
    expect(
        (await service.getShortsFeed()).map((video) => video.id), ['short1']);
    expect((await service.getShortsFeed(page: 1)).map((video) => video.id),
        ['short2']);
    expect(bodies.last['continuation'], 'shortCursor');
    expect(await service.getShortsFeed(page: 2), isEmpty);
    expect(bodies, hasLength(2));
  });

  test('Home preserves YouTube order and excludes Shorts and ads', () {
    final data = feed(
        [card('b'), card('short', short: true), card('a'), card('b')],
        token: 'next');
    (data['contents']['richGridRenderer']['contents'] as List).add({
      'adSlotRenderer': {'videoRenderer': card('ad')}
    });
    final page = TubeInnertubeClient().parseFeedPage(data);
    expect(page.items.map((v) => v.id), ['b', 'a']);
    expect(page.continuationToken, 'next');
  });

  test('public Up Next reads compact cards from the secondary results',
      () async {
    final client = TubeInnertubeClient.withClient(
        MockClient((request) async => http.Response(
            jsonEncode({
              'contents': {
                'twoColumnWatchNextResults': {
                  'secondaryResults': {
                    'secondaryResults': {
                      'results': [
                        {'compactVideoRenderer': card('related')},
                      ]
                    }
                  }
                }
              },
            }),
            200)));
    expect((await client.relatedFeed('seed')).items.single.channelTitle,
        'Real Creator');
  });

  test('Home pagination follows real cursors and stops at exhaustion',
      () async {
    var calls = 0;
    final service = TubeHomeFeedService.withClient(
        TubeInnertubeClient.withClient(MockClient((request) async {
      calls++;
      return http.Response(
          jsonEncode(calls == 1
              ? feed([card('b'), card('a')], token: 'cursor')
              : feed([card('a'), card('c')])),
          200);
    })));
    expect(
        (await service.getCategoryFeed('Recommended', forceRefresh: true))
            .map((v) => v.id),
        ['b', 'a']);
    expect(
        (await service.getCategoryFeedNextPage('Recommended')).map((v) => v.id),
        ['c']);
    expect(service.hasMore('Recommended'), isFalse);
    expect(await service.getCategoryFeedNextPage('Recommended'), isEmpty);
    expect(calls, 2);
  });

  test(
      'live HLS is playable without progressive formats and carries live metadata',
      () {
    final chosen = resolved('live',
        live: true,
        hls: 'https://media.test/live.m3u8',
        streams: []).getBestStream('Auto')!;
    expect(chosen.deliveryMethod, 'HLS');
    expect(chosen.toMediaParams()['isLive'], isTrue);
    expect(chosen.pairedAudioUrl, isNull);
  });

  test('live DASH is selected if HLS is missing', () {
    expect(
        resolved('live',
            live: true,
            dash: 'https://media.test/live.mpd',
            streams: []).getBestStream('720p')!.deliveryMethod,
        'DASH_MPD');
  });

  test('Auto starts at mobile 720p while explicit 1080p remains available', () {
    final video = resolved('vod', streams: [
      stream('1080', 1080, adaptive: true),
      stream('vp9', 720, adaptive: true, codec: 'vp9'),
      stream('muxed', 720)
    ]);
    expect(video.getBestStream('Auto')!.url, 'muxed');
    expect(video.getBestStream('1080p')!.url, '1080');
  });

  test(
      'prefetch and playback share extraction, and forced refresh replaces cached URLs',
      () async {
    var calls = 0;
    final gate = Completer<TubeResolvedVideo>();
    final resolver = TubeStreamResolver.withLoader((id) async {
      calls++;
      return calls == 1
          ? await gate.future
          : resolved(id, streams: [stream('fresh', 720)]);
    });
    final first = resolver.resolve('abcdefghijk');
    final second = resolver.resolve('abcdefghijk');
    gate.complete(resolved('abcdefghijk'));
    await Future.wait([first, second]);
    expect(calls, 1);
    await resolver.resolve('abcdefghijk');
    expect(calls, 1);
    expect(
        (await resolver.resolve('abcdefghijk', forceRefresh: true))
            .getBestStream('Auto')!
            .url,
        'fresh');
    expect(calls, 2);
  });

  testWidgets('tapping the submitted query shows suggestions again',
      (tester) async {
    final service = TubeSearchService.withClient(MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
            jsonEncode([
              'music',
              ['music live', 'music mix']
            ]),
            200);
      }
      return http.Response(
          jsonEncode({
            'contents': {
              'twoColumnSearchResultsRenderer': {
                'primaryContents': {
                  'sectionListRenderer': {
                    'contents': [
                      {
                        'itemSectionRenderer': {
                          'contents': [
                            {'videoRenderer': card('result')}
                          ]
                        }
                      },
                    ]
                  }
                }
              }
            }
          }),
          200);
    }));
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(
        home: TubeSearchScreen(initialQuery: 'music', searchService: service)));
    await tester.pumpAndSettle();
    expect(find.text('Video result'), findsOneWidget);
    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('music live'), findsOneWidget);
    expect(find.text('Video result'), findsNothing);
  });

  testWidgets(
      'closing during extraction prevents a late video from reopening the player',
      (tester) async {
    const channel = MethodChannel('com.shreyx.tube/player_channel');
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return {'ok': true};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final gate = Completer<TubeResolvedVideo>();
    final player = TubePlayerProvider(
      resolver: TubeStreamResolver.withLoader((id) => gate.future),
      homeFeedService: TubeHomeFeedService.withClient(
          TubeInnertubeClient.withClient(
              MockClient((request) async => http.Response('{}', 200)))),
    );
    final playing = player.playVideo(const TubeVideoItem(
        id: 'abcdefghijk',
        title: 'Video',
        channelTitle: 'Creator',
        channelId: 'UCcreator'));
    await tester.pump();
    player.closePlayer();
    gate.complete(resolved('abcdefghijk'));
    await playing;
    await tester.pump();
    expect(player.isPlayerVisible, isFalse);
    expect(calls, isNot(contains('loadMedia')));
    player.dispose();
  });

  testWidgets('opening a URL also loads public Up Next and channel metadata',
      (tester) async {
    const channel = MethodChannel('com.shreyx.tube/player_channel');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => {'ok': true});
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final player = TubePlayerProvider(
      resolver: TubeStreamResolver.withLoader((id) async => TubeResolvedVideo(
            videoId: id,
            title: 'Video',
            uploader: 'Creator',
            uploaderUrl: 'https://www.youtube.com/channel/UCcreator',
            uploaderAvatarUrl: 'https://image.test/avatar.jpg',
            durationSeconds: 120,
            thumbnailUrl: '',
            videoStreams: [stream('https://media.test/$id', 720)],
            audioStreams: [],
            subtitles: [],
            extractorSource: 'test',
          )),
      homeFeedService:
          TubeHomeFeedService.withClient(TubeInnertubeClient.withClient(
        MockClient((_) async => http.Response(
            jsonEncode({
              'contents': {
                'twoColumnWatchNextResults': {
                  'secondaryResults': {
                    'secondaryResults': {
                      'results': [
                        {'compactVideoRenderer': card('next')}
                      ]
                    }
                  }
                }
              }
            }),
            200)),
      )),
    );
    await player.resolveAndPlay('abcdefghijk');
    await tester.pump();
    expect(player.currentVideoItem?.channelId, 'UCcreator');
    expect(player.currentVideoItem?.channelAvatarUrl,
        'https://image.test/avatar.jpg');
    expect(player.relatedVideos.map((video) => video.id), ['next']);
    player.dispose();
  });
}
