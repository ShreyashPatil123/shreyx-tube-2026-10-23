import '../models/tube_stream.dart';
import 'tube_innertube_client.dart';
import 'tube_stream_resolver.dart';

/// Uses only streams YouTube explicitly grants to the connected account.
/// Ciphered/DRM formats are not bypassed or decrypted by this path.
class TubeAuthorizedPlayback {
  TubeAuthorizedPlayback({TubeInnertubeClient? client})
      : _client = client ?? TubeInnertubeClient();
  final TubeInnertubeClient _client;

  static String? streamUrl(dynamic value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return null;
    }
    final host = uri.host.toLowerCase();
    return host == 'youtube.com' ||
            host.endsWith('.youtube.com') ||
            host == 'googlevideo.com' ||
            host.endsWith('.googlevideo.com')
        ? value
        : null;
  }

  Future<TubeResolvedVideo> resolve(String id) async {
    if (!_client.isConnected) throw const TubeMembersOnlyException();
    final data = await _client.authenticatedPlayer(id);
    final status = data['playabilityStatus'] as Map? ?? {};
    if (status['status'] != 'OK') {
      final reason = (status['reason'] ?? '').toString().toLowerCase();
      if (status['status'] == 'LOGIN_REQUIRED' ||
          reason.contains('member') ||
          reason.contains('join this channel')) {
        throw const TubeMembersOnlyException();
      }
      throw StateError(
          'YouTube did not grant playback for this video. Open it in YouTube for details.');
    }
    final details = data['videoDetails'] as Map? ?? {};
    if (details['videoId'] != id) {
      throw StateError('YouTube returned a different video. Retry.');
    }
    final streaming = data['streamingData'] as Map? ?? {};
    if ((streaming['licenseInfos'] as List? ?? []).isNotEmpty) {
      throw const TubeMembersOnlyException(
          'This video requires protected playback. Open it in YouTube.');
    }
    final audio = <TubeAudioStream>[];
    final video = <TubeVideoStream>[];
    for (final adaptive in [false, true]) {
      for (final raw
          in (streaming[adaptive ? 'adaptiveFormats' : 'formats'] as List? ??
              [])) {
        if (raw is! Map || (raw['drmFamilies'] as List? ?? []).isNotEmpty) {
          continue;
        }
        final url = streamUrl(raw['url']);
        if (url == null) {
          continue; // Cipher-only formats cannot be handed to Media3.
        }
        final mime = (raw['mimeType'] ?? '').toString();
        final codec =
            RegExp('codecs="([^"]+)"').firstMatch(mime)?.group(1) ?? '';
        final container = mime.contains('webm') ? 'webm' : 'mp4';
        if (mime.startsWith('audio/')) {
          audio.add(TubeAudioStream(
              url: url,
              container: container,
              mimeType: mime.split(';').first,
              codec: codec,
              bitrate: (raw['bitrate'] as num?)?.toInt() ?? 0));
        } else if (mime.startsWith('video/')) {
          video.add(TubeVideoStream(
              url: url,
              resolution:
                  (raw['qualityLabel'] ?? '${raw['height'] ?? 0}p').toString(),
              width: (raw['width'] as num?)?.toInt() ?? 0,
              height: (raw['height'] as num?)?.toInt() ?? 0,
              container: container,
              mimeType: mime.split(';').first,
              codec: codec,
              fps: (raw['fps'] as num?)?.toInt() ?? 30,
              bitrate: (raw['bitrate'] as num?)?.toInt() ?? 0,
              isVideoOnly: adaptive,
              deliveryMethod: adaptive ? 'DASH_ADAPTIVE' : 'PROGRESSIVE',
              manifestType: adaptive ? 'ADAPTIVE_VIDEO_ONLY' : 'PROGRESSIVE'));
        }
      }
    }
    audio.sort((a, b) => b.bitrate.compareTo(a.bitrate));
    for (final stream in video.where((v) => v.isVideoOnly)) {
      if (audio.isNotEmpty) stream.pairedAudioUrl = audio.first.url;
    }
    video.removeWhere((v) => v.isVideoOnly && v.pairedAudioUrl == null);
    final hls = streamUrl(streaming['hlsManifestUrl']);
    final dash = streamUrl(streaming['dashManifestUrl']);
    if (video.isEmpty && hls == null && dash == null) {
      throw const TubeMembersOnlyException(
          'Your account may have access, but YouTube did not provide a native-compatible stream. Open it in YouTube.');
    }
    if (video.isEmpty) {
      video.add(TubeVideoStream(
          url: hls ?? dash!,
          resolution: 'Auto',
          width: 0,
          height: 0,
          container: hls != null ? 'm3u8' : 'mpd',
          mimeType:
              hls != null ? 'application/x-mpegURL' : 'application/dash+xml',
          codec: '',
          fps: 30,
          bitrate: 0,
          isVideoOnly: false,
          deliveryMethod: hls != null ? 'HLS' : 'DASH_MPD',
          manifestType: 'MANIFEST'));
    }
    return TubeResolvedVideo(
        videoId: id,
        title: (details['title'] ?? 'YouTube video').toString(),
        uploader: (details['author'] ?? '').toString(),
        uploaderUrl:
            'https://www.youtube.com/channel/${details['channelId'] ?? ''}',
        durationSeconds: int.tryParse('${details['lengthSeconds']}') ?? 0,
        thumbnailUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
        videoStreams: video,
        audioStreams: audio,
        subtitles: [],
        hlsUrl: hls,
        dashMpdUrl: dash,
        isLive: details['isLiveContent'] == true,
        extractorSource: 'youtube_account');
  }
}
