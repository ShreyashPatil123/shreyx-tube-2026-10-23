import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shreyx_tube/services/tube_authorized_playback.dart';
import 'package:shreyx_tube/services/tube_innertube_client.dart';
import 'package:shreyx_tube/services/tube_session_service.dart';
import 'package:shreyx_tube/services/tube_storage_service.dart';
import 'package:shreyx_tube/services/tube_stream_resolver.dart';

class _Store implements TubeSessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> delete() async => value = null;
}

Map<String, dynamic> granted({bool cipher = false, bool drm = false}) => {
      'playabilityStatus': {'status': 'OK'},
      'videoDetails': {
        'videoId': 'abcdefghijk',
        'title': 'Authorized fixture',
        'author': 'Fixture',
        'lengthSeconds': '120'
      },
      'streamingData': <String, dynamic>{
        if (drm)
          'licenseInfos': [
            {'drmFamily': 'WIDEVINE'}
          ],
        'formats': [
          {
            'mimeType': 'video/mp4; codecs="avc1, mp4a"',
            'width': 1280,
            'height': 720,
            'qualityLabel': '720p',
            if (!cipher)
              'url':
                  'https://fixture.googlevideo.com/videoplayback?authorized=fixture',
            if (cipher) 'signatureCipher': 'synthetic-cipher-only'
          }
        ],
        'adaptiveFormats': [
          {
            'mimeType': 'audio/mp4; codecs="mp4a"',
            'url': 'https://fixture.googlevideo.com/audio',
            'bitrate': 128000
          },
          {
            'mimeType': 'video/mp4; codecs="avc1"',
            'url': 'https://fixture.googlevideo.com/video',
            'height': 480,
            'qualityLabel': '480p'
          }
        ]
      }
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TubeSessionService session;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await TubeStorageService().init();
  });
  setUp(() async {
    await TubeStorageService().setIncognito(false);
    session = TubeSessionService.withStore(_Store(), webClientId: '');
    await session.savePrivateConnection(
        {'SID': 'fixture', 'SAPISID': 'fixture'},
        name: 'Fixture', userAgent: 'genuine-fixture');
  });
  TubeAuthorizedPlayback playback(
          Future<http.Response> Function(http.Request) handler) =>
      TubeAuthorizedPlayback(
          client: TubeInnertubeClient.withClient(MockClient(handler),
              session: session));
  test(
      'Eligible account uses fixed authenticated player request and authorized native formats',
      () async {
    final result = await playback((request) async {
      expect(request.url.host, 'www.youtube.com');
      expect(request.url.path, '/youtubei/v1/player');
      expect(request.followRedirects, isFalse);
      expect(request.headers['Cookie'], contains('SID=fixture'));
      expect(jsonDecode(request.body)['videoId'], 'abcdefghijk');
      return http.Response(jsonEncode(granted()), 200);
    }).resolve('abcdefghijk');
    expect(result.extractorSource, 'youtube_account');
    expect(result.getBestStream('Auto')!.height, 720);
    expect(result.lowerStream(result.getBestStream('Auto')!)!.pairedAudioUrl,
        'https://fixture.googlevideo.com/audio');
  });
  test('YouTube membership denial stays restricted', () async {
    await expectLater(
        playback((_) async => http.Response(
            jsonEncode({
              'playabilityStatus': {
                'status': 'UNPLAYABLE',
                'reason': 'Join this channel to watch members-only videos'
              }
            }),
            200)).resolve('abcdefghijk'),
        throwsA(isA<TubeMembersOnlyException>()));
  });
  test('Generic server failure is not classified as missing membership',
      () async {
    await expectLater(
        playback((_) async => http.Response('', 503)).resolve('abcdefghijk'),
        throwsA(isA<StateError>()));
  });
  test('Protected streams are left to YouTube', () async {
    await expectLater(
        playback(
                (_) async => http.Response(jsonEncode(granted(drm: true)), 200))
            .resolve('abcdefghijk'),
        throwsA(isA<TubeMembersOnlyException>()
            .having((e) => e.message, 'reason', contains('protected'))));
  });
  test('Cipher-only formats do not pretend to be playable', () async {
    final data = granted(cipher: true);
    (data['streamingData'] as Map)['adaptiveFormats'] = [];
    await expectLater(
        playback((_) async => http.Response(jsonEncode(data), 200))
            .resolve('abcdefghijk'),
        throwsA(isA<TubeMembersOnlyException>().having(
            (e) => e.message, 'reason', contains('native-compatible'))));
  });
  test('Incognito sends no account playback request', () async {
    await TubeStorageService().setIncognito(true);
    var calls = 0;
    await expectLater(
        playback((_) async {
          calls++;
          return http.Response('{}', 200);
        }).resolve('abcdefghijk'),
        throwsA(isA<TubeMembersOnlyException>()));
    expect(calls, 0);
    await TubeStorageService().setIncognito(false);
  });
  test('Account switch discards an in-flight authorized playback response',
      () async {
    final gate = Completer<http.Response>();
    final started = Completer<void>();
    final future = playback((_) {
      started.complete();
      return gate.future;
    }).resolve('abcdefghijk');
    await started.future;
    final rejected = expectLater(future, throwsA(isA<StateError>()));
    await session.clearSession();
    gate.complete(http.Response(jsonEncode(granted()), 200));
    await rejected;
  });
  test('Only first-party HTTPS stream URLs are accepted', () {
    for (final value in [
      'http://fixture.googlevideo.com/v',
      'https://googlevideo.com.evil/v',
      'https://user:password@www.youtube.com/v',
      'https://www.youtube.com:444/v',
      'file:///v'
    ]) {
      expect(TubeAuthorizedPlayback.streamUrl(value), isNull);
    }
    expect(
        TubeAuthorizedPlayback.streamUrl('https://manifest.googlevideo.com/v'),
        isNotNull);
  });
  test('Unexpected video identity cannot activate playback', () async {
    final data = granted();
    (data['videoDetails'] as Map)['videoId'] = 'different01';
    await expectLater(
        playback((_) async => http.Response(jsonEncode(data), 200))
            .resolve('abcdefghijk'),
        throwsA(isA<StateError>()));
  });
}
