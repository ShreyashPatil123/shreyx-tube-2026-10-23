import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shreyx_tube/models/tube_models.dart';
import 'package:shreyx_tube/providers/tube_player_provider.dart';
import 'package:shreyx_tube/screens/tube_search_screen.dart';
import 'package:shreyx_tube/screens/tube_watch_screen.dart';
import 'package:shreyx_tube/services/tube_channel_upload_pager.dart';
import 'package:shreyx_tube/services/tube_innertube_client.dart';
import 'package:shreyx_tube/services/tube_search_service.dart';
import 'package:shreyx_tube/services/tube_storage_service.dart';
import 'package:shreyx_tube/widgets/tube_video_card.dart';

TubeVideoItem video(int id) => TubeVideoItem(
      id: 'video$id',
      title: 'Upload $id',
      channelTitle: 'Creator',
      channelId: 'UCtest',
      durationSeconds: 120,
    );

Map<String, dynamic> renderer(String id, {bool member = false}) => {
      'videoId': id,
      'thumbnail': {
        'thumbnails': [
          {'url': ''}
        ]
      },
      'title': {
        'runs': [
          {'text': 'Upload $id'}
        ]
      },
      'lengthText': {'simpleText': '2:00'},
      'detailedMetadataSnippets': [],
      if (member)
        'badges': [
          {
            'metadataBadgeRenderer': {
              'style': 'BADGE_STYLE_TYPE_MEMBERS_ONLY',
              'label': 'Members only',
            }
          }
        ],
    };

http.Response searchResponse(String id, {bool member = false, String? token}) =>
    http.Response(
        jsonEncode({
          'contents': {
            'twoColumnSearchResultsRenderer': {
              'primaryContents': {
                'sectionListRenderer': {
                  'contents': [
                    {
                      'itemSectionRenderer': {
                        'contents': [
                          {'videoRenderer': renderer(id, member: member)}
                        ]
                      }
                    },
                    if (token != null) continuation(token),
                  ]
                },
              }
            }
          },
        }),
        200);

