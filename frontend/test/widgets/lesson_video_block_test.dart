import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/shared/widgets/lesson_video_block.dart';
import 'package:aveli/shared/widgets/media_player.dart';

void main() {
  const sampleUrl = 'https://cdn.example.com/lesson.mp4';
  const containerKey = Key('test_lesson_video_block_container');
  const surfaceKey = Key('test_lesson_video_block_surface');
  const playerKey = Key('test_lesson_video_block_player');

  testWidgets('renders responsive block container with shared video player', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1280,
              child: LessonVideoBlock(
                url: sampleUrl,
                title: 'Demo',
                containerKey: containerKey,
                surfaceKey: surfaceKey,
                playerKey: playerKey,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byKey(containerKey), findsOneWidget);
    expect(find.byKey(surfaceKey), findsOneWidget);
    expect(find.byType(InlineVideoPlayer), findsOneWidget);
    expect(find.text('Spela video'), findsOneWidget);

    await tester.tap(find.byKey(surfaceKey));
    await tester.pump();
    expect(find.text('Laddar ström...'), findsOneWidget);

    final size = tester.getSize(find.byKey(containerKey));
    expect(size.width, lessThanOrEqualTo(920));
    expect(size.width, greaterThan(880));
  });

  testWidgets('video block stays between text nodes instead of inline flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ovanför'),
                LessonVideoBlock(
                  url: sampleUrl,
                  containerKey: containerKey,
                  surfaceKey: surfaceKey,
                  playerKey: playerKey,
                ),
                Text('Nedanför'),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final topTextBottom = tester.getBottomLeft(find.text('Ovanför')).dy;
    final blockTop = tester.getTopLeft(find.byKey(containerKey)).dy;
    final blockBottom = tester.getBottomLeft(find.byKey(containerKey)).dy;
    final bottomTextTop = tester.getTopLeft(find.text('Nedanför')).dy;

    expect(blockTop, greaterThan(topTextBottom));
    expect(bottomTextTop, greaterThan(blockBottom));
  });

  testWidgets('video block semantics expose editor accessibility labels', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LessonVideoBlock(
              url: sampleUrl,
              containerKey: containerKey,
              surfaceKey: surfaceKey,
              playerKey: playerKey,
              semanticLabel: 'Videoblock i lektionseditorn',
              semanticHint: 'Aktivera med Enter eller mellanslag.',
            ),
          ),
        ),
      );

      await tester.pump();

      final semanticsNode = tester.getSemantics(find.byKey(surfaceKey));
      expect(semanticsNode.label, contains('Videoblock i lektionseditorn'));
      expect(
        semanticsNode.hint,
        contains('Aktivera med Enter eller mellanslag.'),
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('uses same control affordance as home inline player', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              InlineVideoPlayer(url: sampleUrl),
              LessonVideoBlock(
                url: sampleUrl,
                containerKey: containerKey,
                surfaceKey: surfaceKey,
                playerKey: playerKey,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(InlineVideoPlayer), findsNWidgets(2));
    expect(find.text('Spela video'), findsNWidgets(2));
  });
}
