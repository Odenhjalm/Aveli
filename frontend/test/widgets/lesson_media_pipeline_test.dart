import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/editor/document/lesson_document.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/lesson_page.dart';
import 'package:aveli/shared/media/AveliLessonImage.dart';
import 'package:aveli/shared/media/AveliLessonMediaPlayer.dart';
import 'package:aveli/shared/utils/resolved_media_contract.dart';

LessonDetailData _buildLessonData({
  required List<LessonMediaItem> media,
  LessonDocument contentDocument = _defaultLessonDocument,
  LessonDetail? lesson,
  List<LessonSummary>? lessons,
}) {
  final effectiveLesson =
      lesson ??
      const LessonDetail(
        id: 'lesson-1',
        lessonTitle: 'Lektion',
        contentDocument: _defaultLessonDocument,
        position: 1,
      );
  return LessonDetailData(
    lesson: LessonDetail(
      id: effectiveLesson.id,
      lessonTitle: effectiveLesson.lessonTitle,
      contentDocument: contentDocument,
      position: effectiveLesson.position,
    ),
    courseId: 'course-1',
    lessons:
        lessons ??
        const [
          LessonSummary(id: 'lesson-1', lessonTitle: 'Lektion', position: 1),
        ],
    media: media,
  );
}

const LessonDocument _defaultLessonDocument = LessonDocument(
  blocks: [
    LessonHeadingBlock(level: 2, children: [LessonTextRun('Lektion')]),
  ],
);

LessonDocument _paragraphDocument(List<String> paragraphs) {
  return LessonDocument(
    blocks: [
      for (final paragraph in paragraphs)
        LessonParagraphBlock(children: [LessonTextRun(paragraph)]),
    ],
  );
}

LessonDocument _mediaDocument({
  required String mediaType,
  required String lessonMediaId,
  List<String> paragraphs = const <String>[],
}) {
  return LessonDocument(
    blocks: [
      for (final paragraph in paragraphs)
        LessonParagraphBlock(children: [LessonTextRun(paragraph)]),
      LessonMediaBlock(mediaType: mediaType, lessonMediaId: lessonMediaId),
    ],
  );
}

CourseAccessData _courseState({
  int currentUnlockPosition = 1,
  bool canAccess = true,
  DateTime? nextUnlockAt,
}) {
  return CourseAccessData(
    courseId: 'course-1',
    groupPosition: 0,
    requiredEnrollmentSource: 'intro_enrollment',
    enrollable: true,
    purchasable: false,
    isIntroCourse: true,
    selectionLocked: false,
    canAccess: canAccess,
    nextUnlockAt: nextUnlockAt,
    enrollment: CourseEnrollmentRecord(
      id: 'enrollment-1',
      userId: 'user-1',
      courseId: 'course-1',
      source: 'intro_enrollment',
      grantedAt: DateTime.utc(2024, 1, 1),
      dripStartedAt: DateTime.utc(2024, 1, 1),
      currentUnlockPosition: currentUnlockPosition,
    ),
  );
}

LessonMediaItem _lessonMediaItem({
  required String id,
  required String mediaType,
  required String state,
  String? resolvedUrl,
}) {
  return LessonMediaItem(
    id: id,
    lessonId: 'lesson-1',
    mediaAssetId: 'asset-1',
    position: 1,
    mediaType: mediaType,
    state: state,
    media: resolvedUrl == null
        ? null
        : ResolvedMediaData(
            mediaId: 'asset-1',
            state: state,
            resolvedUrl: resolvedUrl,
          ),
  );
}

Finder _lessonAudioMediaPlayerFinder() {
  return find.byWidgetPredicate(
    (widget) => widget is AveliLessonMediaPlayer && widget.kind == 'audio',
    description: 'AveliLessonMediaPlayer(kind: audio)',
  );
}

Future<void> _pumpLessonPage(
  WidgetTester tester, {
  required LessonDetailData data,
  CourseAccessData? courseState,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://localhost',
            subscriptionsEnabled: false,
          ),
        ),
        lessonDetailProvider.overrideWith((ref, lessonId) async => data),
        courseStateProvider.overrideWith(
          (ref, courseId) async => courseState ?? _courseState(),
        ),
      ],
      child: const MaterialApp(home: LessonPage(lessonId: 'lesson-1')),
    ),
  );
}

Future<void> _pumpLessonPageWithError(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://localhost',
            subscriptionsEnabled: false,
          ),
        ),
        lessonDetailProvider.overrideWith(
          (ref, lessonId) async => throw StateError('Malformed lesson payload'),
        ),
        courseStateProvider.overrideWith(
          (ref, courseId) async => _courseState(),
        ),
      ],
      child: const MaterialApp(home: LessonPage(lessonId: 'lesson-1')),
    ),
  );
}

