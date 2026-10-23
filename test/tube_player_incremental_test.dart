import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shreyx_tube/models/tube_models.dart';
import 'package:shreyx_tube/providers/tube_player_provider.dart';
import 'package:shreyx_tube/screens/tube_watch_screen.dart';
import 'package:shreyx_tube/providers/tube_shorts_controller.dart';
import 'package:shreyx_tube/services/tube_youtube_link.dart';
import 'package:shreyx_tube/services/tube_link_service.dart';
import 'package:shreyx_tube/services/tube_user_profile_service.dart';
import 'package:shreyx_tube/services/tube_stream_resolver.dart';
import 'package:shreyx_tube/widgets/tube_link_handler.dart';
import 'package:shreyx_tube/widgets/tube_mini_player.dart';
import 'package:shreyx_tube/widgets/tube_player_gestures.dart';

class TestPlayer extends TubePlayerProvider {
  bool fullscreen = false;
  int plays = 0, pauses = 0, collapses = 0;
  int? startMs;
  TubeVideoItem? requested;
  String? failure;
  Duration? lastSeek;
  @override
  void seek(Duration position) => lastSeek = position;
  @override
  String? get errorMessage => failure;
  @override
  Future<void> playVideo(TubeVideoItem video,
      {int? startPositionMs, bool expand = true}) async {
    ++plays;
    requested = video;
    startMs = startPositionMs;
  }

  @override
  void pause() {
    ++pauses;
  }

  @override
  void collapsePlayer() {
    ++collapses;
  }

  @override
  void togglePlayPause() {
    ++pauses;
  }

  @override
  bool get isFullscreen => fullscreen;
  @override
  bool get isLoading => false;
  @override
  TubeVideoItem get currentVideoItem => const TubeVideoItem(
      id: 'abcdefghijk',
      title: 'Fixture',
      channelTitle: 'Creator',
      channelId: '');
}

class SurfaceProbe extends StatefulWidget {
  const SurfaceProbe({super.key});
  @override
  State<SurfaceProbe> createState() => _SurfaceProbeState();
}

class _SurfaceProbeState extends State<SurfaceProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class TestShorts extends TubeShortsController {
  TubeVideoItem? requested;
  int? startMs;
  @override
  void selectChannelShorts(List<TubeVideoItem> items, int index,
      {int startPositionMs = 0}) {
    requested = items[index];
    startMs = startPositionMs;
  }

  @override
  void activateScreen({TubePlayerProvider? mainPlayerProvider}) {}
  @override
  void deactivateScreen() {}
}

