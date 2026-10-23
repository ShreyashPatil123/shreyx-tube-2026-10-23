import 'dart:convert';

import 'package:crypto/crypto.dart';

class TubeTranscriptSegment {
  const TubeTranscriptSegment(this.id, this.text, {this.startMs});
  final int id;
  final String text;
  final int? startMs;
  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        if (startMs != null) 'startMs': startMs,
      };
}

class TubeTranscript {
  TubeTranscript(this.videoId, this.segments, {this.demo = false}) {
    if ((!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId) &&
            videoId != 'demo-study') ||
        segments.isEmpty ||
        segments.length > 400) {
      throw const FormatException(
        'Select a supported video and provide a transcript with 1–400 sections.',
      );
    }
    var length = 0;
    var previous = -1;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      length += segment.text.length;
      if (segment.id != i ||
          segment.text.trim().isEmpty ||
          segment.text.length > 4000 ||
          (segment.startMs != null &&
              (segment.startMs! < 0 ||
                  segment.startMs! < previous ||
                  segment.startMs! > 86400000))) {
        throw const FormatException(
          'Transcript sections or timestamps are invalid.',
        );
      }
      if (segment.startMs != null) previous = segment.startMs!;
    }
    if (length < 20 || length > 50000) {
      throw const FormatException(
        'Use 20–50,000 transcript characters. For a longer video, paste a smaller excerpt.',
      );
    }
  }
  final String videoId;
  final List<TubeTranscriptSegment> segments;
  final bool demo;
  String get digest => sha256
      .convert(
        utf8.encode(jsonEncode(segments.map((s) => s.toJson()).toList())),
      )
      .toString();
  static String time(int ms) {
    final seconds = ms ~/ 1000;
    final m = ((seconds ~/ 60) % 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return seconds >= 3600 ? '${seconds ~/ 3600}:$m:$s' : '$m:$s';
  }

  static TubeTranscript parse(String id, String input, {bool demo = false}) {
    if (input.length > 60000) {
      throw const FormatException(
        'Transcript too large. Paste a smaller excerpt.',
      );
    }
    final text = input.replaceAll('\r', '').trim();
    final segments = <TubeTranscriptSegment>[];
    final timestamp = RegExp(
      r'^(?:(\d{1,2}):)?(\d{2}):(\d{2})[.,](\d{3})\s*-->\s*(?:(\d{1,2}):)?(\d{2}):(\d{2})[.,](\d{3})',
    );
    if (text.startsWith('WEBVTT') || text.contains('-->')) {
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final match = timestamp.firstMatch(lines[i].trim());
        if (match == null) continue;
        int milliseconds(int offset) {
          final h = int.parse(match.group(1 + offset) ?? '0');
          final m = int.parse(match.group(2 + offset)!);
          final s = int.parse(match.group(3 + offset)!);
          if (m > 59 || s > 59) {
            throw const FormatException('Invalid caption timestamp.');
          }
          return ((h * 60 + m) * 60 + s) * 1000 +
              int.parse(match.group(4 + offset)!);
        }

        final start = milliseconds(0), end = milliseconds(4);
        if (end < start) {
          throw const FormatException('Caption end precedes its start.');
        }
        final content = <String>[];
        while (++i < lines.length && lines[i].trim().isNotEmpty) {
          content.add(lines[i]);
        }
        final cue = content
            .join(' ')
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&nbsp;', ' ')
            .trim();
        if (cue.isNotEmpty && (segments.isEmpty || segments.last.text != cue)) {
          segments.add(
            TubeTranscriptSegment(segments.length, cue, startMs: start),
          );
        }
      }
    } else {
      final chunks = text.split(RegExp(r'\n+|(?<=[.!?])\s+'));
      for (final chunk in chunks) {
        final words = chunk.trim().split(RegExp(r'\s+'));
        var buffer = '';
        for (final word in words) {
          if (word.isEmpty) continue;
          if (buffer.length + word.length > 700 && buffer.isNotEmpty) {
            segments.add(TubeTranscriptSegment(segments.length, buffer));
            buffer = '';
          }
          buffer = buffer.isEmpty ? word : '$buffer $word';
        }
        if (buffer.isNotEmpty) {
          segments.add(TubeTranscriptSegment(segments.length, buffer));
        }
      }
    }
    return TubeTranscript(id, List.unmodifiable(segments), demo: demo);
  }

  static TubeTranscript sample() => parse(
        'demo-study',
        'WEBVTT\n\n00:00.000 --> 00:12.000\nActive recall means retrieving information from memory instead of only rereading it. Close your notes and explain the idea in your own words.\n\n00:12.000 --> 00:25.000\nSpaced practice spreads learning sessions over time. Review difficult ideas again after a delay rather than repeating everything in one sitting.\n\n00:25.000 --> 00:39.000\nFeedback helps reveal gaps in understanding. Compare your explanation with the source and correct mistakes before the next practice session.\n\n00:39.000 --> 00:52.000\nA practical study routine combines a short review, a recall question, and feedback. Choose a manageable schedule and adjust it to what you find difficult.',
        demo: true,
      );
}

