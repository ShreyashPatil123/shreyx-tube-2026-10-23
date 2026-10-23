import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shreyx_tube/screens/tube_account_probe_screen.dart';
import 'package:shreyx_tube/services/tube_account_probe.dart';
import 'package:shreyx_tube/services/tube_session_service.dart';
import 'package:shreyx_tube/services/tube_storage_service.dart';

const fixtureCookies = {'SAPISID': 'synthetic-sapisid', 'SID': 'synthetic-sid'};
Map<String, dynamic> responseContext({bool loggedOut = false}) => {
      'responseContext': {
        'mainAppWebResponseContext': {'loggedOut': loggedOut}
      }
    };
Map<String, dynamic> accountResponse() => {
      ...responseContext(),
      'actions': [
        {
          'activeAccountHeaderRenderer': {
            'accountName': {'simpleText': 'Fixture YouTube account'}
          }
        }
      ]
    };
Map<String, dynamic> card(String id, {bool short = false}) => {
      'videoRenderer': {
        'videoId': id,
        'title': {'simpleText': 'Video $id'},
        if (short) 'navigationEndpoint': {'reelWatchEndpoint': {}}
      }
    };
Map<String, dynamic> homeResponse() => {
      ...responseContext(),
      'contents': [
        card('first'),
        {
          'adSlotRenderer': {'content': card('ad')}
        },
        card('short', short: true),
        card('second'),
        card('first'),
      ]
    };
http.Response fixtureResponse(http.Request request) => http.Response(
    jsonEncode(request.url.path.endsWith('account_menu')
        ? accountResponse()
        : homeResponse()),
    200);

class FakeProbeBrowser implements TubeProbeBrowser {
  late TubeProbeNavigation Function(String) navigation;
  late void Function(String) loaded;
  int clears = 0;
  int reads = 0;
  int returns = 0;
  bool cleanupFails = false;
  @override
  Widget view() => const Text('Fixture browser surface');
  @override
  Future<void> open({
    required TubeProbeNavigation Function(String) navigation,
    required void Function(String) loaded,
    required VoidCallback failed,
  }) async {
    this.navigation = navigation;
    this.loaded = loaded;
    navigation('https://www.youtube.com/');
    loaded('https://www.youtube.com/');
  }

  @override
  Future<Map<String, String>> cookies() async {
    reads++;
    return Map.of(fixtureCookies);
  }

  @override
  Future<String> userAgent() async => 'genuine-fixture-browser';
  @override
  Future<void> returnToYouTube() async {
    returns++;
    navigation('https://www.youtube.com/');
    loaded('https://www.youtube.com/');
  }

  @override
  Future<void> clear() async {
    clears++;
    if (cleanupFails) throw StateError('Fixture cleanup failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await TubeStorageService().init();
  });
  setUp(() async => TubeStorageService().setIncognito(false));

  test('Blocked-destination diagnostics never expose sign-in redirect secrets',
      () {
    expect(
        tubeProbeDestinationLabel(
            'https://user:password@accounts.youtube.com/accounts/SetSID?sidt=private-token#private-fragment'),
        'accounts.youtube.com');
    expect(tubeProbeDestinationLabel('about:blank'), 'about:blank');
    expect(tubeProbeDestinationLabel('intent:private-token'),
        'unsupported destination type');
  });

