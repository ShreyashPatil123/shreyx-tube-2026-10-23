import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shreyx_tube/models/tube_models.dart';
import 'package:shreyx_tube/services/tube_share_service.dart';
import 'package:shreyx_tube/services/tube_buffer_recovery.dart';
import 'package:shreyx_tube/widgets/tube_shorts_shelf.dart';

const item = TubeVideoItem(
    id: 'abcdefghijk',
    title:
        'A long Shorts title that must wrap across two lines without overflow',
    channelTitle: 'Fixture channel',
    channelId: 'UCfixture',
    isShort: true,
    thumbnailUrl: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  testWidgets(
      'Share opens native sharing with the original video URL, without copying',
      (tester) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(TubeShareService.channel, (c) async {
      calls.add(c);
      return true;
    });
    final clipboard = <MethodCall>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      clipboard.add(c);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(TubeShareService.channel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => TubeShareService.share(context, item),
                child: const Text('Share')))));
    await tester.tap(find.text('Share'));
    await tester.pump();
    expect(calls.single.method, 'shareVideo');
    expect(calls.single.arguments, {'url': item.watchUrl, 'title': item.title});
    expect(clipboard.where((c) => c.method == 'Clipboard.setData'), isEmpty);
  });
  testWidgets('Unavailable share menu reports a failure', (tester) async {
    messenger.setMockMethodCallHandler(
        TubeShareService.channel, (_) async => false);
    addTearDown(() =>
        messenger.setMockMethodCallHandler(TubeShareService.channel, null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => TubeShareService.share(context, item),
                    child: const Text('Share'))))));
    await tester.tap(find.text('Share'));
    await tester.pump();
    expect(find.text('Could not open the share menu. Retry.'), findsOneWidget);
  });
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('Shorts shelf fits portrait cards and scaled titles at $scale',
        (tester) async {
      TubeVideoItem? selected;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MediaQuery(
                  data: MediaQueryData(
                      size: const Size(360, 800),
                      textScaler: TextScaler.linear(scale)),
                  child: SingleChildScrollView(
                      child: TubeShortsShelf(
                          items: const [item, item],
                          onOpen: (v) => selected = v))))));
      expect(tester.takeException(), isNull);
      final aspect = find
          .descendant(
              of: find.byType(TubeShortsShelf),
              matching: find.byType(AspectRatio))
          .first;
      final image = tester.getSize(aspect);
      expect(image.height / image.width, closeTo(16 / 9, 0.001));
      await tester.tap(find.text(item.title).first);
      await tester.pump();
      expect(selected, item);
      expect(tester.takeException(), isNull);
    });
  }
  test(
      'Buffer recovery ignores initial loading and seeks, then detects sustained starvation',
      () {
    final p = TubeBufferRecovery();
    final start = DateTime(2026);
    expect(p.buffering(start, ahead: Duration.zero), isFalse);
    p.playing();
    p.seeking(start);
    expect(
        p.buffering(start.add(const Duration(seconds: 2)),
            ahead: Duration.zero),
        isFalse);
    expect(
        p.buffering(start.add(const Duration(seconds: 6)),
            ahead: Duration.zero),
        isFalse);
    expect(
        p.buffering(start.add(const Duration(seconds: 8)),
            ahead: Duration.zero),
        isTrue);
    expect(
        p.buffering(start.add(const Duration(seconds: 9)),
            ahead: Duration.zero),
        isFalse);
  });
  test(
      'Three low-buffer stalls trigger recovery; ready buffer and reset do not',
      () {
    final p = TubeBufferRecovery();
    final start = DateTime(2026);
    p.playing();
    for (var i = 0; i < 2; i++) {
      expect(
          p.buffering(start.add(Duration(seconds: i * 3)),
              ahead: Duration.zero),
          isFalse);
      p.playing();
    }
    expect(
        p.buffering(start.add(const Duration(seconds: 6)),
            ahead: const Duration(seconds: 8)),
        isFalse);
    expect(
        p.buffering(start.add(const Duration(seconds: 7)),
            ahead: Duration.zero),
        isTrue);
    p.reset();
    expect(
        p.buffering(start.add(const Duration(seconds: 40)),
            ahead: Duration.zero),
        isFalse);
  });
}
