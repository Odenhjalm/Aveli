import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:markdown/markdown.dart' as md;
import 'package:mocktail/mocktail.dart';

import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_repository.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/presentation/lesson_media_preview.dart';
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
  final markdownDocument = md.Document(
    encodeHtml: false,
    extensionSet: md.ExtensionSet.gitHubWeb,
  );
  final converter = lesson_pipeline.createLessonMarkdownToDelta(
    markdownDocument,
  );
  final delta = lesson_pipeline.convertLessonMarkdownToDelta(
    converter,
    markdown,
  );
  return quill.QuillController(
    document: quill.Document.fromDelta(delta),
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
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        studioRepositoryProvider.overrideWithValue(studioRepo),
        mediaRepositoryProvider.overrideWithValue(mediaRepo),
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
                'thumbnail_url': 'https://cdn.test/$id-thumb.webp',
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
                'thumbnail_url': 'https://cdn.test/$id-thumb.webp',
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
              'thumbnail_url': 'https://cdn.test/$id-thumb.webp',
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
}