  for (final url in [
    'https://accounts.google.com/ServiceLogin?service=youtube',
    'https://myaccount.google.com/',
    'https://accounts.youtube.com/accounts/SetSID?sidt=synthetic-handoff',
    'https://www.youtube.com/',
    'https://m.youtube.com/',
    'https://consent.google.com/m',
  ]) {
    test('Allows first-party website navigation: $url', () {
      expect(tubeProbeNavigation(url), TubeProbeNavigation.allow);
    });
  }
  for (final url in [
    'http://accounts.google.com/',
    'https://accounts.google.com.evil.example/',
    'https://myaccount.google.com.evil.example/',
    'https://accounts.youtube.com.evil.example/accounts/SetSID',
    'https://youtube.com@evil.example/',
    'https://user:password@www.youtube.com/',
    'https://www.youtube.com:444/',
    'intent://accounts.google.com/',
    'javascript:alert(1)',
  ]) {
    test('Rejects unsupported sign-in destination: $url', () {
      expect(tubeProbeNavigation(url), TubeProbeNavigation.unsupported);
    });
  }
  for (final url in [
    'https://accounts.google.com/o/oauth2/v2/auth',
    'https://accounts.google.com/signin/oauth/consent',
    'https://myaccount.google.com/o/oauth2/auth',
    'https://accounts.google.com/signin/rejected?error=disallowed_useragent',
    'https://accounts.google.com/v3/signin/deniedsigninrejected',
  ]) {
    test('Stops embedded OAuth or sign-in rejection: $url', () {
      expect(tubeProbeNavigation(url), TubeProbeNavigation.rejected);
    });
  }
  test('Credential headers allow only valid session-cookie names and values',
      () {
    final headers = TubeAccountProbe.headersFor({
      ...fixtureCookies,
      'SIDCC': 'invalid\r\nvalue',
      'SSID': 'invalid;value',
      'unrelated': 'never-forward',
    }, timestamp: 123);
    expect(headers['Cookie'], 'SAPISID=synthetic-sapisid; SID=synthetic-sid');
    expect(headers['Authorization'], startsWith('SAPISIDHASH 123_'));
    expect(headers['Origin'], TubeAccountProbe.origin);
    expect(() => TubeAccountProbe.headersFor({'SAPISID': 'no-session'}),
        throwsA(isA<TubeAccountProbeException>()));
  });
  test('Modern first-party session with third-party APISID is accepted', () {
    expect(
        TubeAccountProbe.headersFor({
          '__Secure-3PAPISID': 'synthetic-api',
          '__Secure-1PSID': 'synthetic-session'
        })['Authorization'],
        startsWith('SAPISIDHASH '));
  });
  test('Checks signed-in account and Home; preserves organic server ordering',
      () async {
    final requests = <http.Request>[];
    final probe = TubeAccountProbe(client: MockClient((request) async {
      requests.add(request);
      return fixtureResponse(request);
    }));
    final result = await probe.check(fixtureCookies, userAgent: 'real-browser');
    expect(result.name, 'Fixture YouTube account');
    expect(result.videos.map((v) => v.id), ['first', 'second']);
    expect(requests.length, 2);
    for (final request in requests) {
      expect(request.url.host, 'www.youtube.com');
      expect(request.url.scheme, 'https');
      expect(request.followRedirects, isFalse);
      expect(request.headers['User-Agent'], 'real-browser');
      expect(request.headers['Authorization'], startsWith('SAPISIDHASH '));
    }
    expect(jsonDecode(requests.last.body)['browseId'], 'FEwhat_to_watch');
    expect(TubeSessionService().isLoggedIn, isFalse);
  });
  test('Logged-out or missing-marker responses never count as connected',
      () async {
    for (final data in [
      {...accountResponse(), ...responseContext(loggedOut: true)},
      {...accountResponse(), 'responseContext': {}}
    ]) {
      var requests = 0;
      final probe = TubeAccountProbe(client: MockClient((_) async {
        requests++;
        return http.Response(jsonEncode(data), 200);
      }));
      await expectLater(probe.check(fixtureCookies, userAgent: 'real-browser'),
          throwsA(isA<TubeAccountProbeException>()));
      expect(requests, 1);
    }
  });
  test('Valid account plus logged-out Home cannot pass the feasibility check',
      () async {
    final probe = TubeAccountProbe(
        client: MockClient((request) async =>
            request.url.path.endsWith('account_menu')
                ? fixtureResponse(request)
                : http.Response(
                    jsonEncode(responseContext(loggedOut: true)), 200)));
    await expectLater(probe.check(fixtureCookies, userAgent: 'real-browser'),
        throwsA(isA<TubeAccountProbeException>()));
  });
  test('Redirects, server failures and malformed JSON never expose credentials',
      () async {
    for (final status in [302, 401, 403, 429, 500, 200]) {
      var requests = 0;
      final probe = TubeAccountProbe(client: MockClient((_) async {
        requests++;
        return http.Response('synthetic-sapisid private response', status,
            headers: {'location': 'https://evil.example/'});
      }));
      try {
        await probe.check(fixtureCookies, userAgent: 'real-browser');
        fail('An invalid response must fail');
      } on TubeAccountProbeException catch (error) {
        expect(error.toString(), isNot(contains('synthetic-sapisid')));
        expect(error.toString(), isNot(contains('private response')));
      }
      expect(requests, 1);
    }
  });
  test('Incognito sends no account request', () async {
    var requests = 0;
    final probe = TubeAccountProbe(client: MockClient((request) async {
      requests++;
      return fixtureResponse(request);
    }));
    await TubeStorageService().setIncognito(true);
    await expectLater(probe.check(fixtureCookies, userAgent: 'real-browser'),
        throwsA(isA<TubeAccountProbeException>()));
    expect(requests, 0);
  });
  test('Enabling Incognito during account validation prevents the Home request',
      () async {
    final response = Completer<http.Response>();
    var requests = 0;
    final probe = TubeAccountProbe(client: MockClient((_) {
      requests++;
      return response.future;
    }));
    final result = probe.check(fixtureCookies, userAgent: 'real-browser');
    final assertion =
        expectLater(result, throwsA(isA<TubeAccountProbeException>()));
    await TubeStorageService().setIncognito(true);
    response.complete(http.Response(jsonEncode(accountResponse()), 200));
    await assertion;
    expect(requests, 1);
  });
  test('Signed-in marker without an account profile does not pass', () async {
    var requests = 0;
    final probe = TubeAccountProbe(client: MockClient((_) async {
      requests++;
      return http.Response(jsonEncode(responseContext()), 200);
    }));
    await expectLater(probe.check(fixtureCookies, userAgent: 'real-browser'),
        throwsA(isA<TubeAccountProbeException>()));
    expect(requests, 1);
  });
  test(
      'Cancellation while account request is pending prevents the Home request',
      () async {
    var active = true;
    var requests = 0;
    final response = Completer<http.Response>();
    final probe = TubeAccountProbe(client: MockClient((_) {
      requests++;
      return response.future;
    }));
    final result = probe.check(fixtureCookies,
        userAgent: 'real-browser', stillActive: () => active);
    final assertion =
        expectLater(result, throwsA(isA<TubeAccountProbeException>()));
    active = false;
    response.complete(http.Response(jsonEncode(accountResponse()), 200));
    await assertion;
    expect(requests, 1);
  });

