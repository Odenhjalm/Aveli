import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/shared/widgets/media_player.dart';

class _FakeInlinePlaybackHandle implements InlinePlaybackHandle {
  _FakeInlinePlaybackHandle({required bool isPlaying}) : _isPlaying = isPlaying;

  bool _isPlaying;
  int playCalls = 0;
  int pauseCalls = 0;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Future<void> play() async {
    playCalls++;
    _isPlaying = true;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _isPlaying = false;
  }
}

void main() {
  test('toggleInlinePlayback pauses an active controller instance', () async {
    final handle = _FakeInlinePlaybackHandle(isPlaying: true);

    final playing = await toggleInlinePlayback(handle);

    expect(handle.pauseCalls, 1);
    expect(handle.playCalls, 0);
    expect(playing, isFalse);
    expect(handle.isPlaying, isFalse);
  });

  test('toggleInlinePlayback resumes from paused position/state', () async {
    final handle = _FakeInlinePlaybackHandle(isPlaying: false);

    final playing = await toggleInlinePlayback(handle);

    expect(handle.pauseCalls, 0);
    expect(handle.playCalls, 1);
    expect(playing, isTrue);
    expect(handle.isPlaying, isTrue);
  });

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
