import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tube_intelligence.dart';
import '../models/tube_stream.dart';
import '../providers/tube_intelligence_controller.dart';
import '../services/tube_share_service.dart';
import '../services/tube_youtube_link.dart';
import '../services/tube_storage_service.dart';
import 'tube_ai_privacy_screen.dart';
import '../widgets/tube_intelligence_theme.dart';

class TubeVideoIntelligenceScreen extends StatefulWidget {
  const TubeVideoIntelligenceScreen({
    super.key,
    this.videoId,
    this.title = '',
    this.subtitles = const [],
    this.onSeek,
    this.controller,
  });
  final String? videoId;
  final String title;
  final List<TubeSubtitle> subtitles;
  final bool Function(String videoId, Duration position)? onSeek;
  final TubeIntelligenceController? controller;
  @override
  State<TubeVideoIntelligenceScreen> createState() =>
      _TubeVideoIntelligenceScreenState();
}

class _TubeVideoIntelligenceScreenState
    extends State<TubeVideoIntelligenceScreen> {
  late final c = widget.controller ?? TubeIntelligenceController();
  final _url = TextEditingController(),
      _input = TextEditingController(),
      _question = TextEditingController(),
      _notes = TextEditingController(),
      _search = TextEditingController();
  String? _error;
  bool _initializing = true;
  List<Map<String, Object?>> _saved = [];
  int _libraryEpoch = 0, _privacyRevision = -1;
  bool _incognito = false;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await c.store.init();
      if (!mounted) return;
      await _refreshSaved();
      if (!mounted) return;
      if (widget.videoId != null) await c.select(widget.videoId!, widget.title);
    } catch (_) {
      _error =
          'Could not load saved materials. You can still use a pasted transcript or the demo.';
    }
    if (mounted) setState(() => _initializing = false);
  }

  void _changed() {
    if (!mounted) return;
    if (_notes.text != c.notes) _notes.text = c.notes;
    if (_privacyRevision != c.store.revision ||
        _incognito != TubeStorageService().isIncognito) {
      _saved = [];
      _refreshSaved();
    }
    setState(() {});
  }

  Future<void> _refreshSaved() async {
    final epoch = ++_libraryEpoch;
    _privacyRevision = c.store.revision;
    _incognito = TubeStorageService().isIncognito;
    try {
      final rows = await c.store.listSaved();
      if (mounted && epoch == _libraryEpoch) setState(() => _saved = rows);
    } catch (_) {
      if (mounted && epoch == _libraryEpoch) {
        setState(() {
          _saved = [];
          _error =
              'Could not refresh saved materials. Reopen this screen to retry.';
        });
      }
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    if (widget.controller == null) c.dispose();
    for (final field in [_url, _input, _question, _notes, _search]) {
      field.dispose();
    }
    super.dispose();
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _error = null);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message.toString()
              : e is StateError
                  ? e.message.toString()
                  : 'Could not complete this action. Retry.',
        );
      }
    }
  }

  Future<void> _select(String id, String title) async {
    _input.clear();
    _question.clear();
    _search.clear();
    await c.select(id, title);
  }

  Future<void> _selectUrl() async {
    final link = TubeYoutubeLink.parse(_url.text);
    if (link == null) {
      throw const FormatException(
        'Enter a valid YouTube watch, Shorts, live or youtu.be video URL.',
      );
    }
    await _select(link.videoId, 'YouTube video ${link.videoId}');
  }

  Future<void> _demo() async {
    _input.clear();
    _question.clear();
    _search.clear();
    await c.demo();
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Semantics(
          header: true,
          child: Text(
            text,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
      );
  Widget _evidence(TubeEvidence e) {
    final doc = c.transcript;
    final start = doc?.segments[e.segmentId].startMs;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(e.quote),
            if (start != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Seek to ${TubeTranscript.time(start)}'),
                  onPressed: () {
                    if (widget.onSeek?.call(
                          c.videoId,
                          Duration(milliseconds: start),
                        ) !=
                        true) {
                      _notice(
                        'Open this video in the watch player to use timestamp navigation.',
                      );
                    }
                  },
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Transcript section ${e.segmentId + 1} · no timestamp supplied',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _result(TubeIntelligenceResult r) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(r.provider, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (r.summary.isNotEmpty) ...[
            _heading('Concise summary'),
            SelectableText(r.summary),
          ],
          if (r.detailed.isNotEmpty) ...[
            _heading('Detailed summary'),
            SelectableText(r.detailed),
          ],
          if (r.answer.isNotEmpty) SelectableText(r.answer),
          if (r.takeaways.isNotEmpty) ...[
            _heading('Key takeaways'),
            ...r.takeaways.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SelectableText('• $s'),
              ),
            ),
          ],
          if (r.concepts.isNotEmpty) ...[
            _heading('Important concepts'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: r.concepts.map((s) => Chip(label: Text(s))).toList(),
            ),
          ],
          if (r.sections.isNotEmpty) ...[
            _heading('Timestamped sections'),
            ...r.sections.map((s) {
              final ms = c.transcript!.segments[s.segmentId].startMs;
              return Text(
                '${ms == null ? 'Section ${s.segmentId + 1}' : TubeTranscript.time(ms)} · ${s.heading}',
              );
            }),
          ],
          if (r.evidence.isNotEmpty) ...[
            _heading('Supporting transcript excerpts'),
            ...r.evidence.map(_evidence),
          ],
        ],
      );
  @override
  Widget build(BuildContext context) =>
      TubeIntelligenceTheme(builder: _buildContent);

  Widget _buildContent(BuildContext context) {
    final doc = c.transcript;
    final query = _search.text.toLowerCase().trim();
    final hits = doc?.segments
            .where((s) => query.isEmpty || s.text.toLowerCase().contains(query))
            .toList() ??
        [];
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Video intelligence',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'AI privacy and data controls',
            icon: const Icon(Icons.privacy_tip_outlined),
            onPressed: () => _run(() async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TubeAiPrivacyScreen(store: c.store),
                ),
              );
              if (mounted) await _refreshSaved();
            }),
          ),
        ],
      ),
      body: SafeArea(
        child: _initializing
            ? const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Loading study materials',
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Understand a video from its transcript',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use captions offered by the player, or paste text you have permission to process. No transcript means no content claims. Summaries are not generated automatically.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _url,
                    enabled: !c.busy,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'YouTube video URL',
                      hintText: 'https://www.youtube.com/watch?v=…',
                    ),
                    onSubmitted: (_) => _run(_selectUrl),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: c.busy ? null : () => _run(_selectUrl),
                        child: const Text('Select video'),
                      ),
                      OutlinedButton(
                        onPressed: () => _run(_demo),
                        child: const Text('Try labelled demo'),
                      ),
                    ],
                  ),
                  if (c.videoId.isNotEmpty) ...[
                    _heading(c.title),
                    SelectableText('Video: ${c.videoId}'),
                    if (doc?.demo == true)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'DEMO · Original sample transcript, not content from a YouTube video. Results below are computed locally, not a live Gemini response.',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    if (c.videoId == widget.videoId &&
                        widget.subtitles.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.subtitles
                            .take(4)
                            .map(
                              (track) => OutlinedButton(
                                onPressed: c.busy
                                    ? null
                                    : () => _run(() => c.loadCaptions(track)),
                                child: Text(
                                  'Load captions: ${track.languageName}',
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _input,
                      enabled: !c.busy,
                      minLines: 3,
                      maxLines: 8,
                      maxLength: 60000,
                      maxLengthEnforcement: MaxLengthEnforcement.none,
                      decoration: const InputDecoration(
                        labelText: 'Transcript text or WebVTT captions',
                        helperText:
                            'Up to 50,000 content characters. Plain text has no inferred timestamps.',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: c.busy
                          ? null
                          : () => _run(() async {
                                c.useTranscript(_input.text);
                              }),
                      child: const Text('Use pasted transcript'),
                    ),
                    if (doc == null)
                      const Text(
                        'No transcript loaded. If captions are unavailable or restricted, paste an authorized excerpt or use the labelled demo.',
                      ),
                    if (doc != null)
                      Text(
                        '${doc.segments.length} sections loaded · ${doc.demo ? 'sample' : 'selected video'} · timestamps only where supplied',
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Use external Gemini AI for this analysis',
                      ),
                      subtitle: Text(
                        c.remote
                            ? 'Transcript and question will be sent to your gateway and Google when you run an analysis.'
                            : 'Local extractive analysis. No AI request is sent.',
                      ),
                      value: c.remote,
                      onChanged: c.busy ? null : c.setRemote,
                    ),
                    if (c.busy) ...[
                      Semantics(
                        liveRegion: true,
                        child: const Text(
                          'Working on the selected transcript…',
                        ),
                      ),
                      const LinearProgressIndicator(
                        semanticsLabel:
                            'Analysis or caption loading in progress',
                      ),
                      TextButton(
                        onPressed: c.cancel,
                        child: const Text('Cancel request'),
                      ),
                    ],
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: c.busy || doc == null
                              ? null
                              : () => _run(c.generate),
                          child: const Text('Generate summary'),
                        ),
                        OutlinedButton(
                          onPressed: c.busy || doc == null
                              ? null
                              : () => _run(() => c.generate(studyNotes: true)),
                          child: const Text('Generate study notes'),
                        ),
                      ],
                    ),
                  ],
                  if ((_error ?? c.error) != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                (_error ?? c.error)!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                            if (doc != null && !c.busy)
                              TextButton(
                                onPressed: () => _run(c.retry),
                                child: const Text('Retry last analysis'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (c.result != null) _result(c.result!),
                  if (doc != null) ...[
                    _heading('Ask this video'),
                    TextField(
                      controller: _question,
                      enabled: !c.busy,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 1000,
                      maxLengthEnforcement: MaxLengthEnforcement.none,
                      decoration: const InputDecoration(
                        labelText: 'Question about this transcript',
                      ),
                      onSubmitted: (_) => _ask(),
                    ),
                    FilledButton(
                      onPressed: c.busy ? null : _ask,
                      child: const Text('Ask question'),
                    ),
                    ...c.conversation.map(
                      (turn) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Semantics(
                                header: true,
                                child: Text(
                                  turn.question,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _result(turn.result),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (c.videoId.isNotEmpty) ...[
                    _heading('Study notes'),
                    TextField(
                      controller: _notes,
                      minLines: 3,
                      maxLines: 10,
                      maxLength: 30000,
                      maxLengthEnforcement: MaxLengthEnforcement.none,
                      decoration: const InputDecoration(
                        labelText: 'Your editable study notes',
                      ),
                      onChanged: (value) => c.notes = value,
                    ),
                    const Text(
                      'Save is explicit. In Incognito, saving and external processing are disabled.',
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: c.busy
                              ? null
                              : () => _run(() async {
                                    await c.save();
                                    await _refreshSaved();
                                    _notice(
                                      'Study materials saved on this device.',
                                    );
                                  }),
                          child: const Text('Save materials'),
                        ),
                        OutlinedButton(
                          onPressed: () => _run(() async {
                            await Clipboard.setData(
                              ClipboardData(
                                text:
                                    '${c.export()}\n\nStudy notes\n${_notes.text}',
                              ),
                            );
                            _notice('Study material copied.');
                          }),
                          child: const Text('Copy materials'),
                        ),
                        OutlinedButton(
                          onPressed: () => TubeShareService.exportText(
                            context,
                            c.title,
                            '${c.export()}\n\nStudy notes\n${_notes.text}',
                          ),
                          child: const Text('Export materials'),
                        ),
                      ],
                    ),
                    if (c.savedResponses.isNotEmpty) ...[
                      _heading('Previously saved responses'),
                      const Text(
                        'Saved locally for this video. Import the original transcript before asking further questions.',
                      ),
                      SelectableText(c.savedResponses),
                    ],
                  ],
                  if (doc != null) ...[
                    _heading('Search transcript'),
                    TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        labelText: 'Find words in the transcript',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    Text(
                      '${hits.length} matching sections${hits.length > 40 ? ' · showing the first 40; refine your search' : ''}',
                    ),
                    ...hits
                        .take(40)
                        .map((s) => _evidence(TubeEvidence(s.id, s.text))),
                  ],
                  if (_saved.isNotEmpty) ...[
                    _heading('Saved video materials'),
                    ..._saved.map(
                      (s) => ListTile(
                        title: Text(s['title'] as String),
                        subtitle: const Text('Stored on this device'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _run(
                          () => _select(
                            s['video_id'] as String,
                            s['title'] as String,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Future<void> _ask() => _run(() async {
        if (_question.text.trim().isEmpty) {
          throw const FormatException(
            'Enter a question about the loaded transcript.',
          );
        }
        await c.generate(question: _question.text);
      });
}
