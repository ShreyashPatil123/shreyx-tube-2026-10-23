import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/tube_intelligence.dart';
import '../models/tube_stream.dart';
import '../services/tube_intelligence_store.dart';
import '../services/tube_local_intelligence.dart';
import '../services/tube_storage_service.dart';

class TubeIntelligenceController extends ChangeNotifier {
  TubeIntelligenceController({
    TubeIntelligenceStore? store,
    http.Client Function()? clientFactory,
  })  : store = store ?? TubeIntelligenceStore(),
        _clientFactory = clientFactory ?? http.Client.new {
    this.store.addListener(_privacyChanged);
    TubeStorageService().addListener(_storageChanged);
  }
  final TubeIntelligenceStore store;
  final http.Client Function() _clientFactory;
  http.Client? _client;
  int _epoch = 0;
  bool _disposed = false;
  bool _wasIncognito = TubeStorageService().isIncognito;
  TubeTranscript? transcript;
  String videoId = '', title = '', notes = '', savedResponses = '';
  String? error;
  bool busy = false, remote = false;
  TubeIntelligenceResult? result;
  final List<({String question, TubeIntelligenceResult result})> conversation =
      [];
  final Map<String, TubeIntelligenceResult> _cache = {};
  String _retryQuestion = '';
  bool _retryNotes = false;
  Future<void> retry() =>
      generate(question: _retryQuestion, studyNotes: _retryNotes);
  void _storageChanged() {
    final incognito = TubeStorageService().isIncognito;
    if (incognito == _wasIncognito) return;
    _wasIncognito = incognito;
    _privacyChanged();
  }

  void _privacyChanged() {
    cancel(notify: false);
    _cache.clear();
    _retryQuestion = '';
    _retryNotes = false;
    result = null;
    conversation.clear();
    notes = '';
    savedResponses = '';
    if (!store.externalAllowed || TubeStorageService().isIncognito) {
      remote = false;
    }
    if (!_disposed) notifyListeners();
  }

  void cancel({bool notify = true}) {
    _epoch++;
    _client?.close();
    _client = null;
    busy = false;
    if (notify && !_disposed) notifyListeners();
  }

  Future<void> select(String id, String videoTitle) async {
    cancel(notify: false);
    final epoch = _epoch;
    videoId = id;
    title = videoTitle;
    transcript = null;
    result = null;
    notes = '';
    savedResponses = '';
    error = null;
    conversation.clear();
    _cache.clear();
    _retryQuestion = '';
    _retryNotes = false;
    notifyListeners();
    if (TubeStorageService().isIncognito) return;
    try {
      final saved = await store.load(id);
      if (_disposed || epoch != _epoch) return;
      notes = saved?['notes'] as String? ?? '';
      savedResponses = saved?['responses'] as String? ?? '';
    } catch (_) {
      if (epoch == _epoch) {
        error =
            'Could not read saved study material. Your transcript can still be used.';
      }
    }
    if (!_disposed && epoch == _epoch) notifyListeners();
  }

  void useTranscript(String text) {
    final parsed = TubeTranscript.parse(
      videoId,
      text,
      demo: videoId == 'demo-study',
    );
    cancel(notify: false);
    transcript = parsed;
    result = null;
    error = null;
    conversation.clear();
    _cache.clear();
    _retryQuestion = '';
    _retryNotes = false;
    notifyListeners();
  }

  Future<void> demo() async {
    await select('demo-study', 'Study practice · sample transcript');
    if (_disposed || videoId != 'demo-study') return;
    transcript = TubeTranscript.sample();
    remote = false;
    error = null;
    if (!_disposed) notifyListeners();
  }

  void setRemote(bool value) {
    if (value && (!store.externalAllowed || TubeStorageService().isIncognito)) {
      error =
          'Enable external AI in AI privacy settings first. Incognito always uses local analysis.';
    } else {
      cancel(notify: false);
      remote = value;
      error = null;
    }
    notifyListeners();
  }

