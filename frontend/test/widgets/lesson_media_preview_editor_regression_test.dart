import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:mocktail/mocktail.dart';

import 'package:aveli/editor/adapter/markdown_to_editor.dart'
    as markdown_to_editor;
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/presentation/lesson_media_preview.dart';
import 'package:aveli/features/studio/presentation/lesson_media_preview_cache.dart';
import 'package:aveli/shared/utils/lesson_content_pipeline.dart'
    as lesson_pipeline;

class _MockStudioRepository extends Mock implements StudioRepository {}

class _MockMediaRepository extends Mock implements MediaRepository {}

class _ImagePreviewEmbedBuilder implements quill.EmbedBuilder {
  const _ImagePreviewEmbedBuilder();

  @override
  String get key => quill.BlockEmbed.imageType;

  @override
  bool get expanded => false;

  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(child: widget);

  @override
  String toPlainText(quill.Embed node) =>
      quill.Embed.kObjectReplacementCharacter;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final dynamic value = embedContext.node.value.data;
    final lessonMediaId =
        lesson_pipeline.lessonMediaIdFromEmbedValue(value) ?? '';
    final src =
        lesson_pipeline.lessonMediaUrlFromEmbedValue(value) ??
        (value == null ? '' : value.toString());
    return LessonMediaPreview(
      lessonMediaId: lessonMediaId,
      mediaType: 'image',
      src: src,
    );
  }
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

quill.QuillController _buildController(String markdown) {
  return quill.QuillController(
    document: markdown_to_editor.markdownToEditorDocument(markdown: markdown),
    selection: const TextSelection.collapsed(offset: 0),
  );
}

class _MarkdownPreviewHarness extends StatefulWidget {
  const _MarkdownPreviewHarness({required this.initialMarkdown});

  final String initialMarkdown;

  @override
  State<_MarkdownPreviewHarness> createState() =>
      _MarkdownPreviewHarnessState();
}

class _MarkdownPreviewHarnessState extends State<_MarkdownPreviewHarness> {
  late String _markdown;
  late quill.QuillController _controller;

