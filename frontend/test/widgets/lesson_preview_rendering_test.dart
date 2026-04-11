import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:mocktail/mocktail.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/lesson_page.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/shared/media/AveliLessonMediaPlayer.dart';
import 'package:aveli/shared/utils/resolved_media_contract.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockMediaRepository extends Mock implements MediaRepository {}

class _FakeAuthController extends AuthController {
  _FakeAuthController() : super(_MockAuthRepository(), AuthHttpObserver()) {
    state = AuthState(
      profile: Profile(
        id: 'user-1',
        email: 'teacher@example.com',
        createdAt: DateTime.utc(2024, 1, 1),
        updatedAt: DateTime.utc(2024, 1, 1),
      ),
    );
  }

  @override
  Future<void> loadSession({bool hydrateProfile = true}) async {}
}

class _PreviewHarness extends StatefulWidget {
  const _PreviewHarness({
    required this.initialMarkdown,
    required this.initialLessonMedia,
  });

  final String initialMarkdown;
  final List<LessonMediaItem> initialLessonMedia;

  @override
  State<_PreviewHarness> createState() => _PreviewHarnessState();
}

class _PreviewHarnessState extends State<_PreviewHarness> {
  late String markdown;
  late List<LessonMediaItem> lessonMedia;
  int rebuildCount = 0;

  @override
  void initState() {
    super.initState();
    markdown = widget.initialMarkdown;
    lessonMedia = widget.initialLessonMedia;
  }

  void rebuildSame() {
    setState(() => rebuildCount += 1);
  }

  void switchLesson({
    required String nextMarkdown,
    required List<LessonMediaItem> nextLessonMedia,
  }) {
    setState(() {
      markdown = nextMarkdown;
      lessonMedia = nextLessonMedia;
      rebuildCount += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('rebuild:$rebuildCount'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: LessonPageRenderer(
              markdown: markdown,
              lessonMedia: lessonMedia,
            ),
          ),
        ),
      ],
    );
  }
}

class _StyledTextSegment {
  const _StyledTextSegment(this.text, this.style);

  final String text;
  final TextStyle? style;
}

void _collectStyledTextSegments(
  InlineSpan span,
  List<_StyledTextSegment> segments, {
  TextStyle? inheritedStyle,
}) {
  if (span is! TextSpan) return;
  final effectiveStyle = inheritedStyle?.merge(span.style) ?? span.style;
  final text = span.text;
  if (text != null && text.isNotEmpty) {
    segments.add(_StyledTextSegment(text, effectiveStyle));
  }
  final children = span.children;
  if (children == null || children.isEmpty) {
    return;
  }
  for (final child in children) {
    _collectStyledTextSegments(child, segments, inheritedStyle: effectiveStyle);
  }
}

Finder _lessonMediaPlayerFinder(String kind) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is AveliLessonMediaPlayer &&
        widget.kind.trim().toLowerCase() == kind,
    description: 'AveliLessonMediaPlayer(kind: $kind)',
  );
}

Finder _networkImageFinder(String url) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is NetworkImage &&
        (widget.image as NetworkImage).url == url,
    description: 'Image.network($url)',
  );
}

List<_StyledTextSegment> _previewStyledTextSegments(WidgetTester tester) {
  final segments = <_StyledTextSegment>[];
  final richTextFinder = find.descendant(
    of: find.byType(LessonPageRenderer),
    matching: find.byType(RichText),
  );
  for (final richText in tester.widgetList<RichText>(richTextFinder)) {
    _collectStyledTextSegments(richText.text, segments);
  }
  return segments;
}

List<TextStyle?> _previewTextStylesForText(WidgetTester tester, String target) {
  return [
    for (final segment in _previewStyledTextSegments(tester))
      if (segment.text.contains(target)) segment.style,
  ];
}

String _renderedPreviewText(WidgetTester tester) {
  return _previewStyledTextSegments(
    tester,
  ).map((segment) => segment.text).join();
}

LessonMediaItem _lessonMediaItem(
  String id,
  String kind, {
  String? resolvedUrl,
}) {
  return LessonMediaItem(
    id: id,
    lessonId: 'lesson-1',
    mediaAssetId: 'asset-$id',
    position: 1,
    mediaType: kind,
    state: 'ready',
    media: ResolvedMediaData(
      mediaId: 'asset-$id',
      state: 'ready',
      resolvedUrl: resolvedUrl,
    ),
  );
}

