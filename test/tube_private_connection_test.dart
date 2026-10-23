import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shreyx_tube/models/tube_models.dart';
import 'package:shreyx_tube/screens/tube_account_probe_screen.dart';
import 'package:shreyx_tube/services/tube_account_probe.dart';
import 'package:shreyx_tube/services/tube_home_feed_service.dart';
import 'package:shreyx_tube/services/tube_innertube_client.dart';
import 'package:shreyx_tube/services/tube_session_service.dart';
import 'package:shreyx_tube/services/tube_shorts_service.dart';
import 'package:shreyx_tube/services/tube_storage_service.dart';

const cookies = {
  'SAPISID': 'synthetic-private-api',
  'SID': 'synthetic-session'
};

class _Store implements TubeSessionStore {
  String? value;
  bool failWrite = false;
  Completer<void>? gate;
  final entered = Completer<void>();
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    if (failWrite) throw StateError('Synthetic disk failure');
    value = next;
  }

  @override
  Future<void> delete() async => value = null;
}

Map<String, dynamic> card(String id, {bool short = false}) => {
      'videoRenderer': {
        'videoId': id,
        'title': {'simpleText': id},
        if (short) 'navigationEndpoint': {'reelWatchEndpoint': {}},
      }
    };
Map<String, dynamic> page(List<dynamic> contents, {bool loggedOut = false}) => {
      'responseContext': {
        'mainAppWebResponseContext': {'loggedOut': loggedOut}
      },
      'contents': contents,
    };
http.Response jsonResponse(Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), 200);
Future<bool> connect(TubeSessionService session, {bool Function()? active}) =>
    session.savePrivateConnection(cookies,
        name: 'Verified fixture account',
        userAgent: 'genuine-fixture-browser',
        stillActive: active);

class _Browser implements TubeProbeBrowser {
  int clears = 0;
  @override
  Widget view() => const Text('Synthetic first-party browser');
  @override
  Future<void> open(
      {required TubeProbeNavigation Function(String) navigation,
      required void Function(String) loaded,
      required VoidCallback failed}) async {
    navigation('https://www.youtube.com/');
    loaded('https://www.youtube.com/');
  }