  @override
  void initState() {
    super.initState();
    _markdown = widget.initialMarkdown;
    _controller = _buildController(_markdown);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _replaceMarkdown(String markdown) {
    if (markdown == _markdown) return;
    _controller.dispose();
    _markdown = markdown;
    _controller = _buildController(_markdown);
  }

  void _typeCharacter() {
    setState(() {
      _replaceMarkdown(_markdown.replaceFirst('Eftertext', 'EftertextX'));
    });
  }

  void _deleteCharacter() {
    setState(() {
      _replaceMarkdown(_markdown.replaceFirst('EftertextX', 'Eftertext'));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton(
              key: const ValueKey<String>('type_button'),
              onPressed: _typeCharacter,
              child: const Text('Type'),
            ),
            TextButton(
              key: const ValueKey<String>('backspace_button'),
              onPressed: _deleteCharacter,
              child: const Text('Backspace'),
            ),
          ],
        ),
        Expanded(
          child: quill.QuillEditor.basic(
            controller: _controller,
            config: quill.QuillEditorConfig(
              padding: EdgeInsets.zero,
              embedBuilders: const [_ImagePreviewEmbedBuilder()],
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _pumpEditorHarness(
  WidgetTester tester, {
  required _MockStudioRepository studioRepo,
  required _MockMediaRepository mediaRepo,
  required String initialMarkdown,
  LessonMediaPreviewCache? previewCache,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        studioRepositoryProvider.overrideWithValue(studioRepo),
        mediaRepositoryProvider.overrideWithValue(mediaRepo),
        if (previewCache != null)
          lessonMediaPreviewCacheProvider.overrideWithValue(previewCache),
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
          body: _MarkdownPreviewHarness(initialMarkdown: initialMarkdown),
        ),
      ),
    ),
  );
}

void _stubPreviewDependencies(
  _MockStudioRepository studioRepo,
  _MockMediaRepository mediaRepo, {
  required Future<Map<String, Map<String, dynamic>>> Function(List<String> ids)
  fetchLessonMediaPreviews,
}) {
  when(() => studioRepo.fetchLessonMediaPreviews(any())).thenAnswer((
    invocation,
  ) {
    final ids = List<String>.from(
      invocation.positionalArguments.single as List,
    );
    return fetchLessonMediaPreviews(ids);
  });
  when(() => mediaRepo.resolveDownloadUrl(any())).thenAnswer((invocation) {
    final value = invocation.positionalArguments.single as String;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return 'http://localhost$value';
  });
}

void main() {
  testWidgets(
    'Quill editor applies inserted text immediately while passive preview fetch is pending',
    (tester) async {
      final studioRepo = _MockStudioRepository();
      final mediaRepo = _MockMediaRepository();
      _stubPreviewDependencies(
        studioRepo,
        mediaRepo,
        fetchLessonMediaPreviews: (ids) => Future.delayed(
          const Duration(seconds: 5),
          () => {
            for (final id in ids)
              id: {
                'media_type': 'image',
                'resolved_preview_url': 'https://cdn.test/$id-thumb.webp',
                'file_name': 'image.png',
              },
          },
        ),
      );

      await _pumpEditorHarness(
        tester,
        studioRepo: studioRepo,
        mediaRepo: mediaRepo,
        initialMarkdown: 'Introtext\n\n!image(media-image-1)\n\nEftertext',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('type_button')));
      await tester.pump();

      final harnessState = tester.state<_MarkdownPreviewHarnessState>(
        find.byType(_MarkdownPreviewHarness),
      );
      expect(harnessState._markdown, contains('EftertextX'));
      expect(
        harnessState._controller.document.toPlainText(),
        contains('EftertextX'),
      );
      verify(() => studioRepo.fetchLessonMediaPreviews(any())).called(1);
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'Quill editor applies deleted text immediately while passive preview fetch is pending',
    (tester) async {
      final studioRepo = _MockStudioRepository();
      final mediaRepo = _MockMediaRepository();
      _stubPreviewDependencies(
        studioRepo,
        mediaRepo,
        fetchLessonMediaPreviews: (ids) => Future.delayed(
          const Duration(seconds: 5),
          () => {
            for (final id in ids)
              id: {
                'media_type': 'image',
                'resolved_preview_url': 'https://cdn.test/$id-thumb.webp',
                'file_name': 'image.png',
              },
          },
        ),
      );

      await _pumpEditorHarness(
        tester,
        studioRepo: studioRepo,
        mediaRepo: mediaRepo,
        initialMarkdown: 'Introtext\n\n!image(media-image-1)\n\nEftertextX',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('backspace_button')));
      await tester.pump();

      final harnessState = tester.state<_MarkdownPreviewHarnessState>(
        find.byType(_MarkdownPreviewHarness),
      );
      expect(harnessState._markdown, isNot(contains('EftertextX')));
      expect(harnessState._markdown, contains('Eftertext'));
      expect(
        harnessState._controller.document.toPlainText(),
        isNot(contains('EftertextX')),
      );
      expect(
        harnessState._controller.document.toPlainText(),
        contains('Eftertext'),
      );
      verify(() => studioRepo.fetchLessonMediaPreviews(any())).called(1);
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'LessonMediaPreview renders image previews from batch metadata when embed src is token-only',
    (tester) async {
      final studioRepo = _MockStudioRepository();
      final mediaRepo = _MockMediaRepository();
      _stubPreviewDependencies(
        studioRepo,
        mediaRepo,
        fetchLessonMediaPreviews: (ids) async => {
          for (final id in ids)
            id: {
              'media_type': 'image',
              'resolved_preview_url': 'https://cdn.test/$id-thumb.webp',
              'file_name': 'image.png',
            },
        },
      );

      await _pumpEditorHarness(
        tester,
        studioRepo: studioRepo,
        mediaRepo: mediaRepo,
        initialMarkdown: 'Introtext\n\n!image(media-image-1)\n\nEftertext',
      );
      await tester.pump();

      expect(
        _networkImageFinder('https://cdn.test/media-image-1-thumb.webp'),
        findsOneWidget,
      );
      verify(() => studioRepo.fetchLessonMediaPreviews(any())).called(1);
    },
  );

  testWidgets(
    'LessonMediaPreview ignores raw image URLs without lesson_media_id and shows placeholder',
    (tester) async {
      final studioRepo = _MockStudioRepository();
      final mediaRepo = _MockMediaRepository();
      final telemetry = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          telemetry.add(message);
        }
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      _stubPreviewDependencies(
        studioRepo,
        mediaRepo,
        fetchLessonMediaPreviews: (_) async => <String, Map<String, dynamic>>{},
      );

      await _pumpEditorHarness(
        tester,
        studioRepo: studioRepo,
        mediaRepo: mediaRepo,
        initialMarkdown:
            'Introtext\n\n![](https://cdn.test/raw-image.webp)\n\nEftertext',
      );
      await tester.pump();

      expect(
        _networkImageFinder('https://cdn.test/raw-image.webp'),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('lesson_media_preview_unresolved')),
        findsOneWidget,
      );
      verifyNever(() => studioRepo.fetchLessonMediaPreviews(any()));
      expect(
        telemetry.any(
          (entry) => entry.contains('MISSING_LESSON_MEDIA_ID_RENDER'),
        ),
        isTrue,
      );
      debugPrint = originalDebugPrint;
    },
  );

  testWidgets(
    'LessonMediaPreview treats a waiting preview request as loading without unresolved telemetry',
    (tester) async {
      final studioRepo = _MockStudioRepository();
      final mediaRepo = _MockMediaRepository();
      final previewCompleter = Completer<Map<String, Map<String, dynamic>>>();
      final telemetry = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          telemetry.add(message);
        }
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      _stubPreviewDependencies(
        studioRepo,
        mediaRepo,
        fetchLessonMediaPreviews: (_) => previewCompleter.future,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studioRepositoryProvider.overrideWithValue(studioRepo),
            mediaRepositoryProvider.overrideWithValue(mediaRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 160,
                  child: LessonMediaPreview(
                    lessonMediaId: 'media-image-1',
                    mediaType: 'image',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('lesson_media_preview_loading')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('lesson_media_preview_unresolved')),
        findsNothing,
      );
      expect(
        telemetry.where(
          (entry) => entry.contains('UNRESOLVED_LESSON_MEDIA_RENDER'),
        ),
        isEmpty,
      );

      previewCompleter.complete(<String, Map<String, dynamic>>{});
      await tester.pump();
      debugPrint = originalDebugPrint;
    },
  );

  testWidgets(
    'LessonMediaPreview keeps transient unresolved image previews in processing until the resolver catches up',
    (tester) async {
      final studioRepo = _MockStudioRepository();
      final mediaRepo = _MockMediaRepository();
      var fetchCount = 0;
      final retryCompleter = Completer<Map<String, Map<String, dynamic>>>();
      _stubPreviewDependencies(
        studioRepo,
        mediaRepo,
        fetchLessonMediaPreviews: (_) {
          fetchCount += 1;
          if (fetchCount == 1) {
            return Future<Map<String, Map<String, dynamic>>>.value({
              'media-image-1': {
                'media_type': 'image',
                'authoritative_editor_ready': false,
                'failure_reason': 'unresolvable',
                'file_name': 'image.png',
              },
            });
          }
          return retryCompleter.future;
        },
      );
      final previewCache = LessonMediaPreviewCache(
        studioRepository: studioRepo,
        transientResolverRetryDelay: const Duration(milliseconds: 1),
        transientResolverMaxRetries: 2,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studioRepositoryProvider.overrideWithValue(studioRepo),
            mediaRepositoryProvider.overrideWithValue(mediaRepo),
            lessonMediaPreviewCacheProvider.overrideWithValue(previewCache),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 160,
                  child: LessonMediaPreview(
                    lessonMediaId: 'media-image-1',
                    mediaType: 'image',
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2));

      expect(
        find.byKey(const ValueKey<String>('lesson_media_preview_loading')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('lesson_media_preview_unresolved')),
        findsNothing,
      );

      retryCompleter.complete({
        'media-image-1': {
          'media_type': 'image',
          'authoritative_editor_ready': true,
          'resolved_preview_url': 'https://cdn.test/backend-image-1.webp',
          'file_name': 'image.png',
        },
      });
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();

      expect(
        _networkImageFinder('https://cdn.test/backend-image-1.webp'),
        findsOneWidget,
      );
      expect(fetchCount, 2);
    },
  );

  testWidgets(
    'LessonMediaPreview ignores metadata fallbacks and shows unresolved placeholders',
    (tester) async {
      final studioRepo = _MockStudioRepository();
      final mediaRepo = _MockMediaRepository();
      final telemetry = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          telemetry.add(message);
        }
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      _stubPreviewDependencies(
        studioRepo,
        mediaRepo,
        fetchLessonMediaPreviews: (_) async => {
          'media-image-1': {
            'media_type': 'image',
            'authoritative_editor_ready': false,
            'failure_reason': 'unresolvable',
          },
        },
      );

      final container = ProviderContainer(
        overrides: [
          studioRepositoryProvider.overrideWithValue(studioRepo),
          mediaRepositoryProvider.overrideWithValue(mediaRepo),
          lessonMediaPreviewCacheProvider.overrideWithValue(
            LessonMediaPreviewCache(
              studioRepository: studioRepo,
              transientResolverMaxRetries: 0,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final cache = container.read(lessonMediaPreviewCacheProvider);
      cache.primeFromLessonMedia([
        {
          'id': 'media-image-1',
          'kind': 'image',
          'preferredUrl': 'https://cdn.test/media-image-1.webp',
          'original_name': 'image.png',
        },
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 160,
                  child: LessonMediaPreview(
                    lessonMediaId: 'media-image-1',
                    mediaType: 'image',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        _networkImageFinder('https://cdn.test/media-image-1.webp'),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('lesson_media_preview_unresolved')),
        findsOneWidget,
      );
      expect(
        telemetry.where(
          (entry) => entry.contains('UNRESOLVED_LESSON_MEDIA_RENDER'),
        ),
        hasLength(1),
      );
      debugPrint = originalDebugPrint;
    },
  );

  testWidgets(
    'LessonMediaPreview re-logs unresolved when a failed preview remount triggers a fresh resolver retry',
    (tester) async {
      final studioRepo = _MockStudioRepository();
      final mediaRepo = _MockMediaRepository();
      final telemetry = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          telemetry.add(message);
        }
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      _stubPreviewDependencies(
        studioRepo,
        mediaRepo,
        fetchLessonMediaPreviews: (_) async => {
          'media-image-1': {
            'media_type': 'image',
            'authoritative_editor_ready': false,
            'failure_reason': 'unresolvable',
          },
        },
      );

      final container = ProviderContainer(
        overrides: [
          studioRepositoryProvider.overrideWithValue(studioRepo),
          mediaRepositoryProvider.overrideWithValue(mediaRepo),
          lessonMediaPreviewCacheProvider.overrideWithValue(
            LessonMediaPreviewCache(
              studioRepository: studioRepo,
              transientResolverMaxRetries: 0,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      Widget buildPreview({required Key key}) {
        return UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 160,
                  child: LessonMediaPreview(
                    key: key,
                    lessonMediaId: 'media-image-1',
                    mediaType: 'image',
                  ),
                ),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildPreview(key: const ValueKey('first')));
      await tester.pump();

      expect(
        telemetry.where(
          (entry) => entry.contains('UNRESOLVED_LESSON_MEDIA_RENDER'),
        ),
        hasLength(1),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(buildPreview(key: const ValueKey('second')));
      await tester.pump();

      expect(
        telemetry.where(
          (entry) => entry.contains('UNRESOLVED_LESSON_MEDIA_RENDER'),
        ),
        hasLength(2),
      );
      debugPrint = originalDebugPrint;
    },
  );

  testWidgets(
    'LessonMediaPreview keeps unresolved placeholders compact in narrow layouts',
    (tester) async {
      final studioRepo = _MockStudioRepository();
      final mediaRepo = _MockMediaRepository();
      _stubPreviewDependencies(
        studioRepo,
        mediaRepo,
        fetchLessonMediaPreviews: (_) async => {
          'media-image-1': {
            'media_type': 'image',
            'authoritative_editor_ready': false,
            'failure_reason': 'unresolvable',
          },
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studioRepositoryProvider.overrideWithValue(studioRepo),
            mediaRepositoryProvider.overrideWithValue(mediaRepo),
            lessonMediaPreviewCacheProvider.overrideWithValue(
              LessonMediaPreviewCache(
                studioRepository: studioRepo,
                transientResolverMaxRetries: 0,
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 116,
                  child: LessonMediaPreview(
                    lessonMediaId: 'media-image-1',
                    mediaType: 'image',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('lesson_media_preview_unresolved')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