  Future<void> openProbe(WidgetTester tester, FakeProbeBrowser browser,
      {http.Client? client}) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => TubeAccountProbeScreen(
                                browserFactory: () => browser,
                                probe: TubeAccountProbe(
                                    client: client ??
                                        MockClient((r) async =>
                                            fixtureResponse(r)))))),
                    child: const Text('Open probe'))))));
    await tester.tap(find.text('Open probe'));
    await tester.pumpAndSettle();
  }

  testWidgets('Explicit opt-in, native preview and cleanup do not connect Home',
      (tester) async {
    final browser = FakeProbeBrowser();
    await openProbe(tester, browser);
    expect(find.textContaining('does not reuse Chrome'), findsOneWidget);
    expect(browser.reads, 0);
    await tester.tap(find.text('Start sign-in test'));
    await tester.pumpAndSettle();
    expect(browser.reads, 0);
    await tester.tap(find.text('Check sign-in and preview feed'));
    await tester.pumpAndSettle();
    expect(find.text('Video first'), findsOneWidget);
    expect(find.text('Video second'), findsOneWidget);
    expect(browser.clears, 1);
    expect(TubeSessionService().isLoggedIn, isFalse);
    await tester.tap(find.text('Close test'));
    await tester.pumpAndSettle();
    expect(find.text('Open probe'), findsOneWidget);
    expect(browser.clears, 1);
  });
  testWidgets('Rejected navigation stops checking and removes browser data',
      (tester) async {
    final browser = FakeProbeBrowser();
    await openProbe(tester, browser);
    await tester.tap(find.text('Start sign-in test'));
    await tester.pumpAndSettle();
    browser.navigation('https://accounts.google.com/o/oauth2/auth');
    await tester.pumpAndSettle();
    expect(find.textContaining('does not allow this embedded'), findsOneWidget);
    expect(find.text('Fixture browser surface'), findsNothing);
    expect(browser.clears, 1);
    expect(browser.reads, 0);
    await tester.tap(find.text('Close test'));
    await tester.pumpAndSettle();
  });
  testWidgets(
      'Google account redirect can return to YouTube without clearing sign-in',
      (tester) async {
    final browser = FakeProbeBrowser();
    await openProbe(tester, browser);
    await tester.tap(find.text('Start sign-in test'));
    await tester.pumpAndSettle();
    expect(browser.navigation('https://myaccount.google.com/'),
        TubeProbeNavigation.allow);
    browser.loaded('https://myaccount.google.com/');
    await tester.pumpAndSettle();
    expect(browser.clears, 0);
    expect(browser.reads, 0);
    expect(find.text('Return to YouTube'), findsOneWidget);
    await tester.tap(find.text('Return to YouTube'));
    await tester.pumpAndSettle();
    expect(browser.returns, 1);
    expect(browser.clears, 0);
    await tester.tap(find.text('Check sign-in and preview feed'));
    await tester.pumpAndSettle();
    expect(find.text('Video first'), findsOneWidget);
    expect(browser.clears, 1);
    await tester.tap(find.text('Close test'));
    await tester.pumpAndSettle();
  });
  testWidgets('Back cleans a pending test; late responses cannot show success',
      (tester) async {
    final pending = Completer<http.Response>();
    final browser = FakeProbeBrowser();
    await openProbe(tester, browser, client: MockClient((_) => pending.future));
    await tester.tap(find.text('Start sign-in test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check sign-in and preview feed'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    pending.complete(http.Response(jsonEncode(accountResponse()), 200));
    await tester.pumpAndSettle();
    expect(find.text('Open probe'), findsOneWidget);
    expect(browser.clears, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Cleanup failure keeps Close available for retry',
      (tester) async {
    final browser = FakeProbeBrowser()..cleanupFails = true;
    await openProbe(tester, browser);
    await tester.tap(find.text('Start sign-in test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close test'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tap Close test again'), findsOneWidget);
    expect(find.text('Open probe'), findsNothing);
    browser.cleanupFails = false;
    await tester.tap(find.text('Close test'));
    await tester.pumpAndSettle();
    expect(find.text('Open probe'), findsOneWidget);
    expect(browser.clears, 2);
  });
  testWidgets(
      'An API rejection clears temporary sign-in instead of retrying it',
      (tester) async {
    final browser = FakeProbeBrowser();
    await openProbe(tester, browser,
        client: MockClient((_) async => http.Response('{}', 403)));
    await tester.tap(find.text('Start sign-in test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check sign-in and preview feed'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('YouTube rejected this session'), findsOneWidget);
    expect(browser.clears, 1);
    expect(find.text('Fixture browser surface'), findsNothing);
    await tester.tap(find.text('Close test'));
    await tester.pumpAndSettle();
  });
  testWidgets('Empty Home cards do not claim native feed feasibility',
      (tester) async {
    final browser = FakeProbeBrowser();
    await openProbe(tester, browser,
        client: MockClient((request) async =>
            request.url.path.endsWith('account_menu')
                ? fixtureResponse(request)
                : http.Response(jsonEncode(responseContext()), 200)));
    await tester.tap(find.text('Start sign-in test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check sign-in and preview feed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('has not been demonstrated'), findsOneWidget);
    expect(browser.clears, 1);
    await tester.tap(find.text('Close test'));
    await tester.pumpAndSettle();
  });
}
