import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shreyx_tube/providers/tube_intelligence_controller.dart';
import 'package:shreyx_tube/screens/tube_video_intelligence_screen.dart';
import 'package:shreyx_tube/services/tube_intelligence_store.dart';
import 'package:shreyx_tube/theme/tube_theme.dart';

// Run only on the owned emulator. This uses original sample text and deletes
// only this test's study materials; no human account or video session is used.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'Android offline study journey persists, reopens and deletes data',
      (tester) async {
    final store = TubeIntelligenceStore();
    await store.init();
    await store.clearMaterials();
    final c = TubeIntelligenceController(
        store: store,
        clientFactory: () =>
            throw StateError('Offline demo must not use HTTP'));
    int? seek;
    Future<void> reveal(String text) async {
      for (var i = 0; i < 100; i++) {
        final target = find.text(text);
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
        await tester.dragFrom(Offset(viewport.left + 4, viewport.center.dy),
            const Offset(0, -350));
        await tester.pumpAndSettle();
      }
      fail('Could not reach $text');
    }

    await tester.pumpWidget(MaterialApp(
        theme: TubeTheme.buildThemeData(),
        home: TubeVideoIntelligenceScreen(
            controller: c,
            onSeek: (id, time) {
              expect(id, 'demo-study');
              seek = time.inMilliseconds;
              return true;
            })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try labelled demo'));
    await tester.pumpAndSettle();
    await reveal('Generate summary');
    await tester.tap(find.text('Generate summary'));
    await tester.pumpAndSettle();
    expect(c.result!.provider, contains('local'));
    await reveal('Seek to 00:12');
    await tester.tap(find.text('Seek to 00:12').first);
    expect(seek, 12000);
    await reveal('Question about this transcript');
    await tester.enterText(
        find.widgetWithText(TextField, 'Question about this transcript'),
        'What is feedback?');
    await reveal('Ask question');
    await tester.tap(find.text('Ask question'));
    await tester.pumpAndSettle();
    expect(c.conversation.single.result.evidence, isNotEmpty);
    await reveal('Your editable study notes');
    await tester.enterText(
        find.widgetWithText(TextField, 'Your editable study notes'),
        'Android study journey fixture');
    await reveal('Save materials');
    await tester.tap(find.text('Save materials'));
    await tester.pumpAndSettle();
    expect((await store.load('demo-study'))!['notes'],
        'Android study journey fixture');
    await tester.tap(find.text('Copy materials'));
    for (var i = 0;
        i < 30 && find.text('Study material copied.').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Study material copied.'), findsOneWidget);
    expect((await Clipboard.getData(Clipboard.kTextPlain))?.text,
        contains('Android study journey fixture'));

    await tester.pumpWidget(const SizedBox());
    c.dispose();
    final restored = TubeIntelligenceController(store: store);
    await tester.pumpWidget(MaterialApp(
        theme: TubeTheme.buildThemeData(),
        home: TubeVideoIntelligenceScreen(
            controller: restored,
            videoId: 'demo-study',
            title: 'Saved Android study')));
    await tester.pumpAndSettle();
    expect(restored.notes, 'Android study journey fixture');
    expect(restored.savedResponses, contains('feedback'));
    await tester.tap(find.byTooltip('AI privacy and data controls'));
    await tester.pumpAndSettle();
    await reveal('Clear saved responses and notes');
    await tester.tap(find.text('Clear saved responses and notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(await store.listSaved(), isEmpty);
    expect(restored.notes, isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Saved video materials'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    restored.dispose();
  });
}
