import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/shared/widgets/media_player.dart';

class _FakeInlinePlaybackHandle implements InlinePlaybackHandle {
  _FakeInlinePlaybackHandle({required bool isPlaying}) : _isPlaying = isPlaying;

  bool _isPlaying;
  int playCalls = 0;
  int pauseCalls = 0;
  int seekToStartCalls = 0;

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

  @override
  Future<void> seekToStart() async {
    seekToStartCalls++;
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

  test('stopInlinePlayback pauses and seeks to the beginning', () async {
    final handle = _FakeInlinePlaybackHandle(isPlaying: true);

    final playing = await stopInlinePlayback(handle);

    expect(handle.pauseCalls, 1);
    expect(handle.seekToStartCalls, 1);
    expect(handle.playCalls, 0);
    expect(playing, isFalse);
    expect(handle.isPlaying, isFalse);
  });

  test('controls mode resolves home and lesson/editor chrome consistently', () {
    final home = resolveInlineVideoControls(
      controlsMode: InlineVideoControlsMode.home,
      minimalUi: false,
      controlChrome: InlineVideoControlChrome.playPause,
    );
    expect(home.minimalUi, isTrue);
    expect(home.controlChrome, InlineVideoControlChrome.hidden);

    final lesson = resolveInlineVideoControls(
      controlsMode: InlineVideoControlsMode.lesson,
      minimalUi: false,
      controlChrome: InlineVideoControlChrome.hidden,
    );
    expect(lesson.minimalUi, isTrue);
    expect(lesson.controlChrome, InlineVideoControlChrome.playPauseAndStop);

    final editor = resolveInlineVideoControls(
      controlsMode: InlineVideoControlsMode.editor,
      minimalUi: false,
      controlChrome: InlineVideoControlChrome.hidden,
    );
    expect(editor.minimalUi, isTrue);
    expect(editor.controlChrome, InlineVideoControlChrome.playPauseAndStop);
  });

  testWidgets('lesson/editor modes expose stop button and home mode hides it', (
    tester,
  ) async {
    Future<bool>? stopFuture;

    Future<void> pumpOverlay({
      required InlineVideoControlsMode mode,
      required _FakeInlinePlaybackHandle handle,
    }) async {
      final config = resolveInlineVideoControls(
        controlsMode: mode,
        minimalUi: false,
        controlChrome: InlineVideoControlChrome.hidden,
      );
      stopFuture = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: InlineVideoControlOverlay(
                isPlaying: true,
                showStopButton:
                    config.controlChrome ==
                    InlineVideoControlChrome.playPauseAndStop,
                onToggle: () {},
                onStop: () {
                  stopFuture = stopInlinePlayback(handle);
                },
              ),
            ),
          ),
        ),
      );
    }

    final lessonHandle = _FakeInlinePlaybackHandle(isPlaying: true);
    await pumpOverlay(
      mode: InlineVideoControlsMode.lesson,
      handle: lessonHandle,
    );
    expect(find.byTooltip('Stoppa'), findsOneWidget);
    await tester.tap(find.byTooltip('Stoppa'));
    await tester.pump();
    await stopFuture!;
    expect(lessonHandle.pauseCalls, 1);
    expect(lessonHandle.seekToStartCalls, 1);

    final editorHandle = _FakeInlinePlaybackHandle(isPlaying: true);
    await pumpOverlay(
      mode: InlineVideoControlsMode.editor,
      handle: editorHandle,
    );
    expect(find.byTooltip('Stoppa'), findsOneWidget);
    await tester.tap(find.byTooltip('Stoppa'));
    await tester.pump();
    await stopFuture!;
    expect(editorHandle.pauseCalls, 1);
    expect(editorHandle.seekToStartCalls, 1);

    final homeHandle = _FakeInlinePlaybackHandle(isPlaying: true);
    await pumpOverlay(mode: InlineVideoControlsMode.home, handle: homeHandle);
    expect(find.byTooltip('Stoppa'), findsNothing);
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

  testWidgets(
    'surface tap keeps toggling even when overlay controls are present',
    (tester) async {
      var isPlaying = false;
      var stopCalls = 0;

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
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: Colors.black12,
                            child: Center(
                              child: Text(isPlaying ? 'Spelar' : 'Pausad'),
                            ),
                          ),
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: InlineVideoControlOverlay(
                              isPlaying: isPlaying,
                              showStopButton: true,
                              onToggle: () {
                                setState(() => isPlaying = !isPlaying);
                              },
                              onStop: () {
                                setState(() {
                                  stopCalls++;
                                  isPlaying = false;
                                });
                              },
                            ),
                          ),
                        ],
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

      await tester.tapAt(tester.getCenter(find.byType(VideoSurfaceTapTarget)));
      await tester.pump();
      expect(find.text('Spelar'), findsOneWidget);

      await tester.tap(find.byTooltip('Stoppa'));
      await tester.pump();
      expect(stopCalls, 1);
      expect(find.text('Pausad'), findsOneWidget);

      await tester.tapAt(tester.getCenter(find.byType(VideoSurfaceTapTarget)));
      await tester.pump();
      expect(find.text('Spelar'), findsOneWidget);
    },
  );

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

  testWidgets('keyboard S triggers stop action when surface provides it', (
    tester,
  ) async {
    final focusNode = FocusNode(debugLabel: 'test_video_surface_with_stop');
    addTearDown(focusNode.dispose);
    var isPlaying = true;
    var stopCalls = 0;

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
                    semanticHint:
                        'Mellanslag växlar uppspelning och S stoppar.',
                    onActivate: () {
                      setState(() => isPlaying = !isPlaying);
                    },
                    onStop: () {
                      setState(() {
                        stopCalls++;
                        isPlaying = false;
                      });
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

    expect(find.text('Spelar'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    expect(stopCalls, 1);
    expect(find.text('Pausad'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('Spelar'), findsOneWidget);
  });

  testWidgets('inline player keeps active state across same-url rebuild', (
    tester,
  ) async {
    StateSetter? hostSetState;
    var rebuildTick = 0;
    var currentUrl = 'https://cdn.example.com/a.mp4';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              hostSetState = setState;
              return Column(
                children: [
                  Text('tick:$rebuildTick'),
                  InlineVideoPlayer(url: currentUrl),
                ],
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Spela video'), findsOneWidget);

    await tester.tap(find.byType(VideoSurfaceTapTarget));
    await tester.pump();
    expect(find.text('Laddar ström...'), findsOneWidget);

    hostSetState!(() {
      rebuildTick++;
    });
    await tester.pump();

    expect(find.text('tick:1'), findsOneWidget);
    expect(find.text('Laddar ström...'), findsOneWidget);
    expect(find.text('Spela video'), findsNothing);
  });

  testWidgets('inline player resets when media url changes', (tester) async {
    StateSetter? hostSetState;
    var currentUrl = 'https://cdn.example.com/a.mp4';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              hostSetState = setState;
              return InlineVideoPlayer(url: currentUrl);
            },
          ),
        ),
      ),
    );

    expect(find.text('Spela video'), findsOneWidget);

    await tester.tap(find.byType(VideoSurfaceTapTarget));
    await tester.pump();
    expect(find.text('Laddar ström...'), findsOneWidget);

    hostSetState!(() {
      currentUrl = 'https://cdn.example.com/b.mp4';
    });
    await tester.pump();

    expect(find.text('Spela video'), findsOneWidget);
    expect(find.text('Laddar ström...'), findsNothing);
  });
}
