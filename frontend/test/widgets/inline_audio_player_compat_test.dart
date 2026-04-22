import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/shared/widgets/inline_audio_player.dart';

import '../helpers/fake_home_audio_engine.dart';

void main() {
  testWidgets(
    'compatibility wrapper keeps one engine across rebuilds and url changes',
    (tester) async {
      final engineFactory = FakeHomeAudioEngineFactory();
      StateSetter? hostSetState;
      var currentUrl = 'https://cdn.test/audio/a.mp3';
      var tick = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                hostSetState = setState;
                return Column(
                  children: [
                    Text('tick:$tick'),
                    InlineAudioPlayer(
                      url: currentUrl,
                      title: 'Shared player',
                      engineFactory: engineFactory.create,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(engineFactory.createCount, 1);
      expect(
        engineFactory.single.loadedUrls,
        orderedEquals(['https://cdn.test/audio/a.mp3']),
      );

      hostSetState!(() {
        tick += 1;
      });
      await tester.pump();

      expect(find.text('tick:1'), findsOneWidget);
      expect(engineFactory.createCount, 1);
      expect(engineFactory.single.loadedUrls, hasLength(1));

      hostSetState!(() {
        currentUrl = 'https://cdn.test/audio/b.mp3';
      });
      await tester.pump();

      expect(engineFactory.createCount, 1);
      expect(
        engineFactory.single.loadedUrls,
        orderedEquals([
          'https://cdn.test/audio/a.mp3',
          'https://cdn.test/audio/b.mp3',
        ]),
      );
    },
  );
}