Future<void> incoming(WidgetTester tester) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  await messenger.handlePlatformMessage(
      'com.shreyx.tube/links',
      const StandardMethodCodec()
          .encodeMethodCall(const MethodCall('incoming')),
      (_) {});
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    for (final channel in [
      'com.shreyx.tube/player_channel',
      'com.shreyx.tube/shorts_player_channel'
    ]) {
      messenger.setMockMethodCallHandler(
          MethodChannel(channel), (_) async => true);
    }
    TubeLinkService.clear();
  });

  testWidgets('Fullscreen exit before landscape metrics settle has no error',
      (tester) async {
    tester.view.physicalSize = const Size(2340, 1080);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final player = TestPlayer();
    await tester.pumpWidget(ChangeNotifierProvider<TubePlayerProvider>.value(
        value: player,
        child: MaterialApp(
            home: TubeWatchScreen(onCollapse: () => ++player.collapses))));
    expect(tester.takeException(), isNull);
    for (var cycle = 0; cycle < 5; cycle++) {
      player.fullscreen = true;
      player.notifyListeners();
      await tester.pump();
      tester.view.physicalSize = const Size(2340, 1080);
      await tester.pump();
      player.fullscreen = false;
      player.notifyListeners();
      await tester.pump();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(1080, 2340);
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    await tester.drag(find.byType(Slider), const Offset(90, 0));
    await tester.pump();
    expect(player.lastSeek, isNotNull);
    expect(player.collapses, 0);
    player.failure = 'Persistent network failure';
    player.notifyListeners();
    await tester.pump();
    expect(find.text('Persistent network failure'), findsOneWidget);
    expect(find.text('Open in YouTube'), findsOneWidget);
    String? opened;
    messenger.setMockMethodCallHandler(TubeLinkService.channel, (call) async {
      if (call.method == 'openYouTube') opened = call.arguments['url'];
      return true;
    });
    await tester.tap(find.text('Open in YouTube'));
    await tester.pump();
    expect(opened, 'https://www.youtube.com/watch?v=abcdefghijk');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    player.dispose();
  });

  const variants = [
    'https://youtube.com/watch?v=abcdefghijk',
    'https://www.youtube.com/watch?v=abcdefghijk&list=PLexample&feature=share&t=1m30s',
    'http://m.youtube.com/watch?v=abcdefghijk&start=90',
    'https://youtu.be/abcdefghijk?t=90',
    'https://youtube.com/shorts/abcdefghijk?t=90s',
    'https://youtube.com/live/abcdefghijk?si=share',
    'https://music.youtube.com/watch?v=abcdefghijk#t=90',
    'www.youtube.com/watch?v=abcdefghijk&time_continue=90',
  ];
  for (final url in variants) {
    test('Parses supported URL $url', () {
      final link = TubeYoutubeLink.parse(url)!;
      expect(link.videoId, 'abcdefghijk');
      if (url.contains('90') || url.contains('1m30s')) {
        expect(link.startSeconds, 90);
      }
      expect(link.originalUrl, contains('abcdefghijk'));
    });
  }
  for (final url in [
    'https://youtube.com.evil/watch?v=abcdefghijk',
    'https://evil.com/watch?v=abcdefghijk',
    'https://youtube.com@evil.com/watch?v=abcdefghijk',
    'javascript:abcdefghijk',
    'https://youtu.be/abcdefghijkEXTRA',
    'https://youtube.com/watch?v=bad',
    'https://youtube.com/channel/abcdefghijk',
    'https://youtu.be/abcdefghijk/extra',
  ]) {
    test('Rejects unsupported URL $url',
        () => expect(TubeYoutubeLink.parse(url), isNull));
  }
  test(
      'Timestamp validation retains zero, hours and fragments, rejects negative/oversized',
      () {
    expect(TubeYoutubeLink.parseTimestamp('0'), 0);
    expect(TubeYoutubeLink.parseTimestamp('1h2m3s'), 3723);
    expect(TubeYoutubeLink.parseTimestamp('-1'), isNull);
    expect(TubeYoutubeLink.parseTimestamp('999999999'), isNull);
    expect(TubeYoutubeLink.parseTimestamp('1mgarbage'), isNull);
  });
  test(
      'Generic extraction, forbidden HTTP and title keywords do not imply membership',
      () {
    expect(
        TubeStreamResolver.isMembershipFailure(
            StateError('Explaining members-only videos')),
        isFalse);
    expect(
        TubeStreamResolver.isMembershipFailure(PlatformException(
            code: 'network', message: '403 join this channel')),
        isFalse);
    expect(
        TubeStreamResolver.isMembershipFailure(
            VideoUnplayableException('Streams unavailable')),
        isFalse);
    expect(
        TubeStreamResolver.isMembershipFailure(
            VideoUnplayableException('Only available to members')),
        isTrue);
    expect(
        TubeStreamResolver.isMembershipFailure(
            const TubeMembersOnlyException()),
        isTrue);
  });
  testWidgets(
      'Compact player is 84dp, controls do not expand, double tap resizes',
      (tester) async {
    final player = TestPlayer();
    var expanded = 0;
    await tester.pumpWidget(ChangeNotifierProvider<TubePlayerProvider>.value(
        value: player,
        child: MaterialApp(
            home: Scaffold(
                body: TubeFloatingMiniPlayer(
                    onExpand: () => ++expanded,
                    videoSurface: const ColoredBox(
                        key: ValueKey('actual-surface'),
                        color: Colors.blue))))));
    final mini = find.byKey(const ValueKey('floating-player'));
    expect(tester.getSize(mini).height, 84);
    expect(find.byKey(const ValueKey('actual-surface')), findsOneWidget);
    await tester.tap(find.byTooltip('Play/Pause'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(player.pauses, 1);
    expect(expanded, 0);
    final point = tester.getTopLeft(mini) + const Offset(30, 30);
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.getSize(mini).height, greaterThan(84));
    expect(expanded, 0);
    await tester.pumpWidget(const SizedBox());
    player.dispose();
  });
  testWidgets(
      'Mini dragging stays above navigation; edge hide has an accessible restore button',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final player = TestPlayer();
    final surfaceKey = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider<TubePlayerProvider>.value(
        value: player,
        child: MaterialApp(
            home: Scaffold(
                body: TubeFloatingMiniPlayer(
                    onExpand: () {},
                    videoSurface: SurfaceProbe(key: surfaceKey))))));
    final originalSurface = surfaceKey.currentState;
    final mini = find.byKey(const ValueKey('floating-player'));
    expect(tester.getBottomRight(mini).dy, lessThanOrEqualTo(720));
    final gesture = await tester
        .startGesture(tester.getTopLeft(mini) + const Offset(25, 25));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(180, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(find.byTooltip('Show mini-player'), findsOneWidget);
    expect(surfaceKey.currentState, same(originalSurface));
    await tester.tap(find.byTooltip('Show mini-player'));
    await tester.pump();
    expect(mini, findsOneWidget);
    expect(surfaceKey.currentState, same(originalSurface));
    expect(tester.getBottomRight(mini).dx, lessThanOrEqualTo(392));
    await tester.pumpWidget(const SizedBox());
    player.dispose();
  });
  testWidgets(
      'Two-finger zoom does not collapse; edge vertical drag adjusts volume',
      (tester) async {
    var collapsed = 0;
    double zoom = 1, volume = 0, brightness = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 400,
                height: 300,
                child: TubePlayerGestures(
                    onSingleTap: () {},
                    onCollapse: () => ++collapsed,
                    onDoubleTapLeft: () {},
                    onDoubleTapRight: () {},
                    onZoomChanged: (v) => zoom = v,
                    onBrightnessChanged: (v) => brightness = v,
                    onVolumeChanged: (v) => volume = v,
                    child: const ColoredBox(color: Colors.black))))));
    final first = await tester.startGesture(const Offset(120, 150), pointer: 1);
    final second =
        await tester.startGesture(const Offset(250, 150), pointer: 2);
    await first.moveBy(const Offset(-60, 0));
    await second.moveBy(const Offset(60, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pump();
    expect(zoom, greaterThan(1));
    expect(collapsed, 0);
    await tester.dragFrom(const Offset(370, 100), const Offset(0, 100));
    await tester.pump();
    expect(volume, greaterThan(0));
    expect(collapsed, 0);
    await tester.dragFrom(const Offset(30, 160), const Offset(0, -50));
    await tester.pump();
    expect(brightness, greaterThan(0));
    expect(collapsed, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
  });
  testWidgets('Confirmed double taps seek only on their respective sides',
      (tester) async {
    var left = 0, right = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 400,
                height: 300,
                child: TubePlayerGestures(
                    onSingleTap: () {},
                    onDoubleTapLeft: () => ++left,
                    onDoubleTapRight: () => ++right,
                    child: const SizedBox.expand())))));
    for (final x in [80.0, 320.0]) {
      await tester.tapAt(Offset(x, 120));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(Offset(x, 120));
      await tester.pump(const Duration(milliseconds: 700));
    }
    expect(left, 1);
    expect(right, 1);
    await tester.pumpWidget(const SizedBox());
  });
  for (final cold in [true, false]) {
    testWidgets(
        '${cold ? 'Cold' : 'Warm'} link choice preserves timestamp and original URL',
        (tester) async {
      final inbox = <Map<String, String>>[];
      final opened = <String>[];
      const url =
          'https://www.youtube.com/watch?v=abcdefghijk&t=90&feature=share';
      if (cold) inbox.add({'id': 'one', 'url': url});
      messenger.setMockMethodCallHandler(TubeLinkService.channel, (call) async {
        if (call.method == 'pending') return List.of(inbox);
        if (call.method == 'ack') {
          inbox.removeWhere((v) => v['id'] == call.arguments['id']);
        }
        if (call.method == 'openYouTube') {
          opened.add(call.arguments['url']);
          return true;
        }
        return null;
      });
      TubeUserProfileService().onboardingCompleted = true;
      final player = TestPlayer();
      final shorts = TestShorts();
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<TubePlayerProvider>.value(value: player),
            ChangeNotifierProvider<TubeShortsController>.value(value: shorts)
          ],
          child: MaterialApp(
              navigatorKey: key,
              builder: (_, child) =>
                  TubeLinkHandler(navigatorKey: key, child: child!),
              home: const Scaffold(body: Text('Home fixture')))));
      await tester.pump();
      if (!cold) {
        inbox.add({'id': 'one', 'url': url});
        await incoming(tester);
      }
      await tester.pumpAndSettle();
      expect(find.text('Open YouTube video'), findsOneWidget);
      await tester.tap(find.text('Play in ShreyX Tube'));
      await tester.pumpAndSettle();
      expect(player.plays, 1);
      expect(player.startMs, 90000);
      expect(inbox, isEmpty);
      inbox.add({'id': 'two', 'url': url});
      await incoming(tester);
      await tester.tap(find.text('Open in YouTube'));
      await tester.pumpAndSettle();
      expect(opened, [url]);
      expect(player.plays, 1);
      player.failure = 'This video is unavailable.';
      player.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('This video is unavailable.'), findsOneWidget);
      await tester.tap(find.text('Open in YouTube'));
      await tester.pump();
      expect(opened, [url, url]);
      await tester.pumpWidget(const SizedBox());
      player.dispose();
      shorts.dispose();
    });
  }

  testWidgets(
      'Onboarding retains queued links and rapid distinct links choose players in order',
      (tester) async {
    final inbox = <Map<String, String>>[
      {'id': 'first', 'url': 'https://youtube.com/watch?v=abcdefghijk&t=0'},
      {'id': 'second', 'url': 'https://youtube.com/shorts/lmnopqrstuv?t=12'},
      {'id': 'third', 'url': 'https://youtube.com/live/archived001?t=45'},
    ];
    messenger.setMockMethodCallHandler(TubeLinkService.channel, (call) async {
      if (call.method == 'pending') return List.of(inbox);
      if (call.method == 'ack') {
        inbox.removeWhere((v) => v['id'] == call.arguments['id']);
      }
      return true;
    });
    final profile = TubeUserProfileService();
    profile.onboardingCompleted = false;
    final player = TestPlayer();
    final shorts = TestShorts();
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<TubePlayerProvider>.value(value: player),
          ChangeNotifierProvider<TubeShortsController>.value(value: shorts)
        ],
        child: MaterialApp(
            navigatorKey: key,
            builder: (_, child) =>
                TubeLinkHandler(navigatorKey: key, child: child!),
            home: const Scaffold(body: Text('Onboarding fixture')))));
    await tester.pumpAndSettle();
    expect(find.text('Open YouTube video'), findsNothing);
    expect(inbox.length, 3);
    profile.onboardingCompleted = true;
    profile.notifyListeners();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play in ShreyX Tube'));
    await tester.pumpAndSettle();
    expect(player.requested!.id, 'abcdefghijk');
    expect(player.startMs, 0);
    expect(find.text('Open YouTube video'), findsOneWidget);
    await tester.tap(find.text('Play in ShreyX Tube'));
    await tester.pumpAndSettle();
    expect(shorts.requested!.id, 'lmnopqrstuv');
    expect(shorts.requested!.isShort, isTrue);
    expect(shorts.startMs, 12000);
    await tester.tap(find.text('Play in ShreyX Tube'));
    await tester.pumpAndSettle();
    expect(player.requested!.id, 'archived001');
    expect(player.requested!.isLive,
        isFalse); // Resolve actual live/archive metadata.
    expect(player.startMs, 45000);
    expect(inbox, isEmpty);
    expect(player.plays, 2);
    await tester.pumpWidget(const SizedBox());
    player.dispose();
    shorts.dispose();
  });
  testWidgets(
      'Pinch changes mini dimensions; portrait and landscape keep navigation clear',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final player = TestPlayer();
    await tester.pumpWidget(ChangeNotifierProvider<TubePlayerProvider>.value(
        value: player,
        child: MaterialApp(
            home: Scaffold(
                body: TubeFloatingMiniPlayer(
                    onExpand: () {}, videoSurface: const SizedBox())))));
    final mini = find.byKey(const ValueKey('floating-player'));
    final origin = tester.getTopLeft(mini);
    final first =
        await tester.startGesture(origin + const Offset(35, 35), pointer: 1);
    final second =
        await tester.startGesture(origin + const Offset(135, 35), pointer: 2);
    await first.moveBy(const Offset(-30, 0));
    await second.moveBy(const Offset(30, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(mini).height, greaterThan(84));
    tester.view.physicalSize = const Size(800, 400);
    await tester.pump();
    expect(tester.getBottomRight(mini).dy, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
    player.dispose();
  });
}