void main() {
  testWidgets('lesson renders empty content state without crashing', (
    tester,
  ) async {
    final data = _buildLessonData(
      media: const [],
      contentDocument: LessonDocument.empty(),
    );

    await _pumpLessonPage(tester, data: data);
    await tester.pumpAndSettle();

    expect(find.text('Lektionsinnehållet saknas.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lesson handles provider errors without render exceptions', (
    tester,
  ) async {
    await _pumpLessonPageWithError(tester);
    await tester.pumpAndSettle();

    expect(find.text('Lektionen kunde inte laddas.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('embedded media without backend row renders unavailable state', (
    tester,
  ) async {
    final data = _buildLessonData(
      media: const [],
      contentDocument: _mediaDocument(
        mediaType: 'video',
        lessonMediaId: 'media-video-missing',
        paragraphs: const ['Intro'],
      ),
    );

    await _pumpLessonPage(tester, data: data);
    await tester.pump();
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Lektionsmedia kunde inte laddas.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hides non-embedded processing audio without requesting playback',
    (tester) async {
      final data = _buildLessonData(
        media: [
          _lessonMediaItem(
            id: 'media-audio-1',
            mediaType: 'audio',
            state: 'processing',
          ),
        ],
      );

      await _pumpLessonPage(tester, data: data);
      await tester.pumpAndSettle();

      expect(_lessonAudioMediaPlayerFinder(), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hides non-embedded ready audio without requesting playback', (
    tester,
  ) async {
    final data = _buildLessonData(
      media: [
        _lessonMediaItem(
          id: 'media-audio-1',
          mediaType: 'audio',
          state: 'ready',
          resolvedUrl: 'https://cdn.test/lesson-audio.mp3',
        ),
      ],
    );

    await _pumpLessonPage(tester, data: data);
    await tester.pump();
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsNothing);

    expect(_lessonAudioMediaPlayerFinder(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lesson hides non-embedded trailing image rows', (tester) async {
    final data = _buildLessonData(
      media: [
        _lessonMediaItem(
          id: 'media-image-1',
          mediaType: 'image',
          state: 'ready',
          resolvedUrl: 'https://cdn.test/lesson-image.webp',
        ),
      ],
    );

    await _pumpLessonPage(tester, data: data);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AveliLessonImage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lesson hides non-embedded trailing document rows', (
    tester,
  ) async {
    final data = _buildLessonData(
      media: [
        _lessonMediaItem(
          id: 'media-document-1',
          mediaType: 'document',
          state: 'ready',
          resolvedUrl: 'https://cdn.test/lesson-document.pdf',
        ),
      ],
    );

    await _pumpLessonPage(tester, data: data);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Dokument'), findsNothing);
    expect(find.text('Ladda ner dokument'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lesson renders locked two-paragraph fixture content', (
    tester,
  ) async {
    final data = _buildLessonData(
      media: const [],
      contentDocument: _paragraphDocument(['Hello world', 'This is a lesson']),
    );

    await _pumpLessonPage(tester, data: data);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.textContaining('Hello world', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('This is a lesson', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('LektionsinnehÃ¥llet kunde inte renderas.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lesson renders inline document tokens without trailing fallback duplication',
    (tester) async {
      final data = _buildLessonData(
        media: [
          _lessonMediaItem(
            id: 'media-document-1',
            mediaType: 'document',
            state: 'ready',
            resolvedUrl: 'https://cdn.test/lesson-document.pdf',
          ),
        ],
        contentDocument: _mediaDocument(
          mediaType: 'document',
          lessonMediaId: 'media-document-1',
          paragraphs: const ['Intro', 'Outro'],
        ),
      );

      await _pumpLessonPage(tester, data: data);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Intro', findRichText: true), findsOneWidget);
      expect(find.textContaining('Outro', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('Ladda ner dokument', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('asset-1', findRichText: true), findsNothing);
      expect(
        find.textContaining('media-document-1', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('!document(', findRichText: true),
        findsNothing,
      );
      expect(find.text('Dokument'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('lesson page blocks locked next navigation for learners', (
    tester,
  ) async {
    final nextUnlockAt = DateTime.now().toUtc().add(const Duration(days: 4));
    final data = _buildLessonData(
      media: const [],
      lessons: const [
        LessonSummary(id: 'lesson-1', lessonTitle: 'Lektion', position: 1),
        LessonSummary(id: 'lesson-2', lessonTitle: 'Lektion 2', position: 2),
      ],
    );

    await _pumpLessonPage(
      tester,
      data: data,
      courseState: _courseState(
        currentUnlockPosition: 1,
        nextUnlockAt: nextUnlockAt,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Låst'), findsOneWidget);

    await tester.tap(find.text('Låst'));
    await tester.pump();

    expect(
      find.text('Den här lektionen blir tillgänglig om 4 dagar'),
      findsOneWidget,
    );
  });
}
