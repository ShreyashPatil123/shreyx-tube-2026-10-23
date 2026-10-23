import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shreyx_tube/models/tube_models.dart';
import 'package:shreyx_tube/models/tube_stream.dart';
import 'package:shreyx_tube/providers/tube_player_provider.dart';
import 'package:shreyx_tube/services/tube_home_feed_service.dart';
import 'package:shreyx_tube/services/tube_innertube_client.dart';
import 'package:shreyx_tube/services/tube_session_service.dart';
import 'package:shreyx_tube/services/tube_storage_service.dart';
import 'package:shreyx_tube/services/tube_stream_resolver.dart';

const item = TubeVideoItem(
    id: 'abcdefghijk',
    title: 'Fixture',
    channelTitle: 'Fixture',
    channelId: 'UCfixture');
TubeResolvedVideo resolved({bool account = false}) => TubeResolvedVideo(
    videoId: item.id,
    title: item.title,
    uploader: item.channelTitle,
    durationSeconds: 120,
    thumbnailUrl: '',
    videoStreams: [
      for (final h in [720, 480, 360])
        TubeVideoStream(
            url: 'https://fixture.googlevideo.com/$h',
            resolution: '${h}p',
            width: h * 16 ~/ 9,
            height: h,
            container: 'mp4',
            mimeType: 'video/mp4',
            codec: 'avc1',
            fps: 30,
            bitrate: h * 1000,
            isVideoOnly: false,
            deliveryMethod: 'PROGRESSIVE',
            manifestType: 'PROGRESSIVE')
    ],
    audioStreams: [],
    subtitles: [],
    extractorSource: account ? 'youtube_account' : 'fixture');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const native = MethodChannel('com.shreyx.tube/player_channel');
  final session = TubeSessionService();
  late List<MethodCall> calls;
  late DateTime now;
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await TubeStorageService().init();
    await session.init();
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.shreyx.tube/shorts_player_channel'),
        (_) async => true);
  });
  setUp(() async {
    await TubeStorageService().setIncognito(false);
    await session.clearSession();
    calls = [];
    now = DateTime(2026);
    messenger.setMockMethodCallHandler(native, (c) async {
      calls.add(c);
      return c.method == 'loadMedia' ? {'ok': true} : null;
    });
  });
  Future<void> connect() async {
    await session.savePrivateConnection(
        {'SID': 'fixture', 'SAPISID': 'fixture'},
        name: 'Fixture', userAgent: 'fixture-webview');
  }

  TubePlayerProvider player({bool deny = false}) {
    final p = TubePlayerProvider(
        clock: () => now,
        resolver: TubeStreamResolver.withLoader((_) async => resolved(),
            accountLoader: (_) async {
          if (deny) throw const TubeMembersOnlyException();
          return resolved(account: true);
        }),
        homeFeedService: TubeHomeFeedService.withClient(TubeInnertubeClient
            .withClient(MockClient((_) async => http.Response(
                '{"responseContext":{"mainAppWebResponseContext":{"loggedOut":false}},"contents":{"twoColumnWatchNextResults":{"secondaryResults":{"secondaryResults":{"results":[]}}}}}',
                200)))));
    addTearDown(p.dispose);
    return p;
  }

  Future<void> progress({required bool buffering}) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
        native.name,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall('onProgressUpdate', {
          'positionMs': 10000,
          'durationMs': 120000,
          'bufferedMs': 10200,
          'isPlaying': !buffering,
          'isBuffering': buffering
        })),
        (_) => done.complete());
    await done.future;
    await Future<void>.delayed(Duration.zero);
  }

  test('Eligible membership uses native Media3 and stops on account disconnect',
      () async {
    await connect();
    final p = player();
    await p.playVideo(item.copyWith(isMembersOnly: true));
    final load = calls.singleWhere((c) => c.method == 'loadMedia');
    expect(load.arguments['requiresAccount'], isTrue);
    expect(p.isMembersOnly, isFalse);
    expect(p.currentVideoItem!.isMembersOnly, isTrue);
    await session.clearSession();
    await Future<void>.delayed(Duration.zero);
    expect(p.isMembersOnly, isTrue);
    expect(p.currentStream, isNull);
    expect(calls.any((c) => c.method == 'stop'), isTrue);
  });
  test(
      'Denied account membership does not recurse, load media or hide the restriction',
      () async {
    await connect();
    final p = player(deny: true);
    await p.playVideo(item.copyWith(isMembersOnly: true));
    expect(p.isMembersOnly, isTrue);
    expect(p.errorMessage, contains('eligible'));
    expect(calls.where((c) => c.method == 'loadMedia'), isEmpty);
  });
  test(
      'Incognito stops active account playback while preserving the connection',
      () async {
    await connect();
    final p = player();
    await p.playVideo(item.copyWith(isMembersOnly: true));
    await TubeStorageService().setIncognito(true);
    expect(session.isLoggedIn, isTrue);
    expect(session.usesPrivateFeed, isFalse);
    expect(p.currentStream, isNull);
    expect(p.isMembersOnly, isTrue);
  });
  test(
      'Repeated Auto starvation lowers quality while preserving position and playback intent',
      () async {
    final p = player();
    await p.playVideo(item);
    now = now.add(const Duration(seconds: 6));
    for (var i = 0; i < 3; i++) {
      await progress(buffering: false);
      await progress(buffering: true);
      now = now.add(const Duration(seconds: 2));
    }
    final loads = calls.where((c) => c.method == 'loadMedia').toList();
    expect(loads, hasLength(2));
    expect(p.currentStream!.height, 480);
    expect(loads.last.arguments['startPositionMs'], 10000);
    expect(loads.last.arguments['autoPlay'], isTrue);
    expect(p.selectedQuality, 'Auto');
    now = now.add(const Duration(seconds: 6));
    for (var i = 0; i < 3; i++) {
      await progress(buffering: false);
      await progress(buffering: true);
      now = now.add(const Duration(seconds: 2));
    }
    expect(calls.where((c) => c.method == 'loadMedia'), hasLength(2));
  });
  for (final connected in [false, true]) {
    test(
        'Restoring native account media requires an active connection: $connected',
        () async {
      if (connected) await connect();
      messenger.setMockMethodCallHandler(native, (c) async {
        calls.add(c);
        return c.method == 'getStatus'
            ? {
                'hasMedia': true,
                'requiresAccount': true,
                'videoId': item.id,
                'title': item.title,
                'isPlaying': true
              }
            : null;
      });
      final p = player();
      await p.restoreNativePlayback();
      expect(p.isPlayerVisible, connected);
      if (connected) {
        expect(p.currentVideoItem!.isMembersOnly, isTrue);
        await session.clearSession();
        expect(p.isMembersOnly, isTrue);
      }
      expect(calls.any((c) => c.method == 'stop'), isTrue);
    });
  }
  for (final manual in [true, false]) {
    test(
        '${manual ? 'Manual quality' : 'Paused playback'} never auto-reloads after buffer events',
        () async {
      final p = player();
      await p.playVideo(item);
      await progress(buffering: false);
      if (manual) {
        await p.changeQuality('720p');
      } else {
        p.pause();
      }
      final before = calls.where((c) => c.method == 'loadMedia').length;
      now = now.add(const Duration(seconds: 6));
      for (var i = 0; i < 3; i++) {
        await progress(buffering: false);
        await progress(buffering: true);
        now = now.add(const Duration(seconds: 3));
      }
      expect(calls.where((c) => c.method == 'loadMedia').length, before);
    });
  }
}
