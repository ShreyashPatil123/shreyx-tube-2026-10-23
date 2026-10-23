import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shreyx_tube/models/tube_intelligence.dart';
import 'package:shreyx_tube/models/tube_stream.dart';
import 'package:shreyx_tube/providers/tube_intelligence_controller.dart';
import 'package:shreyx_tube/screens/tube_video_intelligence_screen.dart';
import 'package:shreyx_tube/screens/tube_ai_privacy_screen.dart';
import 'package:shreyx_tube/services/tube_database_service.dart';
import 'package:shreyx_tube/services/tube_intelligence_store.dart';
import 'package:shreyx_tube/services/tube_local_intelligence.dart';
import 'package:shreyx_tube/services/tube_share_service.dart';
import 'package:shreyx_tube/services/tube_storage_service.dart';
import 'package:shreyx_tube/theme/tube_theme.dart';

final sample = TubeTranscript.sample();
Map<String, dynamic> aiResponse() => {
      'summary': 'Recall uses memory.',
      'detailed': 'The sample describes retrieval practice.',
      'answer': 'The sample describes retrieval practice.',
      'takeaways': ['Retrieve from memory.'],
      'concepts': ['Recall'],
      'evidence': [
        {'segmentId': 0, 'quote': sample.segments[0].text},
      ],
      'sections': [
        {'segmentId': 0, 'heading': 'Recall'},
      ],
      'notCovered': false,
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late TubeIntelligenceStore store;
  final controllers = <TubeIntelligenceController>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)',
    );
    await db.execute(
      'CREATE TABLE video_intelligence (video_id TEXT PRIMARY KEY,title TEXT,notes TEXT,responses TEXT,digest TEXT,updated_at INTEGER)',
    );
    store = TubeIntelligenceStore.withDatabase(db);
  });
  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
    await TubeStorageService().setIncognito(false);
    store.dispose();
    await db.close();
    messenger.setMockMethodCallHandler(TubeShareService.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
  TubeIntelligenceController controller([http.Client Function()? factory]) {
    final c = TubeIntelligenceController(store: store, clientFactory: factory);
    controllers.add(c);
    return c;
  }

  Future<void> remote(TubeIntelligenceController c) async {
    await store.configure(
      allowed: true,
      url: 'https://gateway.example',
      token: 'synthetic-gateway-user-token-123456',
    );
    await c.demo();
    c.setRemote(true);
  }

  test('Plain transcript has stable IDs and no invented times', () {
    final doc = TubeTranscript.parse(
      'abcdefghijk',
      'A sufficiently long sentence about learning. A second useful sentence about practice.',
    );
    expect(doc.segments.length, 2);
    expect(doc.segments.every((s) => s.startMs == null), isTrue);
    expect(
      doc.digest,
      TubeTranscript.parse(
        'abcdefghijk',
        'A sufficiently long sentence about learning. A second useful sentence about practice.',
      ).digest,
    );
  });
  test(
      'VTT timestamps, tags and caption entities are parsed without player changes',
      () {
    final doc = TubeTranscript.parse(
      'abcdefghijk',
      'WEBVTT\n\n00:01.250 --> 00:04.000\n<b>Active recall</b> &amp; feedback help with learning.',
    );
    expect(doc.segments.single.startMs, 1250);
    expect(
      doc.segments.single.text,
      'Active recall & feedback help with learning.',
    );
    expect(TubeTranscript.time(3723000), '1:02:03');
  });
  for (final text in [
    '',
    'short',
    'x' * 60001,
    'WEBVTT\nnot captions',
    'WEBVTT\n\n00:62.000 --> 00:63.000\nLong enough sentence to be a transcript.',
    'WEBVTT\n\n00:05.000 --> 00:01.000\nLong enough sentence to be a transcript.',
  ]) {
    test(
      'Malformed or missing transcript is rejected (${text.length} chars)',
      () {
        expect(
          () => TubeTranscript.parse('abcdefghijk', text),
          throwsFormatException,
        );
      },
    );
  }
  test('Foreign IDs, negative times and too many sections are rejected', () {
    expect(
      () => TubeTranscript.parse(
        'http://127.0.0.1',
        'A long enough transcript sentence with useful words.',
      ),
      throwsFormatException,
    );
    expect(
      () => TubeTranscript('abcdefghijk', [
        const TubeTranscriptSegment(
          0,
          'A long enough transcript for this example.',
          startMs: -1,
        ),
      ]),
      throwsFormatException,
    );
    expect(
      () => TubeTranscript(
        'abcdefghijk',
        List.generate(
          401,
          (i) => TubeTranscriptSegment(i, 'Long enough section.'),
        ),
      ),
      throwsFormatException,
    );
  });
  test(
    'Local summary, concepts, notes and evidence all come from the real input',
    () {
      final r = TubeLocalIntelligence.analyze(sample);
      expect(r.provider, contains('Demo'));
      expect(r.summary, isNotEmpty);
      expect(r.concepts, isNotEmpty);
      for (final e in r.evidence) {
        expect(sample.segments[e.segmentId].text, contains(e.quote));
      }
      expect(r.studyNotes(sample, 'Study'), contains('00:12'));
      final q = TubeLocalIntelligence.analyze(
        sample,
        question: 'What is spaced practice?',
      );
      expect(q.answer, contains('local evidence search'));
      expect(q.evidence.any((e) => e.segmentId == 1), isTrue);
      expect(
        TubeLocalIntelligence.analyze(
          sample,
          question: 'quantum blackholes superconductors',
        ).answer,
        contains('No matching passage'),
      );
    },
  );
  test(
    'AI parser validates exact quotes, segment references and typed fields',
    () {
      expect(
        TubeIntelligenceResult.parse(
          aiResponse(),
          sample,
          provider: 'fixture',
        ).evidence.length,
        1,
      );
      for (final replacement in [
        {
          'evidence': [
            {'segmentId': 0, 'quote': 'This never appeared in the transcript.'},
          ],
        },
        {
          'evidence': [
            {'segmentId': 99, 'quote': sample.segments[0].text},
          ],
        },
        {'summary': 42},
        {
          'sections': [
            {'segmentId': 99, 'heading': 'Invented'},
          ],
        },
        {
          'takeaways': ['x' * 1501],
        },
        {'evidence': []},
      ]) {
        expect(
          () => TubeIntelligenceResult.parse(
            {...aiResponse(), ...replacement},
            sample,
            provider: 'fixture',
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'Unsupported AI answers are replaced and model timestamps are ignored',
    () {
      final value = {
        ...aiResponse(),
        'summary': '',
        'detailed': '',
        'takeaways': [],
        'evidence': [],
        'notCovered': true,
        'answer': 'Unverified answer.',
      };
      expect(
        TubeIntelligenceResult.parse(value, sample, provider: 'fixture').answer,
        'The provided transcript does not cover this question.',
      );
      final r = TubeIntelligenceResult.parse(
        {
          ...aiResponse(),
          'sections': [
            {'segmentId': 1, 'heading': 'Practice', 'startMs': 999999},
          ],
        },
        sample,
        provider: 'fixture',
      );
      expect(sample.segments[r.sections.single.segmentId].startMs, 12000);
    },
  );
  for (final url in [
    'file:///private',
    'http://gateway.example',
    'https://user:secret@gateway.example',
    'https://gateway.example/path',
    'https://gateway.example?key=secret',
    'https://127.0.0.1',
    'https://localhost',
    'https://192.168.1.2',
    'https://[::1]',
  ]) {
    test('Production gateway validation rejects $url', () {
      expect(
        () => TubeIntelligenceStore.validateEndpoint(url, allowLoopback: false),
        throwsFormatException,
      );
    });
  }
  test(
    'Gateway config rejects a provider key and persists access token securely',
    () async {
      await expectLater(
        store.configure(
          allowed: true,
          url: 'https://gateway.example',
          token: 'AIza${'synthetic' * 6}',
        ),
        throwsFormatException,
      );
      await store.configure(
        allowed: true,
        url: 'https://gateway.example',
        token: 'synthetic-gateway-user-token-123456',
      );
      final rows = await db.query('settings');
      expect(rows.toString(), isNot(contains('synthetic-gateway-user-token')));
      final restored = TubeIntelligenceStore.withDatabase(db);
      await restored.init();
      expect(restored.externalAllowed, isTrue);
      expect(restored.accessToken, 'synthetic-gateway-user-token-123456');
      restored.dispose();
    },
  );
  test(
    'Local workflow saves and restores notes and responses for the right video',
    () async {
      final c = controller();
      await c.demo();
      await c.generate(studyNotes: true);
      await c.generate(question: 'What is feedback?');
      await c.save();
      final saved = await store.load('demo-study');
      expect(saved!['notes'], contains('Source excerpts'));
      await c.select('abcdefghijk', 'Other');
      expect(c.notes, isEmpty);
      expect(c.conversation, isEmpty);
      expect(c.result, isNull);
      await c.select('demo-study', 'Study');
      expect(c.notes, contains('Source excerpts'));
      expect(c.savedResponses, contains('feedback'));
    },
  );
  test(
    'Reset fences queued configuration and cannot restore external consent',
    () async {
      final write = store.configure(
        allowed: true,
        url: 'https://gateway.example',
        token: 'synthetic-gateway-user-token-123456',
      );
      final rejected = expectLater(write, throwsStateError);
      await store.reset();
      await rejected;
      await store.init();
      expect(store.externalAllowed, isFalse);
      expect(store.endpoint, isEmpty);
      expect(store.accessToken, isEmpty);
      expect(await db.query('settings'), isEmpty);
    },
  );
  test(
    'Incognito hides the saved library, forbids saves and sends no AI requests',
    () async {
      var requests = 0;
      final c = controller(
        () => MockClient((r) async {
          requests++;
          return http.Response(jsonEncode(aiResponse()), 200);
        }),
      );
      await remote(c);
      await c.save();
      expect(await store.listSaved(), hasLength(1));
      await TubeStorageService().setIncognito(true);
      expect(c.remote, isFalse);
      expect(await store.listSaved(), isEmpty);
      expect(await store.load('demo-study'), isNull);
      await expectLater(c.save(), throwsStateError);
      c.setRemote(true);
      expect(c.remote, isFalse);
      await c.generate();
      expect(requests, 0);
      await TubeStorageService().setIncognito(false);
      expect(await store.listSaved(), hasLength(1));
    },
  );
  test(
    'Explicit cancellation and disposal discard an in-flight AI reply',
    () async {
      for (final dispose in [false, true]) {
        final pending = Completer<http.Response>();
        final c = controller(() => MockClient((r) => pending.future));
        await remote(c);
        final operation = c.generate();
        await Future<void>.delayed(Duration.zero);
        if (dispose) {
          controllers.remove(c);
          c.dispose();
        } else {
          c.cancel();
        }
        pending.complete(http.Response(jsonEncode(aiResponse()), 200));
        await operation;
        expect(c.result, isNull);
        expect(c.busy, isFalse);
      }
    },
  );
  test(
    'Caption redirects and non-VTT responses cannot become source content',
    () async {
      for (final response in [
        http.Response('', 302, headers: {'location': 'http://127.0.0.1'}),
        http.Response('<html>Not captions</html>', 200),
      ]) {
        final c = controller(() => MockClient((r) async => response));
        await c.select('abcdefghijk', 'Caption test');
        await c.loadCaptions(
          TubeSubtitle(
            languageCode: 'en',
            format: 'vtt',
            languageName: 'English',
            url: 'https://www.youtube.com/api/timedtext?v=abcdefghijk',
            isAutoGenerated: false,
          ),
        );
        expect(c.transcript, isNull);
        expect(c.error, isNotNull);
      }
    },
  );
  test(
      'Clearing materials does not corrupt a separately requested consent save',
      () async {
    final configure = store.configure(
        allowed: true,
        url: 'https://gateway.example',
        token: 'synthetic-gateway-user-token-123456');
    await store.clearMaterials();
    await configure;
    await store.init();
    expect(store.externalAllowed, isTrue);
    expect(store.accessToken, 'synthetic-gateway-user-token-123456');
  });
  test('Ordinary viewing-storage updates preserve in-progress study material',
      () async {
    final c = controller();
    await c.demo();
    await c.generate(studyNotes: true);
    final notes = c.notes;
    final summary = c.result;
    // Playback and other existing features notify this same storage service.
    await TubeStorageService().setPauseWatchHistory(true);
    expect(c.notes, notes);
    expect(c.result, same(summary));
    await TubeStorageService().setPauseWatchHistory(false);
  });
  test(
    'SQLite values are parameterized and material bounds are enforced',
    () async {
      await store.save(
        videoId: 'abcdefghijk',
        title: "Title'); DROP TABLE settings; --",
        notes: 'My notes',
        responses: 'Response',
        digest: 'fixture',
        expectedRevision: store.revision,
      );
      expect(await db.query('settings'), isEmpty);
      await expectLater(
        store.save(
          videoId: 'abcdefghijk',
          title: 'Title',
          notes: 'x' * 30001,
          responses: '',
          digest: '',
          expectedRevision: store.revision,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'Clearing material cancels responses and prevents stale saves',
    () async {
      final c = controller();
      await c.demo();
      await c.generate(studyNotes: true);
      await c.save();
      final old = store.revision;
      await store.clearMaterials();
      expect(await store.listSaved(), isEmpty);
      expect(c.notes, isEmpty);
      expect(c.result, isNull);
      await expectLater(
        store.save(
          videoId: 'abcdefghijk',
          title: 'old',
          notes: 'late',
          responses: '',
          digest: '',
          expectedRevision: old,
        ),
        throwsStateError,
      );
    },
  );
  test(
    'External requests are opt-in, bounded and cached without cookies',
    () async {
      var calls = 0;
      final c = controller(
        () => MockClient((request) async {
          calls++;
          expect(request.url.toString(), 'https://gateway.example/v1/analyze');
          expect(request.headers.containsKey('cookie'), isFalse);
          expect(
            request.headers['authorization'],
            startsWith('Bearer synthetic-'),
          );
          expect(jsonDecode(request.body)['videoId'], 'demo-study');
          return http.Response(jsonEncode(aiResponse()), 200);
        }),
      );
      await c.demo();
      c.setRemote(true);
      expect(c.remote, isFalse);
      expect(c.error, contains('Enable external'));
      await remote(c);
      await c.generate();
      expect(c.result!.provider, startsWith('Gemini'));
      await c.generate();
      expect(calls, 1);
    },
  );
  for (final status in [429, 401, 403, 503, 502]) {
    test(
      'Remote $status failure remains visible and retry uses the same question',
      () async {
        var fail = true;
        final c = controller(
          () => MockClient(
            (r) async => fail
                ? http.Response('failure', status)
                : http.Response(jsonEncode(aiResponse()), 200),
          ),
        );
        await remote(c);
        await c.generate(question: 'What is recall?');
        expect(c.error, isNotNull);
        expect(c.conversation, isEmpty);
        fail = false;
        await c.retry();
        expect(c.error, isNull);
        expect(c.conversation.single.question, 'What is recall?');
      },
    );
  }
  for (final body in [
    '{',
    '[]',
    jsonEncode({
      ...aiResponse(),
      'evidence': [
        {'segmentId': 0, 'quote': 'a fabricated quote from nowhere'},
      ],
    }),
    'x' * 96001,
  ]) {
    test(
      'Malformed or oversized remote output fails safely (${body.length})',
      () async {
        final c = controller(
          () => MockClient((r) async => http.Response(body, 200)),
        );
        await remote(c);
        await c.generate();
        expect(c.error, isNotNull);
        expect(c.result, isNull);
      },
    );
  }
  test(
    'Network and timeout failures do not fabricate an AI response',
    () async {
      for (final e in [
        http.ClientException('offline'),
        TimeoutException('deadline'),
      ]) {
        final c = controller(() => MockClient((r) async => throw e));
        await remote(c);
        await c.generate();
        expect(c.error, isNotNull);
        expect(c.result, isNull);
      }
    },
  );
  test(
      'Cancel and switching videos discard late completions and block duplicate calls',
      () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final c = controller(
      () => MockClient((r) {
        calls++;
        return pending.future;
      }),
    );
    await remote(c);
    final first = c.generate();
    await Future<void>.delayed(Duration.zero);
    await c.generate();
    expect(calls, 1);
    await c.select('abcdefghijk', 'New video');
    pending.complete(http.Response(jsonEncode(aiResponse()), 200));
    await first;
    expect(c.videoId, 'abcdefghijk');
    expect(c.result, isNull);
    expect(c.busy, isFalse);
  });
  test(
      'Changing external consent cancels pending results and clears cached responses',
      () async {
    final pending = Completer<http.Response>();
    final c = controller(() => MockClient((r) => pending.future));
    await remote(c);
    final active = c.generate();
    await Future<void>.delayed(Duration.zero);
    await store.configure(allowed: false, url: '', token: '');
    pending.complete(http.Response(jsonEncode(aiResponse()), 200));
    await active;
    expect(c.remote, isFalse);
    expect(c.result, isNull);
    expect(c.busy, isFalse);
  });
  test(
      'Caption loading does not mutate the player and rejects redirects or unsupported hosts',
      () async {
    final c = controller(
      () => MockClient((r) async {
        expect(r.url.queryParameters['fmt'], 'vtt');
        return http.Response(
          'WEBVTT\n\n00:01.000 --> 00:05.000\nA valid caption with a useful learning explanation.',
          200,
        );
      }),
    );
    await c.select('abcdefghijk', 'Captions');
    await c.loadCaptions(
      TubeSubtitle(
        languageCode: 'en',
        format: 'vtt',
        languageName: 'English',
        url: 'https://www.youtube.com/api/timedtext?v=abcdefghijk',
        isAutoGenerated: false,
      ),
    );
    expect(c.transcript!.segments.single.startMs, 1000);
    await c.loadCaptions(
      TubeSubtitle(
        languageCode: 'en',
        format: 'vtt',
        languageName: 'English',
        url: 'http://127.0.0.1/private',
        isAutoGenerated: false,
      ),
    );
    expect(c.error, contains('unsupported'));
  });
  Future<void> reveal(WidgetTester tester, String text) async {
    final target = find.text(text);
    for (var i = 0; i < 80; i++) {
      if (target.evaluate().isNotEmpty) {
        await tester.ensureVisible(target.first);
        await tester.pumpAndSettle();
        if (target.evaluate().isNotEmpty &&
            tester
                .getRect(find.byType(Scrollable).first)
                .contains(tester.getRect(target.first).center)) {
          return;
        }
      }
      final viewport = tester.getRect(find.byType(Scrollable).first);
      await tester.dragFrom(
        Offset(viewport.left + 4, viewport.center.dy),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
    }
    fail('Could not reach $text');
  }

  testWidgets(
    'Actual dark theme provides labelled, reachable controls and accessible contrast',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final c = controller();
      await tester.pumpWidget(
        MaterialApp(
          theme: TubeTheme.buildThemeData(),
          home: TubeVideoIntelligenceScreen(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.byTooltip('AI privacy and data controls'))
            .tooltip,
        contains('AI privacy'),
      );
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNotNull);
      expect(FocusManager.instance.primaryFocus!.context, isNotNull);
      await reveal(tester, 'Try labelled demo');
      await tester.tap(find.text('Try labelled demo'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Generate summary');
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await tester.pumpWidget(
        MaterialApp(
          theme: TubeTheme.buildThemeData(),
          home: TubeAiPrivacyScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await reveal(tester, 'Save AI privacy choices');
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    },
  );

  testWidgets(
    'Demo summary, video question, source navigation, notes and explicit save form one flow',
    (tester) async {
      final c = controller();
      int? seek;
      await tester.pumpWidget(
        MaterialApp(
          home: TubeVideoIntelligenceScreen(
            controller: c,
            onSeek: (id, d) {
              seek = d.inMilliseconds;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, 'Try labelled demo');
      await tester.tap(find.text('Try labelled demo'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Generate summary');
      await tester.tap(find.text('Generate summary'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Concise summary');
      expect(c.result, isNotNull);
      await reveal(tester, 'Seek to 00:12');
      await tester.tap(find.text('Seek to 00:12').first);
      expect(seek, 12000);
      await reveal(tester, 'Question about this transcript');
      await tester.enterText(
        find.widgetWithText(TextField, 'Question about this transcript'),
        'What is feedback?',
      );
      await reveal(tester, 'Ask question');
      await tester.tap(find.text('Ask question'));
      await tester.pumpAndSettle();
      expect(c.conversation.length, 1);
      await reveal(tester, 'Your editable study notes');
      await tester.enterText(
        find.widgetWithText(TextField, 'Your editable study notes'),
        'My editable notes',
      );
      await reveal(tester, 'Save materials');
      await tester.tap(find.text('Save materials'));
      await tester.pumpAndSettle();
      expect((await store.load('demo-study'))!['notes'], 'My editable notes');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Invalid selection and missing transcript have useful UI states',
    (tester) async {
      final c = controller();
      await tester.pumpWidget(
        MaterialApp(home: TubeVideoIntelligenceScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'YouTube video URL'),
        'http://localhost/private',
      );
      await tester.tap(find.text('Select video'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter a valid YouTube'), findsOneWidget);
      await c.select('abcdefghijk', 'Selected');
      await tester.pumpAndSettle();
      await reveal(tester, 'Use pasted transcript');
      expect(find.textContaining('No transcript loaded'), findsOneWidget);
    },
  );
  testWidgets('An external deletion removes saved titles from an open library',
      (tester) async {
    final c = controller();
    await c.demo();
    await c.save();
    await tester.pumpWidget(
        MaterialApp(home: TubeVideoIntelligenceScreen(controller: c)));
    await tester.pumpAndSettle();
    await reveal(tester, 'Saved video materials');
    expect(find.text('Saved video materials'), findsOneWidget);
    await store.clearMaterials();
    await tester.pumpAndSettle();
    expect(find.text('Saved video materials'), findsNothing);
  });
  testWidgets('Copy uses plain text and export failures remain visible',
      (tester) async {
    String? copied;
    var exports = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = call.arguments['text'] as String;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(TubeShareService.channel, (call) async {
      exports++;
      throw PlatformException(code: 'unavailable');
    });
    final c = controller();
    await tester.pumpWidget(
        MaterialApp(home: TubeVideoIntelligenceScreen(controller: c)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try labelled demo'));
    await tester.pumpAndSettle();
    await reveal(tester, 'Copy materials');
    await tester.tap(find.text('Copy materials'));
    await tester.pumpAndSettle();
    expect(copied, contains('demo-study'));
    expect(find.text('Study material copied.'), findsOneWidget);
    await tester.tap(find.text('Export materials'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(exports, 1);
    expect(find.textContaining('Could not export study materials'),
        findsOneWidget);
    final context = tester.element(find.byType(TubeVideoIntelligenceScreen));
    await TubeShareService.exportText(context, 'Too long', 'x' * 32001);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(exports, 1);
    expect(find.textContaining('Export is limited'), findsOneWidget);
  });
  testWidgets(
    'Privacy screen explains external transfer and clears saved material',
    (tester) async {
      final c = controller();
      await c.demo();
      await c.generate(studyNotes: true);
      await c.save();
      await tester.pumpWidget(
        MaterialApp(home: TubeAiPrivacyScreen(store: store)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Local by default'), findsOneWidget);
      await reveal(tester, 'Clear saved responses and notes');
      await tester.tap(find.text('Clear saved responses and notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(await store.listSaved(), isEmpty);
    },
  );
  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    testWidgets('Workbench is scrollable with large text at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = controller();
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: TubeVideoIntelligenceScreen(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, 'Try labelled demo');
      await tester.tap(find.text('Try labelled demo'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Generate study notes');
      await tester.tap(find.text('Generate study notes'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Save materials');
      expect(tester.takeException(), isNull);
      final semantics = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(find.widgetWithText(FilledButton, 'Save materials'))
            .label,
        contains('Save materials'),
      );
      semantics.dispose();
    });
  }
  testWidgets(
    'Export opens Android sharing with text; copy is an explicit action',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(TubeShareService.channel, (
        call,
      ) async {
        calls.add(call);
        return true;
      });
      final c = controller();
      await tester.pumpWidget(
        MaterialApp(home: TubeVideoIntelligenceScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      await reveal(tester, 'Try labelled demo');
      await tester.tap(find.text('Try labelled demo'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Generate study notes');
      await tester.tap(find.text('Generate study notes'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Export materials');
      await tester.tap(find.text('Export materials'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'shareText');
      expect(calls.single.arguments['text'], contains('Source excerpts'));
    },
  );
  test(
    'Version 2 database upgrades to version 3 without losing watch history',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'tube-intelligence-migration-',
      );
      await databaseFactory.setDatabasesPath(root.path);
      final old = await databaseFactory.openDatabase(
        '${root.path}/shreyx_tube.db',
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE watch_history (video_id TEXT PRIMARY KEY)',
            );
            await db.execute(
              'CREATE TABLE settings (key TEXT PRIMARY KEY,value TEXT)',
            );
            await db.insert('watch_history', {'video_id': 'abcdefghijk'});
          },
        ),
      );
      await old.close();
      final upgraded = await TubeDatabaseService().init();
      expect(await upgraded.getVersion(), 3);
      expect(
        (await upgraded.query('watch_history')).single['video_id'],
        'abcdefghijk',
      );
      expect(await upgraded.query('video_intelligence'), isEmpty);
      await upgraded.close();
      await root.delete(recursive: true);
    },
  );
}