Map<String, dynamic> continuation(String token) => {
      'continuationItemRenderer': {
        'continuationEndpoint': {
          'continuationCommand': {'token': token},
        }
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(
        {'pref_pause_personalization': true});
    await TubeStorageService().init();
  });

  test('sort, upload time and duration compose in the request', () {
    final encoded = const TubeSearchFilters(
            sortBy: 'upload_date',
            uploadDate: 'hour',
            duration: 'long',
            contentType: 'videos')
        .toInnertubeParams()!;
    expect(base64Decode(encoded), [8, 2, 18, 6, 8, 1, 16, 1, 24, 2]);
    expect(const TubeSearchFilters(sortBy: 'upload_date').toInnertubeParams(),
        'CAISBAgCEAE=');
    expect(const TubeSearchFilters(sortBy: 'view_count').toInnertubeParams(),
        'CAMSAhAB');
    expect(const TubeSearchFilters().toInnertubeParams(), isNull);
  });

  test('refresh bypasses cache and content types have separate cache entries',
      () async {
    var requests = 0;
    final service = TubeSearchService.withClient(MockClient((request) async {
      requests++;
      return searchResponse('result$requests', member: true);
    }));
    addTearDown(service.dispose);
    expect((await service.search('new upload')).videos.single.id, 'result1');
    expect((await service.search('new upload')).videos.single.id, 'result1');
    expect(
        (await service.search('new upload', forceRefresh: true))
            .videos
            .single
            .id,
        'result2');
    await service.search('new upload',
        filters: const TubeSearchFilters(contentType: 'channels'));
    expect(requests, 3);
    expect((await service.search('new upload')).videos.single.isMembersOnly,
        isTrue);
  });

  test('nested continuation results retain membership and terminate pagination',
      () async {
    final service = TubeSearchService.withClient(
        MockClient((request) async => http.Response(
            jsonEncode({
              'onResponseReceivedCommands': [
                {
                  'appendContinuationItemsAction': {
                    'continuationItems': [
                      {
                        'itemSectionRenderer': {
                          'contents': [
                            {'videoRenderer': renderer('member', member: true)},
                          ]
                        }
                      }
                    ],
                  }
                }
              ],
            }),
            200)));
    addTearDown(service.dispose);
    final page = await service.searchNextPage('last');
    expect(page.videos.single.isMembersOnly, isTrue);
    expect(
        const TubeSearchResults(continuationToken: 'old')
            .copyWith(
                videos: page.videos, continuationToken: page.continuationToken)
            .continuationToken,
        isNull);
  });

  test('membership detection uses badges rather than title keywords', () {
    final client = TubeInnertubeClient();
    final public = renderer('public')
      ..['title'] = {'simpleText': 'Explaining members-only videos'};
    expect(client.parseVideoRenderer(public)!.isMembersOnly, isFalse);
    expect(
        client
            .parseVideoRenderer(renderer('member', member: true))!
            .isMembersOnly,
        isTrue);
  });

  test('channel browse sends cursor and parses both response formats',
      () async {
    var calls = 0;
    final client = TubeInnertubeClient.withClient(MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      calls++;
      if (calls == 1) {
        expect(body['browseId'], 'UCtest');
        expect(body['params'], 'EgZ2aWRlb3PyBgQKAjoA');
        return http.Response(
            jsonEncode({
              'contents': {
                'twoColumnBrowseResultsRenderer': {
                  'tabs': [
                    {
                      'tabRenderer': {
                        'selected': true,
                        'content': {
                          'richGridRenderer': {
                            'contents': [
                              {
                                'richItemRenderer': {
                                  'content': {
                                    'videoRenderer':
                                        renderer('one', member: true)
                                  }
                                }
                              },
                              continuation('next'),
                            ]
                          }
                        }
                      }
                    },
                  ]
                }
              }
            }),
            200);
      }
      expect(body['continuation'], 'next');
      expect(body.containsKey('browseId'), isFalse);
      return http.Response(
          jsonEncode({
            'onResponseReceivedActions': [
              {
                'appendContinuationItemsAction': {
                  'continuationItems': [
                    {'gridVideoRenderer': renderer('two')}
                  ],
                }
              }
            ]
          }),
          200);
    }));
    final first = await client.channelVideos('UCtest', channelTitle: 'Creator');
    expect(first.items.single.isMembersOnly, isTrue);
    expect(first.items.single.channelId, 'UCtest');
    final last = await client.channelVideos('UCtest',
        continuation: first.continuationToken);
    expect(last.items.single.id, 'two');
    expect(last.continuationToken, isNull);
  });

  test('modern channel video lockups retain metadata and membership', () {
    final item = TubeInnertubeClient().parseVideoLockup({
      'contentId': 'modern',
      'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
      'contentImage': {
        'thumbnailViewModel': {
          'image': {
            'sources': [
              {'url': 'https://i.ytimg.com/vi/modern/hqdefault.jpg'}
            ]
          },
          'overlays': [
            {
              'thumbnailOverlayBadgeViewModel': {
                'thumbnailBadges': [
                  {
                    'thumbnailBadgeViewModel': {'text': '12:34'}
                  }
                ]
              }
            }
          ]
        }
      },
      'metadata': {
        'lockupMetadataViewModel': {
          'title': {'content': 'New upload'},
          'metadata': {
            'contentMetadataViewModel': {
              'metadataRows': [
                {
                  'metadataParts': [
                    {
                      'text': {'content': 'Creator'}
                    }
                  ]
                },
                {
                  'metadataParts': [
                    {
                      'text': {'content': '1K views'}
                    },
                    {
                      'text': {'content': '1 hour ago'}
                    }
                  ]
                },
                {
                  'badges': [
                    {'label': 'Members only'}
                  ]
                },
              ]
            }
          },
        }
      },
    });
    expect(item!.title, 'New upload');
    expect(item.durationSeconds, 754);
    expect(item.viewCount, 1000);
    expect(item.isMembersOnly, isTrue);
    expect(
        TubeInnertubeClient.hasMembersOnlyBadge({
          'metadata': {
            'lockupMetadataViewModel': {
              'title': {'content': 'Explaining members-only videos'},
            }
          },
        }),
        isFalse);
  });

  test('latest requests a recent period and sorts returned timestamps locally',
      () async {
    final service = TubeSearchService.withClient(MockClient((request) async {
      expect(jsonDecode(request.body)['params'], 'CAISBAgCEAE=');
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
                            {
                              'videoRenderer': renderer('older')
                                ..['publishedTimeText'] = {
                                  'simpleText': '6 hours ago'
                                }
                            },
                            {
                              'videoRenderer': renderer('newer')
                                ..['publishedTimeText'] = {
                                  'simpleText': '3 minutes ago'
                                }
                            },
                          ]
                        }
                      },
                    ]
                  }
                },
              }
            }
          }),
          200);
    }));
    addTearDown(service.dispose);
    final result = await service.search('technology',
        filters: const TubeSearchFilters(sortBy: 'upload_date'));
    expect(result.videos.map((video) => video.id), ['newer', 'older']);
    final merged = TubeSearchService.latestFirst([
      ...result.videos,
      video(3).copyWith(publishedTimeText: '1 minute ago'),
    ]);
    expect(merged.first.id, 'video3');
    expect(
        base64Decode(
            const TubeSearchFilters(duration: 'short').toInnertubeParams()!),
        [18, 2, 24, 4]);
    expect(
        base64Decode(
            const TubeSearchFilters(duration: 'medium').toInnertubeParams()!),
        [18, 2, 24, 5]);
  });

  test('channel Home responses trigger fallback rather than false exhaustion',
      () async {
    final client = TubeInnertubeClient.withClient(
        MockClient((request) async => http.Response(
            jsonEncode({
              'contents': {
                'twoColumnBrowseResultsRenderer': {
                  'tabs': [
                    {
                      'tabRenderer': {
                        'title': 'Home',
                        'selected': true,
                        'content': {}
                      }
                    },
                  ]
                }
              },
            }),
            200)));
    await expectLater(client.channelVideos('UCtest'), throwsStateError);
  });

  test('catalog pagination reaches 2400 uploads without a fixed cap', () async {
    final pager = TubeChannelUploadPager(
      readPage: (token) async {
        final offset = int.parse(token ?? '0');
        return (
          items: List.generate(40, (index) => video(offset + index)),
          continuationToken: offset + 40 == 2400 ? null : '${offset + 40}'
        );
      },
      fallbackUploads: () => const Stream.empty(),
    );
    while (pager.hasMore) {
      await pager.loadMore();
    }
    expect(pager.items.length, 2400);
    expect(pager.items.last.id, 'video2399');
  });

  test(
      'transient browse failure falls back, deduplicates, then retries same cursor',
      () async {
    var fail = true;
    final tokens = <String?>[];
    final pager = TubeChannelUploadPager(
        readPage: (token) async {
          tokens.add(token);
          if (fail) throw StateError('Offline');
          return (
            items: [video(0), video(1), video(2)],
            continuationToken: null
          );
        },
        fallbackUploads: () => Stream.fromIterable([video(0), video(1)]));
    expect((await pager.loadMore()).length, 2);
    expect(pager.hasMore, isTrue);
    fail = false;
    expect((await pager.loadMore()).length, 3);
    expect(tokens, [null, null]);
    expect(pager.hasMore, isFalse);
  });

  test('failed fallback preserves retryable cursor and existing uploads',
      () async {
    var calls = 0;
    final pager = TubeChannelUploadPager(
        readPage: (token) async {
          if (++calls == 1) {
            return (items: [video(0)], continuationToken: 'next');
          }
          expect(token, 'next');
          throw StateError('Network error');
        },
        fallbackUploads: () => const Stream.empty());
    await pager.loadMore();
    await expectLater(pager.loadMore(), throwsStateError);
    expect(pager.items.single.id, 'video0');
    expect(pager.hasMore, isTrue);
    await expectLater(pager.loadMore(), throwsStateError);
  });

  test('concurrent channel loads share a single request', () async {
    final response = Completer<TubeChannelPage>();
    var calls = 0;
    final pager = TubeChannelUploadPager(
        readPage: (_) {
          calls++;
          return response.future;
        },
        fallbackUploads: () => const Stream.empty());
    final first = pager.loadMore();
    final second = pager.loadMore();
    response.complete((items: [video(1)], continuationToken: null));
    await Future.wait([first, second]);
    expect(calls, 1);
    expect(pager.items.length, 1);
  });

  test('duplicate-only pages are skipped and repeated cursors stay retryable',
      () async {
    var calls = 0;
    final pager = TubeChannelUploadPager(
        readPage: (token) async {
          calls++;
          if (token == null) {
            return (items: [video(0)], continuationToken: 'one');
          }
          if (token == 'one') {
            return (items: [video(0)], continuationToken: 'two');
          }
          return (items: [video(1)], continuationToken: 'three');
        },
        fallbackUploads: () => const Stream.empty());
    await pager.loadMore();
    expect((await pager.loadMore()).length, 2);
    expect(calls, 3);
    await expectLater(pager.loadMore(), throwsStateError);
    expect(pager.hasMore, isTrue);
  });

  testWidgets(
      'search shows latest sort and a repeated submit fetches fresh results',
      (tester) async {
    var calls = 0;
    final service = TubeSearchService.withClient(
        MockClient((request) async => searchResponse('result${++calls}')));
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(
        home:
            TubeSearchScreen(initialQuery: 'latest', searchService: service)));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Upload result2'), findsOneWidget);
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Upload Date (Latest)'), findsOneWidget);
    await tester.tap(find.text('Upload Date (Latest)'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, 'Upload Date (Latest)'))
            .selected,
        isTrue);
  });

  testWidgets(
      'members-only playback pauses native audio and shows a copyable notice',
      (tester) async {
    final calls = <String>[];
    String? clipboard;
    const playerChannel = MethodChannel('com.shreyx.tube/player_channel');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(playerChannel, (call) async {
      calls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = call.arguments['text'] as String;
      }
      return null;
    });
    final player = TubePlayerProvider();
    await player.playVideo(video(1).copyWith(isMembersOnly: true));
    expect(player.isLoading, isFalse);
    expect(player.errorMessage, isNull);
    player.play();
    player.retry();
    await tester.pump();
    expect(calls, ['stop', 'pause']);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: player,
        child: MaterialApp(home: TubeWatchScreen(onCollapse: () {}))));
    expect(find.text('MEMBERS ONLY'), findsOneWidget);
    expect(find.text('Retry Video'), findsNothing);
    await tester.tap(find.text('Copy Link'));
    await tester.pump();
    expect(clipboard, 'https://www.youtube.com/watch?v=video1');
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
    messenger.setMockMethodCallHandler(playerChannel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('a late search response cannot replace a newer query',
      (tester) async {
    final oldResponse = Completer<http.Response>();
    final service = TubeSearchService.withClient(MockClient((request) async {
      final query = jsonDecode(request.body)['query'];
      return query == 'old' ? await oldResponse.future : searchResponse('new');
    }));
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(
        home: TubeSearchScreen(initialQuery: 'old', searchService: service)));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'new');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.text('Upload new'), findsOneWidget);
    oldResponse.complete(searchResponse('old'));
    await tester.pumpAndSettle();
    expect(find.text('Upload new'), findsOneWidget);
    expect(find.text('Upload old'), findsNothing);
  });

  testWidgets('pull-to-refresh also works for empty search results',
      (tester) async {
    var calls = 0;
    final service = TubeSearchService.withClient(MockClient((request) async {
      calls++;
      return http.Response(
          jsonEncode({
            'contents': {
              'twoColumnSearchResultsRenderer': {
                'primaryContents': {
                  'sectionListRenderer': {'contents': []},
                }
              },
            }
          }),
          200);
    }));
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(
        home: TubeSearchScreen(initialQuery: 'empty', searchService: service)));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.drag(find.byType(ListView).last, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('compact and home video cards both display the gold badge',
      (tester) async {
    for (final compact in [true, false]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TubeVideoCard(
                  video: video(1).copyWith(isMembersOnly: true),
                  isCompact: compact))));
      expect(find.text('MEMBERS ONLY'), findsOneWidget);
    }
  });
}
