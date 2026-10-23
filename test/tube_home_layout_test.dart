import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shreyx_tube/screens/tube_home_screen.dart';
import 'package:shreyx_tube/services/tube_home_feed_service.dart';
import 'package:shreyx_tube/services/tube_innertube_client.dart';
import 'package:shreyx_tube/services/tube_shorts_service.dart';
import 'package:shreyx_tube/services/tube_storage_service.dart';
import 'package:shreyx_tube/widgets/tube_skeleton.dart';

http.Response _page(String title) => http.Response(
    jsonEncode({
      'contents': [
        {
          'videoRenderer': {
            'videoId': 'abcdefghijk',
            'title': {'simpleText': title},
            'ownerText': {
              'runs': [
                {'text': 'Fixture channel'}
              ]
            },
          }
        }
      ]
    }),
    200);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await TubeStorageService().init();
  });

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('Home loads and refreshes within bounded viewport $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var response = Completer<http.Response>();
      final client = MockClient((_) => response.future);
      final shortsClient = MockClient(
          (_) async => http.Response(jsonEncode({'contents': []}), 200));
      addTearDown(client.close);
      addTearDown(shortsClient.close);
      final screen = TubeHomeScreen(
        feedService: TubeHomeFeedService.withClient(
            TubeInnertubeClient.withClient(client)),
        shortsService: TubeShortsService.withClient(
            TubeInnertubeClient.withClient(shortsClient)),
      );

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(TubeHomeFeedSkeleton), findsOneWidget);
      expect(tester.takeException(), isNull);
      final loadingSize = tester.getSize(find.byType(TubeHomeFeedSkeleton));
      expect(loadingSize.height, greaterThan(0));
      expect(loadingSize.height, lessThan(size.height));

      response.complete(_page('First recommendation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('First recommendation'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.byType(TubeHomeFeedSkeleton), findsNothing);
      expect(tester.takeException(), isNull);

      response = Completer<http.Response>();
      await tester.drag(find.byType(RefreshIndicator), const Offset(0, 350));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('First recommendation'), findsOneWidget);
      expect(tester.takeException(), isNull);
      response.complete(_page('Refreshed recommendation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Refreshed recommendation'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
