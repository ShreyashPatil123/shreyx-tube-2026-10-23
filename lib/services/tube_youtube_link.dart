enum TubeLinkKind { video, shorts, live }

/// Exact host/path validation; parameters are parsed separately from the video ID.
class TubeYoutubeLink {
  final String originalUrl, videoId;
  final TubeLinkKind kind;
  final int? startSeconds;
  const TubeYoutubeLink(
      this.originalUrl, this.videoId, this.kind, this.startSeconds);
  static final _id = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static const hosts = {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtu.be',
    'www.youtu.be'
  };
  static bool isVideoId(String input) => _id.hasMatch(input);
  static TubeYoutubeLink? parse(String input) {
    if (input.length > 4096) return null;
    var url = input.trim();
    if (!url.contains('://')) url = 'https://$url';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !{'https', 'http'}.contains(uri.scheme) ||
        !hosts.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && !{80, 443}.contains(uri.port))) {
      return null;
    }
    final parts = uri.pathSegments;
    String? id;
    var kind = TubeLinkKind.video;
    if (uri.host.endsWith('youtu.be')) {
      if (parts.length == 1) id = parts.first;
    } else if (parts.length == 1 && parts.first == 'watch') {
      id = uri.queryParameters['v'];
    } else if (parts.length == 2 && {'shorts', 'live'}.contains(parts.first)) {
      id = parts[1];
      kind = parts.first == 'shorts' ? TubeLinkKind.shorts : TubeLinkKind.live;
    }
    if (id == null || !isVideoId(id)) return null;
    final fragment = uri.fragment.startsWith('t=')
        ? uri.fragment.substring(2)
        : uri.fragment;
    final time = uri.queryParameters['t'] ??
        uri.queryParameters['start'] ??
        uri.queryParameters['time_continue'] ??
        fragment;
    return TubeYoutubeLink(url, id, kind, parseTimestamp(time));
  }

  static int? parseTimestamp(String value) {
    if (value.isEmpty) return null;
    final number = int.tryParse(value);
    if (number != null) return number >= 0 && number <= 604800 ? number : null;
    final match =
        RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$', caseSensitive: false)
            .firstMatch(value);
    if (match == null) return null;
    final seconds = (int.tryParse(match[1] ?? '') ?? 0) * 3600 +
        (int.tryParse(match[2] ?? '') ?? 0) * 60 +
        (int.tryParse(match[3] ?? '') ?? 0);
    return seconds <= 604800 ? seconds : null;
  }
}
