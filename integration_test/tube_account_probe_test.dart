import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:shreyx_tube/screens/tube_account_probe_screen.dart';
import 'package:shreyx_tube/services/tube_session_service.dart';
import 'dart:convert';

class _EncryptedRecord implements TubeSessionStore {
  final storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => storage.read(key: 'tube_google_connection_v1');
  @override
  Future<void> write(String value) =>
      storage.write(key: 'tube_google_connection_v1', value: value);
  @override
  Future<void> delete() => storage.delete(key: 'tube_google_connection_v1');
}

// Owned emulator only. No human account or real credentials are used.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  final cookieDomain = Uri.parse('https://www.youtube.com');
  testWidgets('Interrupted test clears the actual Android WebView cookie jar',
      (tester) async {
    final cookies = WebViewCookieManager();
    await cookies.setCookie(const WebViewCookie(
        name: 'shreyx_probe_fixture',
        value: 'synthetic',
        domain: '.youtube.com'));
    expect(await cookies.getCookies(domain: cookieDomain), isNotEmpty);
    await storage.write(key: 'tube_cookie_login_retired', value: 'true');
    await storage.write(key: 'tube_account_probe_pending', value: 'true');
    await TubeSessionService().init();
    expect(await storage.read(key: 'tube_account_probe_pending'), isNull);
    expect(await cookies.getCookies(domain: cookieDomain), isEmpty);
    expect(TubeSessionService().isLoggedIn, isFalse);
  });
  testWidgets('Actual sign-in WebView opens and close removes test state',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const TubeAccountProbeScreen())),
                    child: const Text('Open test'))))));
    await tester.tap(find.text('Open test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start sign-in test'));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byType(WebViewWidget).evaluate().isNotEmpty ||
          find.textContaining('test has stopped').evaluate().isNotEmpty) {
        break;
      }
    }
    final hasWebView = find.byType(WebViewWidget).evaluate().isNotEmpty;
    expect(
        hasWebView ||
            find.textContaining('test has stopped').evaluate().isNotEmpty,
        isTrue);
    if (hasWebView) {
      await WebViewCookieManager().setCookie(const WebViewCookie(
          name: 'shreyx_probe_fixture',
          value: 'synthetic',
          domain: '.youtube.com'));
    }
    await tester.tap(find.text('Close test'));
    // Native document teardown has no Flutter animation to keep pumpAndSettle
    // waiting. Wait for the route itself, with a bounded real-device deadline.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text('Open test').evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.textContaining('cleanup did not finish'), findsNothing);
    expect(find.text('Open test'), findsOneWidget);
    expect(await storage.read(key: 'tube_account_probe_pending'), isNull);
    expect(
        await WebViewCookieManager().getCookies(domain: cookieDomain), isEmpty);
    expect(TubeSessionService().isLoggedIn, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Actual Android encrypted private connection restores and disconnects',
      (tester) async {
    final record = _EncryptedRecord();
    final session = TubeSessionService.withStore(record, webClientId: '');
    expect(
        await session.savePrivateConnection({
          'SAPISID': 'synthetic-android-api',
          'SID': 'synthetic-android-session'
        },
            name: 'Synthetic Android fixture',
            userAgent: 'genuine-synthetic-browser'),
        isTrue);
    expect(jsonDecode((await record.read())!)['mode'], 'youtubeSession');
    final restored = TubeSessionService.withStore(record, webClientId: '');
    await restored.init();
    expect(restored.usesPrivateFeed, isTrue);
    expect(restored.userChannelName, 'Synthetic Android fixture');
    expect(restored.getAuthHeaders(), isEmpty);
    await restored.clearSession();
    expect(await record.read(), isNull);
    expect(restored.getPrivateHeaders(), isEmpty);
  });
}