Future<void> _pumpPreviewHarness(
  WidgetTester tester, {
  required MediaRepository mediaRepository,
  required String markdown,
  required List<LessonMediaItem> lessonMedia,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => _FakeAuthController()),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://localhost',
            stripePublishableKey: '',
            stripeMerchantDisplayName: 'Test',
            subscriptionsEnabled: false,
          ),
        ),
        mediaRepositoryProvider.overrideWithValue(mediaRepository),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          quill.FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('sv')],
        home: Scaffold(
          body: _PreviewHarness(
            initialMarkdown: markdown,
            initialLessonMedia: lessonMedia,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://cdn.test/fallback.mp3'));
  });

  testWidgets(
    'preview renders image, audio, and video with lesson-style audio chrome and avoids extra async work on rebuild',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mediaRepository = _MockMediaRepository();

      when(() => mediaRepository.resolvePlaybackUrl(any())).thenAnswer(
        (invocation) => invocation.positionalArguments.single as String,
      );

      await _pumpPreviewHarness(
        tester,
        mediaRepository: mediaRepository,
        markdown:
            'Intro\n\n!image(media-image-1)\n\n!audio(media-audio-1)\n\n!video(media-video-1)\n',
        lessonMedia: [
          _lessonMediaItem(
            'media-image-1',
            'image',
            resolvedUrl: 'https://cdn.test/preview-image.webp',
          ),
          _lessonMediaItem(
            'media-audio-1',
            'audio',
            resolvedUrl: 'https://cdn.test/preview-audio.mp3',
          ),
          _lessonMediaItem(
            'media-video-1',
            'video',
            resolvedUrl: 'https://cdn.test/preview-video.mp4',
          ),
        ],
      );

      await tester.pump();
      for (var i = 0; i < 6; i += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        _networkImageFinder('https://cdn.test/preview-image.webp'),
        findsOneWidget,
      );
      expect(_lessonMediaPlayerFinder('audio'), findsOneWidget);
      expect(_lessonMediaPlayerFinder('video'), findsOneWidget);
      expect(find.text('Ljud'), findsNothing);

      final harnessState = tester.state<_PreviewHarnessState>(
        find.byType(_PreviewHarness),
      );
      harnessState.rebuildSame();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preview canonicalizes bold and underline with the same contract as the editor',
    (tester) async {
      final mediaRepository = _MockMediaRepository();

      await _pumpPreviewHarness(
        tester,
        mediaRepository: mediaRepository,
        markdown:
            '<strong>Fet text</strong>\n\n<u>Understruken text</u>\n\n**<u>Fet understruken</u>**',
        lessonMedia: const <LessonMediaItem>[],
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final boldHtmlStyles = _previewTextStylesForText(tester, 'Fet text');
      final underlineStyles = _previewTextStylesForText(
        tester,
        'Understruken text',
      );
      final boldUnderlineStyles = _previewTextStylesForText(
        tester,
        'Fet understruken',
      );

      expect(
        boldHtmlStyles.any((style) => style?.fontWeight == FontWeight.bold),
        isTrue,
      );
      expect(
        underlineStyles.any(
          (style) =>
              style?.decoration?.contains(TextDecoration.underline) ?? false,
        ),
        isTrue,
      );
      expect(
        boldUnderlineStyles.any(
          (style) =>
              style?.fontWeight == FontWeight.bold &&
              (style?.decoration?.contains(TextDecoration.underline) ?? false),
        ),
        isTrue,
      );
    },
  );

  testWidgets('preview renders escaped bold markers as bold text', (
    tester,
  ) async {
    final mediaRepository = _MockMediaRepository();

    await _pumpPreviewHarness(
      tester,
      mediaRepository: mediaRepository,
      markdown: r'\*\*Should have been bold\*\*',
      lessonMedia: const <LessonMediaItem>[],
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final boldStyles = _previewTextStylesForText(
      tester,
      'Should have been bold',
    );

    expect(_renderedPreviewText(tester), contains('Should have been bold'));
    expect(_renderedPreviewText(tester), isNot(contains('**')));
    expect(
      boldStyles.any((style) => style?.fontWeight == FontWeight.bold),
      isTrue,
    );
  });

  testWidgets('broken preview media shows explicit error without retry UI', (
    tester,
  ) async {
    final mediaRepository = _MockMediaRepository();

    when(() => mediaRepository.resolvePlaybackUrl(any())).thenAnswer(
      (invocation) => invocation.positionalArguments.single as String,
    );

    await _pumpPreviewHarness(
      tester,
      mediaRepository: mediaRepository,
      markdown:
          'Intro\n\n!image(media-image-valid)\n\n!audio(media-audio-broken)\n',
      lessonMedia: [
        _lessonMediaItem(
          'media-image-valid',
          'image',
          resolvedUrl: 'https://cdn.test/valid-image.webp',
        ),
        _lessonMediaItem('media-audio-broken', 'audio', resolvedUrl: null),
      ],
    );

    await tester.pump();
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      _networkImageFinder('https://cdn.test/valid-image.webp'),
      findsOneWidget,
    );
    expect(find.text('Lektionsmedia kunde inte laddas.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Försök igen'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unresolved lesson media stays in explicit error state without refetching on rebuild',
    (tester) async {
      final mediaRepository = _MockMediaRepository();

      when(() => mediaRepository.resolvePlaybackUrl(any())).thenAnswer(
        (invocation) => invocation.positionalArguments.single as String,
      );

      await _pumpPreviewHarness(
        tester,
        mediaRepository: mediaRepository,
        markdown: 'Intro\n\n!video(media-video-broken)\n',
        lessonMedia: [
          _lessonMediaItem('media-video-broken', 'video', resolvedUrl: null),
        ],
      );

      await tester.pump();
      for (var i = 0; i < 8; i += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Lektionsmedia kunde inte laddas.'), findsOneWidget);

      final harnessState = tester.state<_PreviewHarnessState>(
        find.byType(_PreviewHarness),
      );
      harnessState.rebuildSame();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Lektionsmedia kunde inte laddas.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching preview lessons ignores stale media resolution work', (
    tester,
  ) async {
    final mediaRepository = _MockMediaRepository();

    await _pumpPreviewHarness(
      tester,
      mediaRepository: mediaRepository,
      markdown: 'Intro\n\n!video(media-video-stale)\n',
      lessonMedia: [
        _lessonMediaItem('media-video-stale', 'video', resolvedUrl: null),
      ],
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final harnessState = tester.state<_PreviewHarnessState>(
      find.byType(_PreviewHarness),
    );
    harnessState.switchLesson(
      nextMarkdown: 'Andra lektionen',
      nextLessonMedia: const <LessonMediaItem>[],
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(harnessState.markdown, 'Andra lektionen');
    expect(_lessonMediaPlayerFinder('video'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
