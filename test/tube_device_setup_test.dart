import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shreyx_tube/providers/tube_player_provider.dart';
import 'package:shreyx_tube/providers/tube_shorts_controller.dart';
import 'package:shreyx_tube/screens/tube_device_setup_screen.dart';
import 'package:shreyx_tube/services/tube_device_setup_service.dart';
import 'package:shreyx_tube/services/tube_link_service.dart';
import 'package:shreyx_tube/services/tube_user_profile_service.dart';
import 'package:shreyx_tube/widgets/tube_link_handler.dart';

const disabled = {
  'available': true,
  'notificationsEnabled': false,
  'canRequestNotifications': true,
  'linksSupported': true,
  'linksAllowed': true,
  'domains': {'youtube.com': 'disabled', 'youtu.be': 'disabled'},
  'youtubeInstalled': true,
  'pipSupported': true,
  'pipEnabled': true,
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Future<void> reveal(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(find.text(text), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  tearDown(() async {
    messenger.setMockMethodCallHandler(TubeDeviceSetupService.channel, null);
    messenger.setMockMethodCallHandler(TubeLinkService.channel, null);
    debugDefaultTargetPlatformOverride = null;
    await TubeDeviceSetupService().init(platform: TargetPlatform.linux);
  });
  test(
      'First launch and existing installs receive setup once; explicit skip persists',
      () async {
    final store = <String, String>{};
    TubeDeviceSetupService make() =>
        TubeDeviceSetupService.withStore((key) async => store[key],
            (key, value) async {
          store[key] = value;
        });
    final service = make();
    await service.init(platform: TargetPlatform.android);
    expect(service.pending, isTrue);
    await service.complete();
    expect(service.pending, isFalse);
    final nextProcess = make();
    await nextProcess.init(platform: TargetPlatform.android);
    expect(nextProcess.pending, isFalse);
    store.clear();
    await nextProcess.init(platform: TargetPlatform.android);
    expect(nextProcess.pending, isTrue);
  });
  test('Non-Android startup does not read setup storage', () async {
    final service = TubeDeviceSetupService.withStore(
        (_) async => throw StateError('Must not read'), (_, __) async {});
    await service.init(platform: TargetPlatform.linux);
    expect(service.pending, isFalse);
  });
  test('A failed setup write leaves first-run setup pending', () async {
    final service = TubeDeviceSetupService.withStore(
        (_) async => null, (_, __) async => throw StateError('disk full'));
    await service.init(platform: TargetPlatform.android);
    await expectLater(service.complete(), throwsStateError);
    expect(service.pending, isTrue);
  });
  test('Enabled toggle alone does not mean links are selected', () {
    expect(const TubeDeviceSetupStatus(disabled).linksReady, isFalse);
    final all = {
      ...disabled,
      'domains': {'youtube.com': 'selected', 'youtu.be': 'verified'}
    };
    expect(TubeDeviceSetupStatus(all).linksReady, isTrue);
    expect(TubeDeviceSetupStatus({...all, 'linksAllowed': false}).linksReady,
        isFalse);
    expect(TubeDeviceSetupStatus({...all, 'domains': {}}).linksReady, isFalse);
  });
  test('Missing native bridge reports unknown status and action failure',
      () async {
    expect((await TubeDeviceSetupService.inspect()).available, isFalse);
    expect(await TubeDeviceSetupService.action('openLinkSettings'), isFalse);
  });
  testWidgets(
      'Initial setup offers Android links, YouTube defaults and permission request',
      (tester) async {
    final actions = <String>[];
    messenger.setMockMethodCallHandler(TubeDeviceSetupService.channel,
        (call) async {
      if (call.method == 'status') return disabled;
      actions.add(call.method);
      return true;
    });
    await tester.pumpWidget(
        const MaterialApp(home: TubeDeviceSetupScreen(initialSetup: true)));
    await tester.pumpAndSettle();
    expect(
        find.text(
            '0 of 2 link domains enabled. In Android settings, choose In the app (or enable Open supported links), then add/select the YouTube and youtu.be addresses.'),
        findsOneWidget);
    await tester.tap(find.text('Set up supported links'));
    await tester.pumpAndSettle();
    await reveal(tester, 'YouTube link defaults');
    await tester.tap(find.text('YouTube link defaults'));
    await tester.pumpAndSettle();
    await reveal(tester, 'Allow notifications');
    await tester.tap(find.text('Allow notifications'));
    await tester.pumpAndSettle();
    expect(actions,
        ['openLinkSettings', 'openYouTubeSettings', 'requestNotifications']);
    await reveal(tester, 'Continue for now');
    expect(find.text('Continue for now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Returning from settings refreshes the actual link and notification state',
      (tester) async {
    var current = disabled;
    messenger.setMockMethodCallHandler(
        TubeDeviceSetupService.channel, (_) async => current);
    await tester.pumpWidget(
        const MaterialApp(home: TubeDeviceSetupScreen(initialSetup: true)));
    await tester.pumpAndSettle();
    current = {
      ...disabled,
      'notificationsEnabled': true,
      'domains': {'youtube.com': 'selected', 'youtu.be': 'selected'}
    };
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await reveal(tester, 'Notifications enabled');
    expect(find.text('Allow notifications'), findsNothing);
    await reveal(tester, 'Continue');
    expect(find.text('Continue'), findsOneWidget);
  });
  testWidgets(
      'Permanently denied permission opens settings and repeated taps do not duplicate',
      (tester) async {
    final pending = Completer<bool>();
    var calls = 0;
    messenger.setMockMethodCallHandler(TubeDeviceSetupService.channel,
        (call) async {
      if (call.method == 'status') {
        return {...disabled, 'canRequestNotifications': false};
      }
      expect(call.method, 'openNotificationSettings');
      calls++;
      return pending.future;
    });
    await tester.pumpWidget(const MaterialApp(home: TubeDeviceSetupScreen()));
    await tester.pumpAndSettle();
    await reveal(tester, 'Notification settings');
    await tester.tap(find.text('Notification settings'));
    await tester.pump();
    await tester.tap(find.text('Notification settings'));
    expect(calls, 1);
    pending.complete(true);
    await tester.pumpAndSettle();
  });
  testWidgets('Settings failures remain recoverable', (tester) async {
    messenger.setMockMethodCallHandler(TubeDeviceSetupService.channel,
        (call) async => call.method == 'status' ? disabled : false);
    await tester.pumpWidget(const MaterialApp(home: TubeDeviceSetupScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up supported links'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not open the Android permission'),
        findsOneWidget);
  });
  testWidgets(
      'YouTube Music defaults are offered only for an unselected music domain',
      (tester) async {
    final actions = <String>[];
    messenger.setMockMethodCallHandler(TubeDeviceSetupService.channel,
        (call) async {
      if (call.method == 'status') {
        return {
          ...disabled,
          'youtubeMusicInstalled': true,
          'domains': {'music.youtube.com': 'disabled'}
        };
      }
      actions.add(call.method);
      return true;
    });
    await tester.pumpWidget(const MaterialApp(home: TubeDeviceSetupScreen()));
    await tester.pumpAndSettle();
    await reveal(tester, 'YouTube Music link defaults');
    await tester.tap(find.text('YouTube Music link defaults'));
    await tester.pumpAndSettle();
    expect(actions, ['openYouTubeMusicSettings']);
  });
  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    testWidgets('Setup stays scrollable at $size and large text',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      messenger.setMockMethodCallHandler(
          TubeDeviceSetupService.channel, (_) async => disabled);
      await tester.pumpWidget(MaterialApp(
          builder: (_, child) => MediaQuery(
              data: MediaQueryData(
                  size: size, textScaler: const TextScaler.linear(2)),
              child: child!),
          home: const TubeDeviceSetupScreen(initialSetup: true)));
      await tester.pumpAndSettle();
      await reveal(tester, 'Continue for now');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'Cold link remains queued through device setup, then shows the existing chooser',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final setup = TubeDeviceSetupService()..reset();
    final profile = TubeUserProfileService();
    profile.onboardingCompleted = true;
    final inbox = [
      {'id': 'one', 'url': 'https://youtu.be/abcdefghijk?t=30'}
    ];
    messenger.setMockMethodCallHandler(TubeLinkService.channel,
        (call) async => call.method == 'pending' ? inbox : true);
    final player = TubePlayerProvider();
    final shorts = TubeShortsController();
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: player),
          ChangeNotifierProvider.value(value: shorts)
        ],
        child: MaterialApp(
            navigatorKey: key,
            builder: (_, child) =>
                TubeLinkHandler(navigatorKey: key, child: child!),
            home: const Scaffold(body: Text('Setup fixture')))));
    await tester.pumpAndSettle();
    expect(find.text('Open YouTube video'), findsNothing);
    expect(inbox.length, 1);
    await setup.init(platform: TargetPlatform.linux);
    await tester.pumpAndSettle();
    expect(find.text('Play in ShreyX Tube'), findsOneWidget);
    expect(find.text('Open in YouTube'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    player.dispose();
    shorts.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