class TubeEvidence {
  const TubeEvidence(this.segmentId, this.quote);
  final int segmentId;
  final String quote;
  Map<String, dynamic> toJson() => {'segmentId': segmentId, 'quote': quote};
}

class TubeIntelligenceResult {
  const TubeIntelligenceResult({
    required this.summary,
    required this.detailed,
    required this.takeaways,
    required this.concepts,
    required this.evidence,
    required this.provider,
    this.answer = '',
    this.sections = const [],
  });
  final String summary, detailed, answer, provider;
  final List<String> takeaways, concepts;
  final List<TubeEvidence> evidence;
  final List<({int segmentId, String heading})> sections;
  Map<String, dynamic> toJson() => {
        'summary': summary,
        'detailed': detailed,
        'answer': answer,
        'takeaways': takeaways,
        'concepts': concepts,
        'provider': provider,
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'sections': sections
            .map((s) => {'segmentId': s.segmentId, 'heading': s.heading})
            .toList(),
      };
  static TubeIntelligenceResult parse(
    Map<String, dynamic> data,
    TubeTranscript source, {
    required String provider,
  }) {
    String field(String key, int max) {
      final value = data[key] ?? '';
      if (value is! String || value.length > max) {
        throw const FormatException('AI returned an invalid text field.');
      }
      return value.trim();
    }

    List<String> list(String key, int max) {
      final value = data[key] ?? [];
      if (value is! List ||
          value.length > max ||
          value.any((v) => v is! String || v.length > 1500)) {
        throw const FormatException('AI returned an invalid list.');
      }
      return value.cast<String>();
    }

    String normalize(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final evidence = <TubeEvidence>[];
    final raw = data['evidence'];
    if (raw is! List || raw.length > 8) {
      throw const FormatException(
        'AI did not provide valid supporting excerpts.',
      );
    }
    for (final e in raw) {
      if (e is! Map || e['segmentId'] is! int || e['quote'] is! String) {
        throw const FormatException('Invalid evidence.');
      }
      final id = e['segmentId'] as int, quote = e['quote'] as String;
      if (id < 0 ||
          id >= source.segments.length ||
          quote.trim().length < 8 ||
          quote.length > 1000 ||
          !normalize(source.segments[id].text).contains(normalize(quote))) {
        throw const FormatException(
          'The AI cited content that is not in this transcript. Try again or use local analysis.',
        );
      }
      evidence.add(TubeEvidence(id, quote));
    }
    final summary = field('summary', 3000),
        detailed = field('detailed', 12000),
        answer = field('answer', 5000);
    if (summary.isEmpty && answer.isEmpty) {
      throw const FormatException('AI returned an empty response.');
    }
    if (evidence.isEmpty && data['notCovered'] != true) {
      throw const FormatException(
        'No supporting transcript evidence was returned.',
      );
    }
    final takeaways = list('takeaways', 12), concepts = list('concepts', 16);
    if (data['notCovered'] == true &&
        (summary.isNotEmpty || detailed.isNotEmpty || takeaways.isNotEmpty)) {
      throw const FormatException(
        'An unsupported answer cannot contain summary claims.',
      );
    }
    final sections = <({int segmentId, String heading})>[];
    final rawSections = data['sections'] ?? [];
    if (rawSections is! List || rawSections.length > 12) {
      throw const FormatException('Invalid sections.');
    }
    for (final s in rawSections) {
      if (s is! Map ||
          s['segmentId'] is! int ||
          s['heading'] is! String ||
          (s['heading'] as String).length > 200) {
        throw const FormatException('Invalid section reference.');
      }
      final id = s['segmentId'] as int;
      if (id < 0 || id >= source.segments.length) {
        throw const FormatException('Unknown transcript section.');
      }
      sections.add((segmentId: id, heading: s['heading'] as String));
    }
    return TubeIntelligenceResult(
      summary: summary,
      detailed: detailed,
      answer: data['notCovered'] == true
          ? 'The provided transcript does not cover this question.'
          : answer,
      takeaways: takeaways,
      concepts: concepts,
      evidence: List.unmodifiable(evidence),
      provider: provider,
      sections: sections,
    );
  }

  String studyNotes(TubeTranscript source, String title) {
    final out = StringBuffer(
      '# $title\n\nVideo: ${source.videoId}\nMethod: $provider\n\n',
    );
    out.writeln(summary);
    if (detailed.isNotEmpty) out.writeln('\n$detailed');
    out.writeln('\nKey takeaways');
    for (final item in takeaways) {
      out.writeln('- $item');
    }
    if (concepts.isNotEmpty) out.writeln('\nConcepts: ${concepts.join(', ')}');
    out.writeln('\nSource excerpts');
    for (final e in evidence) {
      final time = source.segments[e.segmentId].startMs;
      out.writeln(
        '${time == null ? 'Section ${e.segmentId + 1}' : TubeTranscript.time(time)}: ${e.quote}',
      );
    }
    return out.toString();
  }
}
