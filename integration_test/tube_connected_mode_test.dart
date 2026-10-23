import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shreyx_tube/screens/tube_auth_screen.dart';
import 'package:shreyx_tube/services/tube_session_service.dart';

// Isolated emulator only: this deletes the app's synthetic test account metadata.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android encrypted metadata and legacy-cookie session cleanup',
      (tester) async {
    const storage = FlutterSecureStorage();
    await storage.write(
        key: 'tube_google_connection_v1',
        value: jsonEncode({'accountId': 'synthetic-fixture'}));
    await storage.write(
        key: 'tube_youtube_session_v1', value: 'retired-test-session');
    expect(
        jsonDecode((await storage.read(key: 'tube_google_connection_v1'))!)[
            'accountId'],
        'synthetic-fixture');
    await TubeSessionService().clearSession();
    expect(await storage.read(key: 'tube_google_connection_v1'), isNull);
    expect(await storage.read(key: 'tube_youtube_session_v1'), isNull);
    expect(TubeSessionService().getAuthHeaders(), isEmpty);
  });
  testWidgets(
      'Android account screen explains unconfigured build and cancels safely',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const TubeAuthScreen())),
                    child: const Text('Connect'))))));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not enabled in this build'), findsOneWidget);
    expect(find.text('Open YouTube in default browser'), findsOneWidget);
    await tester.ensureVisible(find.text('Continue as Guest'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue as Guest'));
    await tester.pumpAndSettle();
    expect(find.text('Connect'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
