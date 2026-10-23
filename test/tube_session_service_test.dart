import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shreyx_tube/models/tube_models.dart';
import 'package:shreyx_tube/screens/tube_auth_screen.dart';
import 'package:shreyx_tube/services/tube_google_auth.dart';
import 'package:shreyx_tube/services/tube_innertube_client.dart';
import 'package:shreyx_tube/services/tube_session_service.dart';
import 'package:shreyx_tube/services/tube_storage_service.dart';
import 'package:shreyx_tube/services/tube_youtube_account_client.dart';

class MemoryStore implements TubeSessionStore {
  String? value;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (failWrite) throw StateError('Disk unavailable');
    value = next;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class FakeGoogle implements TubeGoogleAuth {
  TubeGoogleIdentity identity =
      const TubeGoogleIdentity('user-a', 'Account A', '');
  String? accessToken = 'synthetic-access-token';
  int authentications = 0;
  bool revoked = false;
  @override
  Future<void> initialize(String webClientId) async {}
  @override
  Future<TubeGoogleIdentity?> restore() async => identity;
  @override
  Future<TubeGoogleIdentity> authenticate() async {
    authentications++;
    return identity;
  }

  @override
  Future<String?> token(
          {bool interactive = false, bool refresh = false}) async =>
      accessToken;
  @override
  Future<void> disconnect() async {
    revoked = true;
  }
}

const fakeClientId = '12345-app-registration.apps.googleusercontent.com';
const channel = TubeChannelInfo(
    id: 'channel-a',
    title: 'Actual YouTube channel',
    avatarUrl: 'https://yt3.ggpht.com/avatar',
    handle: '@actual');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryStore store;
  late FakeGoogle google;
  late TubeSessionService session;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await TubeStorageService().init();
  });
  setUp(() async {
    store = MemoryStore();
    google = FakeGoogle();
    session = TubeSessionService.withStore(store,
        auth: google,
        webClientId: fakeClientId,
        profileLoader: (_) async => channel);
    await TubeStorageService().setIncognito(false);
  });
  test('Guest default; missing app registration never starts Google login', () {
    expect(session.isLoggedIn, isFalse);
    expect(session.getAuthHeaders(), isEmpty);
    final unconfigured =
        TubeSessionService.withStore(store, auth: google, webClientId: '');
    expect(() => unconfigured.connect(), throwsStateError);
    expect(google.authentications, 0);
  });
  test('Official authorization persists metadata without tokens or cookies',
      () async {
    await session.connect();
    expect(session.userChannelName, channel.title);
    expect(session.getAuthHeaders(),
        {'Authorization': 'Bearer synthetic-access-token'});
    expect(store.value, isNot(contains('synthetic-access-token')));
    expect(store.value, isNot(contains('Cookie')));
    expect(jsonDecode(store.value!)['accountId'], 'user-a');
  });
  test('One app registration accepts different users dynamically', () async {
    await session.connect();
    await session.clearSession();
    google.identity = const TubeGoogleIdentity('user-b', 'Account B', '');
    google.accessToken = 'user-b-token';
    await session.connect();
    expect(jsonDecode(store.value!)['accountId'], 'user-b');
    expect(session.getAuthHeaders()['Authorization'], 'Bearer user-b-token');
  });
  test('Disconnect deletes metadata, drops headers and revokes app access',
      () async {
    await session.connect();
    await session.clearSession();
    expect(google.revoked, isTrue);
    expect(store.value, isNull);
    expect(session.getAuthHeaders(), isEmpty);
    expect(session.userChannelName, isEmpty);
  });
  test('Silent restore requires the same account and existing grant', () async {
    await session.connect();
    final restored = TubeSessionService.withStore(store,
        auth: google, webClientId: fakeClientId);
    await restored.init();
    expect(restored.isLoggedIn, isTrue);
    google.identity = const TubeGoogleIdentity('other', 'Other', '');
    final wrong = TubeSessionService.withStore(store,
        auth: google, webClientId: fakeClientId);
    await wrong.init();
    expect(wrong.isLoggedIn, isFalse);
    expect(store.value, isNull);
  });
  test('Missing grant cannot silently connect', () async {
    await session.connect();
    google.accessToken = null;
    final restored = TubeSessionService.withStore(store,
        auth: google, webClientId: fakeClientId);
    await restored.init();
    expect(restored.isLoggedIn, isFalse);
  });
  test('Storage failure never activates an account', () async {
    store.failWrite = true;
    await expectLater(session.connect(), throwsStateError);
    expect(session.isLoggedIn, isFalse);
  });
  test('Malformed metadata returns to Guest', () async {
    store.value = '{invalid';
    await session.init();
    expect(session.isLoggedIn, isFalse);
    expect(store.value, isNull);
  });
  test('Disconnect fences a pending connection', () async {
    final profile = Completer<TubeChannelInfo?>();
    session = TubeSessionService.withStore(store,
        auth: google,
        webClientId: fakeClientId,
        profileLoader: (_) => profile.future);
    final pending = session.connect();
    await Future<void>.delayed(Duration.zero);
    await session.clearSession();
    profile.complete(channel);
    await pending;
    expect(session.isLoggedIn, isFalse);
    expect(store.value, isNull);
  });
  test('Rapid sign-in taps share one Google authentication', () async {
    await Future.wait([session.connect(), session.connect()]);
    expect(google.authentications, 1);
  });
  test('Incognito suppresses account requests but preserves saved connection',
      () async {
    await session.connect();
    await TubeStorageService().setIncognito(true);
    expect(await session.authorizationToken(), isNull);
    expect(session.getAuthHeaders(), isEmpty);
    expect(session.isLoggedIn, isTrue);
    await TubeStorageService().setIncognito(false);
    expect(await session.authorizationToken(), 'synthetic-access-token');
  });
  test('Guest local data survives connecting and disconnecting', () async {
    await TubeStorageService().writeStoreFile('oauth_sentinel', 'preserved');
    await session.connect();
    await session.clearSession();
    expect(await TubeStorageService().readStoreFile('oauth_sentinel'),
        'preserved');
  });
  test('Innertube receives no OAuth headers or session cookies', () async {
    await session.connect();
    final client = TubeInnertubeClient.withClient(MockClient((r) async {
      expect(r.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')));
      expect(r.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('cookie')));
      return http.Response('{}', 200);
    }));
    await client.search('public');
    await client.next('public');
    await client.browse('FEwhat_to_watch');
  });
  test('Official subscriptions parse IDs, thumbnails and continuation tokens',
      () async {
    final api = TubeYoutubeAccountClient(
        client: MockClient((r) async {
          expect(r.url.host, 'www.googleapis.com');
          expect(r.url.path, '/youtube/v3/subscriptions');
          expect(r.url.queryParameters['pageToken'], 'next-page');
          expect(r.headers['authorization'], 'Bearer token');
          expect(r.followRedirects, isFalse);
          return http.Response(
              jsonEncode({
                'items': [
                  {
                    'snippet': {
                      'title': 'Subscribed channel',
                      'resourceId': {'channelId': 'UCactual'},
                      'thumbnails': {
                        'default': {'url': 'https://yt3.ggpht.com/avatar'}
                      }
                    }
                  }
                ],
                'nextPageToken': 'more'
              }),
              200);
        }),
        tokenProvider: (_) async => 'token',
        onUnauthorized: () async {});
    final page = await api.getSubscribedChannels(continuation: 'next-page');
    expect(page.items.single.id, 'UCactual');
    expect(page.continuationToken, 'more');
  });
  test(
      '401 retries once with refreshed token; persistent rejection disconnects',
      () async {
    final attempts = <bool>[];
    var rejected = false;
    var requests = 0;
    final api = TubeYoutubeAccountClient(client: MockClient((_) async {
      requests++;
      return http.Response('{}', 401);
    }), tokenProvider: (refresh) async {
      attempts.add(refresh);
      return 'token';
    }, onUnauthorized: () async {
      rejected = true;
    });
    await expectLater(
        api.getSubscribedChannels(), throwsA(isA<TubeAccountApiException>()));
    expect(attempts, [false, true]);
    expect(requests, 2);
    expect(rejected, isTrue);
  });
  test('Quota errors explain the cause without signing out', () async {
    var rejected = false;
    final api = TubeYoutubeAccountClient(
        client: MockClient((_) async => http.Response(
            '{"error":{"errors":[{"reason":"quotaExceeded"}]}}', 403)),
        tokenProvider: (_) async => 'token',
        onUnauthorized: () async {
          rejected = true;
        });
    await expectLater(api.getSubscribedChannels(),
        throwsA(predicate((e) => e.toString().contains('quota'))));
    expect(rejected, isFalse);
  });
  test('Advertising wrappers discard nested video cards', () {
    final client = TubeInnertubeClient.withClient(
        MockClient((_) async => http.Response('{}', 200)));
    Map<String, dynamic> card(String id) => {
          'videoRenderer': {
            'videoId': id,
            'title': {'simpleText': id}
          }
        };
    final page = client.parseFeedPage({
      'contents': [
        card('organic'),
        for (final ad in [
          'adSlotRenderer',
          'promotedSparklesWebRenderer',
          'statementBannerRenderer',
          'promotedVideoRenderer'
        ])
          {
            ad: {'content': card('advertisement')}
          }
      ]
    });
    expect(page.items.map((v) => v.id), ['organic']);
  });
  testWidgets(
      'Default-browser action calls Android without creating a connection',
      (tester) async {
    var launches = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const bridge = MethodChannel('com.shreyx.tube/session_browser');
    messenger.setMockMethodCallHandler(bridge, (call) async {
      expect(call.method, 'openBrowser');
      launches++;
      return true;
    });
    await tester.pumpWidget(const MaterialApp(home: TubeAuthScreen()));
    await tester.ensureVisible(find.text('Open YouTube in default browser'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open YouTube in default browser'));
    await tester.pumpAndSettle();
    expect(launches, 1);
    expect(TubeSessionService().isLoggedIn, isFalse);
    messenger.setMockMethodCallHandler(bridge, null);
  });
  testWidgets('Missing default browser produces an actionable error',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const bridge = MethodChannel('com.shreyx.tube/session_browser');
    messenger.setMockMethodCallHandler(bridge, (_) async => false);
    await tester.pumpWidget(const MaterialApp(home: TubeAuthScreen()));
    await tester.ensureVisible(find.text('Open YouTube in default browser'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open YouTube in default browser'));
    await tester.pumpAndSettle();
    expect(find.text('No supported browser is available.'), findsOneWidget);
    messenger.setMockMethodCallHandler(bridge, null);
  });
  testWidgets('Unconfigured build is explicit and contains no embedded login',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TubeAuthScreen()));
    expect(find.textContaining('not enabled in this build'), findsOneWidget);
    expect(find.text('Open YouTube in default browser'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });
}