  Future<List<int>> _bounded(http.StreamedResponse response, int max) async {
    if ((response.contentLength ?? 0) > max) {
      throw const FormatException(
        'Response is too large. Use a smaller transcript.',
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > max) {
        throw const FormatException('Response is too large.');
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<void> loadCaptions(TubeSubtitle track) async {
    if (busy) return;
    cancel(notify: false);
    final epoch = _epoch;
    busy = true;
    error = null;
    notifyListeners();
    final client = _clientFactory();
    _client = client;
    try {
      final uri = Uri.tryParse(track.url);
      if (uri == null ||
          uri.scheme != 'https' ||
          !['youtube.com', 'www.youtube.com'].contains(uri.host) ||
          uri.path != '/api/timedtext' ||
          uri.userInfo.isNotEmpty ||
          (uri.hasPort && uri.port != 443)) {
        throw const FormatException(
          'This caption source is unsupported. Paste an authorized transcript instead.',
        );
      }
      final request = http.Request(
        'GET',
        uri.replace(queryParameters: {...uri.queryParameters, 'fmt': 'vtt'}),
      )..followRedirects = false;
      final bytes = await (() async {
        final response = await client.send(request);
        if (response.statusCode != 200) {
          throw StateError(
            'Captions are unavailable. Paste a transcript you have permission to use.',
          );
        }
        return _bounded(response, 256000);
      })()
          .timeout(const Duration(seconds: 15));
      final text = utf8.decode(bytes);
      if (!text.trimLeft().startsWith('WEBVTT')) {
        throw const FormatException(
          'No supported captions were returned. Paste a transcript instead.',
        );
      }
      final doc = TubeTranscript.parse(videoId, text);
      if (!_disposed && epoch == _epoch) {
        transcript = doc;
        result = null;
        conversation.clear();
        _cache.clear();
      }
    } catch (e) {
      if (!_disposed && epoch == _epoch) error = _message(e);
    } finally {
      client.close();
      if (!_disposed && epoch == _epoch) {
        _client = null;
        busy = false;
        notifyListeners();
      }
    }
  }

  String _message(Object e) => e is FormatException
      ? e.message.toString()
      : e is TimeoutException
          ? 'The request timed out. Retry or use local analysis.'
          : e is StateError
              ? e.message.toString()
              : 'The request failed. Check your connection and retry. No result was saved.';
  Future<void> generate({String question = '', bool studyNotes = false}) async {
    if (busy) return;
    final source = transcript;
    if (source == null) {
      error = 'Import a transcript or load the labelled demo first.';
      notifyListeners();
      return;
    }
    if (question.length > 1000 ||
        (question.isNotEmpty && question.trim().isEmpty)) {
      error = 'Use a question of 1–1,000 characters.';
      notifyListeners();
      return;
    }
    final q = question.trim();
    _retryQuestion = q;
    _retryNotes = studyNotes;
    final key = '${source.digest}:$remote:$q';
    final epoch = ++_epoch;
    final privacyRevision = store.revision;
    busy = true;
    error = null;
    notifyListeners();
    try {
      var generated = _cache[key];
      if (generated == null) {
        if (remote) {
          if (!store.externalAllowed || TubeStorageService().isIncognito) {
            throw StateError(
              'External processing is disabled. Choose local analysis.',
            );
          }
          final origin = TubeIntelligenceStore.validateEndpoint(store.endpoint);
          final client = _clientFactory();
          _client = client;
          final request = http.Request('POST', origin.resolve('/v1/analyze'))
            ..followRedirects = false
            ..headers.addAll({
              'content-type': 'application/json',
              'authorization': 'Bearer ${store.accessToken}',
            })
            ..body = jsonEncode({
              'videoId': source.videoId,
              'title': title,
              'task': q.isEmpty ? 'summary' : 'ask',
              'question': q,
              'segments': source.segments.map((s) => s.toJson()).toList(),
            });
          final bytes = await (() async {
            final response = await client.send(request);
            if (response.statusCode == 429) {
              throw StateError(
                'AI usage limit reached. Wait before retrying or choose local analysis.',
              );
            }
            if (response.statusCode == 401 || response.statusCode == 403) {
              throw StateError(
                'Gateway access was denied. Check your gateway token in AI privacy settings.',
              );
            }
            if (response.statusCode == 503) {
              throw StateError(
                'The AI gateway is unavailable or unconfigured. Retry later or choose local analysis.',
              );
            }
            if (response.statusCode != 200) {
              throw StateError(
                'AI request failed (${response.statusCode}). Retry or choose local analysis.',
              );
            }
            return _bounded(response, 96000);
          })()
              .timeout(const Duration(seconds: 35));
          if (_disposed ||
              epoch != _epoch ||
              privacyRevision != store.revision) {
            return;
          }
          final data = jsonDecode(utf8.decode(bytes));
          if (data is! Map<String, dynamic>) {
            throw const FormatException('The AI returned invalid JSON.');
          }
          generated = TubeIntelligenceResult.parse(
            data,
            source,
            provider: 'Gemini · external AI · verify against excerpts',
          );
        } else {
          generated = TubeLocalIntelligence.analyze(source, question: q);
        }
      }
      if (_disposed ||
          epoch != _epoch ||
          privacyRevision != store.revision ||
          transcript?.digest != source.digest) {
        return;
      }
      _cache[key] = generated;
      if (_cache.length > 12) _cache.remove(_cache.keys.first);
      if (q.isEmpty) {
        result = generated;
      } else {
        conversation.add((question: q, result: generated));
        if (conversation.length > 12) conversation.removeAt(0);
      }
      if (studyNotes) notes = generated.studyNotes(source, title);
    } catch (e) {
      if (!_disposed && epoch == _epoch) error = _message(e);
    } finally {
      if (!_disposed && epoch == _epoch) {
        _client?.close();
        _client = null;
        busy = false;
        notifyListeners();
      }
    }
  }

  String export() {
    final out = StringBuffer('# $title\nVideo: $videoId\n\n');
    if (result != null && transcript != null) {
      out.writeln(result!.studyNotes(transcript!, title));
    }
    if (savedResponses.isNotEmpty) out.writeln(savedResponses);
    for (final turn in conversation) {
      out.writeln('\nQuestion: ${turn.question}\n${turn.result.answer}');
      if (transcript != null) {
        for (final e in turn.result.evidence) {
          final start = transcript!.segments[e.segmentId].startMs;
          out.writeln(
            '${start == null ? 'Section ${e.segmentId + 1}' : TubeTranscript.time(start)}: ${e.quote}',
          );
        }
      }
    }
    return out.toString();
  }

  Future<void> save() async {
    final revision = store.revision;
    await store.save(
      videoId: videoId,
      title: title,
      notes: notes,
      responses: export(),
      digest: transcript?.digest ?? '',
      expectedRevision: revision,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    cancel(notify: false);
    store.removeListener(_privacyChanged);
    TubeStorageService().removeListener(_storageChanged);
    super.dispose();
  }
}