  @override
  Future<void> returnToYouTube() async {}
  @override
  Future<Map<String, String>> cookies() async =>
      {'SAPISID': 'synthetic-private-api', 'SID': 'synthetic-session'};
  @override
  Future<String> userAgent() async => 'genuine-fixture-browser';
  @override
  Future<void> clear() async {
    clears++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late TubeSessionService session;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await TubeStorageService().init();
  });
  setUp(() async {
    await TubeStorageService().setIncognito(false);
    store = _Store();
    session = TubeSessionService.withStore(store, webClientId: '');
  });

  test(
      'Opt-in private connection needs no OAuth client and keeps OAuth headers separate',
      () async {
    expect(await connect(session), isTrue);
    expect(session.isLoggedIn, isTrue);
    expect(session.usesPrivateFeed, isTrue);
    expect(session.usesAccountData, isFalse);
    expect(session.getAuthHeaders(), isEmpty);
    expect(await session.authorizationToken(), isNull);
    expect(session.getPrivateHeaders()['Authorization'],
        startsWith('SAPISIDHASH '));
    expect(jsonDecode(store.value!)['mode'], 'youtubeSession');
  });
  test('Saved connection restores independently of app OAuth configuration',
      () async {
    await connect(session);
    final restored = TubeSessionService.withStore(store, webClientId: '');
    await restored.init();
    expect(restored.usesPrivateFeed, isTrue);
    expect(restored.userChannelName, 'Verified fixture account');
    expect(restored.revision, greaterThan(0));
    expect(
        restored.getPrivateHeaders()['Cookie'], contains('synthetic-session'));
  });
  test(
      'Incognito suppresses private credentials and preserves the saved session',
      () async {
    await connect(session);
    final stored = store.value;
    await TubeStorageService().setIncognito(true);
    expect(session.usesPrivateFeed, isFalse);
    expect(session.getPrivateHeaders(), isEmpty);
    expect(store.value, stored);
    await TubeStorageService().setIncognito(false);
    expect(session.usesPrivateFeed, isTrue);
  });
  test('Disconnect deletes the saved session without deleting Guest data',
      () async {
    await TubeStorageService().writeStoreFile('private_sentinel', 'preserved');
    await connect(session);
    await session.clearSession();
    expect(session.isLoggedIn, isFalse);
    expect(session.getPrivateHeaders(), isEmpty);
    expect(store.value, isNull);
    expect(await TubeStorageService().readStoreFile('private_sentinel'),
        'preserved');
  });
  test('Storage failure never activates the private connection', () async {
    store.failWrite = true;
    await expectLater(connect(session), throwsStateError);
    expect(session.isLoggedIn, isFalse);
    expect(session.getPrivateHeaders(), isEmpty);
  });
  test('Cancelling during the encrypted write rolls back the saved record',
      () async {
    store.gate = Completer<void>();
    var active = true;
    final saving = connect(session, active: () => active);
    await store.entered.future;
    active = false;
    store.gate!.complete();
    expect(await saving, isFalse);
    expect(store.value, isNull);
    expect(session.isLoggedIn, isFalse);
  });
  test('Malformed private records cannot connect on startup', () async {
    store.value = jsonEncode({
      'mode': 'youtubeSession',
      'cookies': {'SID': 'incomplete'},
      'name': 'Fixture',
      'userAgent': 'browser'
    });
    await session.init();
    expect(session.isLoggedIn, isFalse);
    expect(store.value, isNull);
  });
  test(
      'Private requests are first-party, authenticated and never follow redirects',
      () async {
    await connect(session);
    final client = TubeInnertubeClient.withClient(MockClient((request) async {
      expect(request.url.host, 'www.youtube.com');
      expect(request.url.scheme, 'https');
      expect(request.followRedirects, isFalse);
      expect(request.headers['Cookie'], contains('synthetic-session'));
      expect(request.headers['Authorization'], startsWith('SAPISIDHASH '));
      expect(request.headers['User-Agent'], 'genuine-fixture-browser');
      return jsonResponse(page([card('server-item')]));
    }), session: session);
    expect((await client.homeFeed()).items.single.id, 'server-item');
  });
  test(
      'Account Home ignores local reranking/suppression and keeps continuation order',
      () async {
    await connect(session);
    await TubeStorageService().addNotInterestedVideo('server-first');
    final calls = <Map<String, dynamic>>[];
    final client = TubeInnertubeClient.withClient(MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      calls.add(body);
      expect(request.url.path.endsWith('/browse'), isTrue);
      if (body['continuation'] != null) {
        return jsonResponse(page([card('server-third')]));
      }
      return jsonResponse(page([
        card('server-first'),
        card('server-second'),
        card('server-first'),
        {
          'continuationItemRenderer': {
            'continuationEndpoint': {
              'continuationCommand': {'token': 'cursor-a'}
            }
          }
        },
      ]));
    }), session: session);
    final feed = TubeHomeFeedService.withClient(client);
    expect(
        (await feed.getCategoryFeed('Recommended', forceRefresh: true))
            .map((v) => v.id),
        ['server-first', 'server-second']);
    expect((await feed.getCategoryFeedNextPage('Recommended')).map((v) => v.id),
        ['server-third']);
    expect(calls.last['continuation'], 'cursor-a');
    expect(calls.length, 2);
  });
  test('Account Up Next preserves the returned order', () async {
    await connect(session);
    final client = TubeInnertubeClient.withClient(
        MockClient((_) async => jsonResponse({
              'responseContext': page([])['responseContext'],
              'contents': {
                'twoColumnWatchNextResults': {
                  'secondaryResults': {
                    'secondaryResults': {
                      'results': [card('z-first'), card('a-second')]
                    }
                  }
                }
              }
            })),
        session: session);
    final feed = TubeHomeFeedService.withClient(client);
    const current = TubeVideoItem(
        id: 'current',
        title: 'Current fixture',
        channelTitle: '',
        channelId: '');
    expect((await feed.getRelatedVideos(current)).map((v) => v.id),
        ['z-first', 'a-second']);
  });
  test(
      'Explicit expiry clears the connection; generic forbidden responses do not',
      () async {
    await connect(session);
    final forbidden = TubeInnertubeClient.withClient(
        MockClient((_) async => http.Response('{}', 403)),
        session: session);
    await expectLater(forbidden.homeFeed(), throwsStateError);
    expect(session.usesPrivateFeed, isTrue);
    final expired = TubeInnertubeClient.withClient(
        MockClient((_) async => jsonResponse(page([], loggedOut: true))),
        session: session);
    await expectLater(expired.homeFeed(), throwsStateError);
    expect(session.isLoggedIn, isFalse);
    expect(store.value, isNull);
  });
  test('Ambiguous Home responses never count as a personalized feed', () async {
    await connect(session);
    final client = TubeInnertubeClient.withClient(
        MockClient((_) async => jsonResponse({
              'contents': [card('public')]
            })),
        session: session);
    await expectLater(client.homeFeed(), throwsStateError);
    expect(session.usesPrivateFeed, isTrue);
  });
  test('Disconnect fences an already pending account response', () async {
    await connect(session);
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final client = TubeInnertubeClient.withClient(MockClient((_) {
      started.complete();
      return response.future;
    }), session: session);
    final loading = client.homeFeed();
    final assertion = expectLater(loading, throwsStateError);
    await started.future;
    await session.clearSession();
    response.complete(jsonResponse(page([card('stale-account-card')])));
    await assertion;
  });
  test(
      'Committing a different account rejects requests started during its save',
      () async {
    await connect(session);
    store.gate = Completer<void>();
    final saving = session.savePrivateConnection(
        {'SAPISID': 'synthetic-account-b', 'SID': 'synthetic-session-b'},
        name: 'Fixture account B', userAgent: 'genuine-fixture-browser');
    await Future<void>.delayed(Duration.zero);
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final client = TubeInnertubeClient.withClient(MockClient((request) {
      expect(request.headers['Cookie'], contains('synthetic-session'));
      started.complete();
      return response.future;
    }), session: session);
    final loading = client.homeFeed();
    final assertion = expectLater(loading, throwsStateError);
    await started.future;
    store.gate!.complete();
    expect(await saving, isTrue);
    response.complete(jsonResponse(page([card('previous-account-result')])));
    await assertion;
    expect(session.userChannelName, 'Fixture account B');
  });
  test(
      'Unsupported private Shorts falls back without mixing continuation sources',
      () async {
    await connect(session);
    final paths = <String>[];
    final client = TubeInnertubeClient.withClient(MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/browse')) return http.Response('{}', 500);
      final body = jsonDecode(request.body);
      if (body['continuation'] != null) {
        expect(body['continuation'], 'search-cursor');
        return jsonResponse(page([card('second-short', short: true)]));
      }
      return jsonResponse(page([
        card('real-short', short: true),
        {
          'continuationItemRenderer': {
            'continuationEndpoint': {
              'continuationCommand': {'token': 'search-cursor'}
            }
          }
        },
      ]));
    }), session: session);
    final shorts = TubeShortsService.withClient(client);
    expect((await shorts.getShortsFeed()).single.id, 'real-short');
    expect((await shorts.getShortsFeed(page: 1)).single.id, 'second-short');
    expect(paths.map((p) => p.split('/').last), ['browse', 'search', 'search']);
  });
  test('Video and lockup channel avatars resolve protocol-relative image URLs',
      () {
    final client = TubeInnertubeClient.withClient(
        MockClient((_) async => http.Response('{}', 200)),
        session: session);
    const url = '//yt3.ggpht.com/fixture';
    final video = client.parseVideoRenderer({
      'videoId': 'fixture-video',
      'channelThumbnailSupportedRenderers': {
        'channelThumbnailWithLinkRenderer': {
          'thumbnail': {
            'thumbnails': [
              {'url': url}
            ]
          }
        }
      }
    });
    final lockup = client.parseVideoLockup({
      'contentId': 'fixture-lockup',
      'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
      'metadata': {
        'lockupMetadataViewModel': {
          'image': {
            'decoratedAvatarViewModel': {
              'avatar': {
                'avatarViewModel': {
                  'image': {
                    'sources': [
                      {'url': url}
                    ]
                  }
                }
              }
            }
          }
        }
      }
    });
    expect(video!.channelAvatarUrl, 'https:$url');
    expect(lockup!.channelAvatarUrl, 'https:$url');
  });
  test(
      'Account subscriptions use their own continuation and channel metadata endpoints',
      () async {
    await connect(session);
    final calls = <Map<String, dynamic>>[];
    final client = TubeInnertubeClient.withClient(MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      calls.add(body);
      if (body['browseId'] == 'FEchannels') {
        return jsonResponse(page([
          {
            'channelRenderer': {
              'channelId': 'UCfixture',
              'title': {'simpleText': 'Fixture channel'},
              'thumbnail': {
                'thumbnails': [
                  {'url': '//yt3.ggpht.com/fixture'}
                ]
              }
            }
          }
        ]));
      }
      expect(body['browseId'], 'FEsubscriptions');
      return jsonResponse(page([
        card(body['continuation'] == null
            ? 'subscription-first'
            : 'subscription-next')
      ]));
    }), session: session);
    final channel = (await client.subscribedChannels()).single;
    expect(channel.id, 'UCfixture');
    expect(channel.avatarUrl, 'https://yt3.ggpht.com/fixture');
    expect((await client.subscriptionsFeed()).items.single.id,
        'subscription-first');
    expect(
        (await client.subscriptionsFeed(continuation: 'subscription-cursor'))
            .items
            .single
            .id,
        'subscription-next');
    expect(calls.last['continuation'], 'subscription-cursor');
  });
  testWidgets(
      'Explicit connected flow saves a validated session and closes without preview-only mode',
      (tester) async {
    // Construct its serialization Future in the widget test's fake-async zone.
    session = TubeSessionService.withStore(store, webClientId: '');
    final browser = _Browser();
    final probe = TubeAccountProbe(client: MockClient((request) async {
      if (request.url.path.endsWith('account_menu')) {
        return jsonResponse({
          ...page([]),
          'activeAccountHeaderRenderer': {
            'accountName': {'simpleText': 'Verified fixture account'}
          }
        });
      }
      return jsonResponse(page([card('native-preview')]));
    }));
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => TubeAccountProbeScreen(
                                saveConnection: true,
                                session: session,
                                probe: probe,
                                browserFactory: () => browser))),
                    child: const Text('Connect fixture'))))));
    await tester.tap(find.text('Connect fixture'));
    await tester.pumpAndSettle();
    expect(find.textContaining('encrypted on this device'), findsOneWidget);
    await tester.tap(find.text('Sign in and connect feed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish connecting'));
    await tester.pumpAndSettle();
    expect(session.usesPrivateFeed, isTrue);
    expect(browser.clears, 1);
    expect(find.text('Connect fixture'), findsOneWidget);
    expect(find.text('native-preview'), findsNothing);
  });
}
