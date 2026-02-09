import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/shared/widgets/media_player.dart';

void main() {
  testWidgets('surface tap toggles play pause resume state', (tester) async {
    var isPlaying = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Center(
                child: SizedBox(
                  width: 320,
                  height: 180,
                  child: VideoSurfaceTapTarget(
                    semanticLabel: 'Testspelare',
                    semanticHint: 'Tryck för att spela eller pausa.',
                    onActivate: () {
                      setState(() => isPlaying = !isPlaying);
                    },
                    child: ColoredBox(
                      color: Colors.black12,
                      child: Center(
                        child: Text(isPlaying ? 'Spelar' : 'Pausad'),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Pausad'), findsOneWidget);

    await tester.tap(find.byType(VideoSurfaceTapTarget));
    await tester.pump();
    expect(find.text('Spelar'), findsOneWidget);

    await tester.tap(find.byType(VideoSurfaceTapTarget));
    await tester.pump();
    expect(find.text('Pausad'), findsOneWidget);

    await tester.tap(find.byType(VideoSurfaceTapTarget));
    await tester.pump();
    expect(find.text('Spelar'), findsOneWidget);
  });

  testWidgets('keyboard space toggles playback on focused surface', (
    tester,
  ) async {
    final focusNode = FocusNode(debugLabel: 'test_video_surface');
    addTearDown(focusNode.dispose);
    var isPlaying = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Center(
                child: SizedBox(
                  width: 320,
                  height: 180,
                  child: VideoSurfaceTapTarget(
                    focusNode: focusNode,
                    semanticLabel: 'Testspelare',
                    semanticHint: 'Mellanslag eller Enter växlar uppspelning.',
                    onActivate: () {
                      setState(() => isPlaying = !isPlaying);
                    },
                    child: ColoredBox(
                      color: Colors.black12,
                      child: Center(
                        child: Text(isPlaying ? 'Spelar' : 'Pausad'),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    expect(find.text('Pausad'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('Spelar'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('Pausad'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('Spelar'), findsOneWidget);
  });
}
