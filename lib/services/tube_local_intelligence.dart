import '../models/tube_intelligence.dart';

/// Extractive transcript tools. These results are never presented as a live LLM response.
class TubeLocalIntelligence {
  static final _stop =
      'a an and are as at be by can do does for from how i in is it its of on or that the their this to was we what when which with you your'
          .split(' ')
          .toSet();
  static List<String> words(String text) =>
      RegExp(r'[\p{L}\p{N}]+', unicode: true)
          .allMatches(text.toLowerCase())
          .map((m) => m.group(0)!)
          .where((w) => w.length > 1 && !_stop.contains(w))
          .toList();
  static TubeIntelligenceResult analyze(
    TubeTranscript doc, {
    String question = '',
  }) {
    final frequency = <String, int>{};
    final termsById = {
      for (final s in doc.segments) s.id: words(s.text).toSet(),
    };
    for (final s in doc.segments) {
      for (final w in termsById[s.id]!) {
        frequency.update(w, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final query = words(question).toSet();
    final scores = {
      for (final s in doc.segments)
        s.id: query.isNotEmpty
            ? termsById[s.id]!
                .where(query.contains)
                .fold<double>(0, (v, w) => v + 1 / (frequency[w] ?? 1))
            : termsById[s.id]!.fold<double>(
                  0,
                  (v, w) => v + (frequency[w] ?? 0),
                ) /
                (termsById[s.id]!.length + 1),
    };
    final ranked = List.of(doc.segments)
      ..sort((a, b) {
        final diff = scores[b.id]!.compareTo(scores[a.id]!);
        return diff == 0 ? a.id.compareTo(b.id) : diff;
      });
    final matching = question.isEmpty
        ? ranked
        : ranked
            .where(
              (s) => query.isNotEmpty && termsById[s.id]!.any(query.contains),
            )
            .toList();
    final chosen = matching.take(6).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    String excerpt(String text) =>
        text.length <= 900 ? text : '${text.substring(0, 897)}…';
    final evidence = chosen
        .map(
          (s) => TubeEvidence(
            s.id,
            s.text.length <= 900 ? s.text : s.text.substring(0, 900),
          ),
        )
        .toList();
    final concepts = frequency.keys.toList()
      ..sort(
        (a, b) => frequency[b]!.compareTo(frequency[a]!) == 0
            ? a.compareTo(b)
            : frequency[b]!.compareTo(frequency[a]!),
      );
    final provider = doc.demo
        ? 'Demo · local extractive analysis'
        : 'Local extractive analysis';
    return TubeIntelligenceResult(
      summary: question.isEmpty
          ? chosen.take(2).map((s) => excerpt(s.text)).join(' ')
          : '',
      detailed: question.isEmpty
          ? chosen.map((s) => excerpt(s.text)).join('\n\n')
          : '',
      answer: question.isEmpty
          ? ''
          : evidence.isEmpty
              ? 'No matching passage was found. Try the terms used in the transcript or use an opted-in AI gateway. This local search cannot infer an answer.'
              : 'Relevant transcript passages (local evidence search, not a generated answer):\n\n${chosen.map((s) => excerpt(s.text)).join('\n\n')}',
      takeaways: question.isEmpty
          ? chosen.take(4).map((s) => excerpt(s.text)).toList()
          : [],
      concepts: question.isEmpty ? concepts.take(8).toList() : [],
      evidence: evidence,
      provider: provider,
      sections: question.isEmpty
          ? chosen
              .where((s) => s.startMs != null)
              .map((s) => (segmentId: s.id, heading: 'Section ${s.id + 1}'))
              .toList()
          : [],
    );
  }
}
