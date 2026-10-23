import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/tube_stream.dart';

class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;

  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  bool isActiveAt(Duration position) {
    return position >= start && position <= end;
  }
}

/// WebVTT subtitle parser & real-time cue tracker.
class TubeSubtitleService {
  static final TubeSubtitleService _instance = TubeSubtitleService._internal();
  factory TubeSubtitleService() => _instance;
  TubeSubtitleService._internal();

  TubeSubtitle? _currentTrack;
  List<SubtitleCue> _cues = [];
  bool _isLoading = false;
  int _generation = 0;

  TubeSubtitle? get currentTrack => _currentTrack;
  bool get hasActiveTrack => _currentTrack != null;
  bool get isLoading => _isLoading;

  /// Loads and parses a subtitle track.
  Future<void> loadSubtitleTrack(TubeSubtitle? track) async {
    final generation = ++_generation;
    _isLoading = false;
    _currentTrack = track;
    _cues.clear();
    if (track == null || track.url.isEmpty) {
      return;
    }

    _isLoading = true;
    try {
      debugPrint(
          '[TubeSubtitleService] Loading subtitle track: ${track.languageName} ');
      final resp = await http
          .get(Uri.parse(track.url))
          .timeout(const Duration(seconds: 10));
      if (generation == _generation && resp.statusCode == 200) {
        _cues = _parseWebVTT(resp.body);
        debugPrint(
            '[TubeSubtitleService] Parsed ${_cues.length} cues for ${track.languageName}');
      }
    } catch (e) {
      debugPrint('[TubeSubtitleService] Error loading subtitles: $e');
    } finally {
      if (generation == _generation) _isLoading = false;
    }
  }

  /// Clears active subtitle track.
  void clearTrack() {
    ++_generation;
    _isLoading = false;
    _currentTrack = null;
    _cues.clear();
  }

  /// Finds the currently active subtitle cue for a given video playback timestamp.
  String? getActiveCueText(Duration position) {
    if (_cues.isEmpty) return null;
    for (final cue in _cues) {
      if (cue.isActiveAt(position)) {
        return cue.text;
      }
    }
    return null;
  }

  /// Simple and robust WebVTT parser.
  List<SubtitleCue> _parseWebVTT(String content) {
    final List<SubtitleCue> cues = [];
    final lines = const LineSplitter().convert(content);
    final timeRegex = RegExp(
        r'(\d{2}:)?(\d{2}):(\d{2})[.,](\d{3})\s*-->\s*(\d{2}:)?(\d{2}):(\d{2})[.,](\d{3})');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      final match = timeRegex.firstMatch(line);
      if (match != null) {
        final start = _parseTimestamp(
          match.group(1),
          match.group(2)!,
          match.group(3)!,
          match.group(4)!,
        );
        final end = _parseTimestamp(
          match.group(5),
          match.group(6)!,
          match.group(7)!,
          match.group(8)!,
        );

        final textLines = <String>[];
        var j = i + 1;
        while (j < lines.length && lines[j].trim().isNotEmpty) {
          textLines.add(lines[j]
              .trim()
              .replaceAll(RegExp(r'<[^>]*>'), '')); // Strip HTML tags
          j++;
        }

        if (textLines.isNotEmpty) {
          cues.add(
              SubtitleCue(start: start, end: end, text: textLines.join('\n')));
        }
        i = j;
      }
    }
    return cues;
  }

  Duration _parseTimestamp(
      String? hoursStr, String minsStr, String secsStr, String millisStr) {
    final hours =
        hoursStr != null ? int.tryParse(hoursStr.replaceAll(':', '')) ?? 0 : 0;
    final mins = int.tryParse(minsStr) ?? 0;
    final secs = int.tryParse(secsStr) ?? 0;
    final millis = int.tryParse(millisStr) ?? 0;
    return Duration(
        hours: hours, minutes: mins, seconds: secs, milliseconds: millis);
  }
}
