import 'dart:typed_data';

import 'package:dio/dio.dart';
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
import 'package:aveli/domain/models/entry_state.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/application/studio_upload_queue.dart';
import 'package:aveli/features/studio/data/studio_models.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/presentation/course_editor_page.dart';
import 'package:aveli/features/studio/presentation/editor_test_bridge.dart'
    as editor_test_bridge;
import 'package:aveli/features/courses/presentation/lesson_page.dart';
import 'package:aveli/shared/utils/course_cover_contract.dart';
import 'package:aveli/shared/utils/resolved_media_contract.dart';

class _MockStudioRepository extends Mock implements StudioRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _V2TeacherStatus extends Fake implements StudioStatus {
  @override
  bool get isTeacher => true;

  @override
  bool get hasApplication => false;
}

class _FakeAuthController extends AuthController {
  _FakeAuthController() : super(_MockAuthRepository(), AuthHttpObserver()) {
    state = AuthState(
      profile: Profile(
        id: 'teacher-1',
        email: 'teacher@example.com',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      entryState: const EntryState(
        canEnterApp: true,
        onboardingState: EntryOnboardingState.completed,
        onboardingCompleted: true,
        membershipActive: true,
        needsOnboarding: false,
        needsPayment: false,
        role: 'teacher',
      ),
    );
  }

  @override
  Future<void> loadSession({bool hydrateProfile = true}) async {}
}

class _NoopUploadQueueNotifier extends UploadQueueNotifier {
  _NoopUploadQueueNotifier(super.repo);

  @override
  String enqueueUpload({
    required String courseId,
    required String lessonId,
    required Uint8List data,
    required String filename,
    String? displayName,
    required String contentType,
    required String mediaType,
  }) {
    return 'noop';
  }

  @override
  void cancelUpload(String id) {}

  @override
  void retryUpload(String id) {}

  @override
  void removeJob(String id) {}
}

const _course = CourseStudio(
  id: 'course-1',
  title: 'Tarot Basics',
  slug: 'tarot-basics',
  courseGroupId: 'course-group-1',
  groupPosition: 1,
  dripEnabled: false,
  dripIntervalDays: null,
  coverMediaId: null,
  cover: null,
  priceAmountCents: 1200,
);

const _courseCoverUrl = 'https://cdn.test/course-cover.webp';
const _courseWithCover = CourseStudio(
  id: 'course-1',
  title: 'Tarot Basics',
  slug: 'tarot-basics',
  courseGroupId: 'course-group-1',
  groupPosition: 1,
  dripEnabled: false,
  dripIntervalDays: null,
  coverMediaId: 'course-cover-1',
  cover: CourseCoverData(
    mediaId: 'course-cover-1',
    state: 'ready',
    resolvedUrl: _courseCoverUrl,
  ),
  priceAmountCents: 1200,
);

const _canonicalLessonMediaUrl = 'https://cdn.test/canonical-lesson-image.webp';
const _canonicalTrailingDocumentUrl =
    'https://cdn.test/canonical-lesson-document.pdf';
const _editorTransientMediaPreviewUrl =
    'https://cdn.test/editor-transient-preview.webp';

const _lesson = LessonStudio(
  id: 'lesson-1',
  courseId: 'course-1',
  lessonTitle: 'Valkommen',
  position: 1,
);

const _secondLesson = LessonStudio(
  id: 'lesson-2',
  courseId: 'course-1',
  lessonTitle: 'Fortsattning',
  position: 2,
);

StudioLessonContentRead _contentRead({
  required String lessonId,
  required String contentMarkdown,
  required String etag,
  List<StudioLessonContentMediaItem> media =
      const <StudioLessonContentMediaItem>[],
}) {
  return StudioLessonContentRead(
    lessonId: lessonId,
    contentMarkdown: contentMarkdown,
    media: media,
    etag: etag,
  );
}

StudioLessonMediaItem _placementImage(String lessonMediaId) {
  return StudioLessonMediaItem(
    lessonMediaId: lessonMediaId,
    lessonId: 'lesson-1',
    position: 1,
    mediaType: 'image',
    state: 'ready',
    previewReady: true,
    mediaAssetId: 'asset-$lessonMediaId',
    media: ResolvedMediaData(
      mediaId: 'asset-$lessonMediaId',
      state: 'ready',
      resolvedUrl: _canonicalLessonMediaUrl,
    ),
  );
}

StudioLessonMediaItem _placementDocument(String lessonMediaId) {
  return StudioLessonMediaItem(
    lessonMediaId: lessonMediaId,
    lessonId: 'lesson-1',
    position: 2,
    mediaType: 'document',
    state: 'ready',
    previewReady: true,
    mediaAssetId: 'asset-$lessonMediaId',
    media: ResolvedMediaData(
      mediaId: 'asset-$lessonMediaId',
      state: 'ready',
      resolvedUrl: _canonicalTrailingDocumentUrl,
    ),
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

void _stubBaseStudioData(
  _MockStudioRepository repo, {
  CourseStudio course = _course,
  List<LessonStudio> lessons = const [_lesson],
  Future<StudioLessonContentRead> Function(String lessonId)? readContent,
}) {
  when(() => repo.fetchStatus()).thenAnswer((_) async => _V2TeacherStatus());
  when(() => repo.myCourses()).thenAnswer((_) async => [course]);
  when(() => repo.fetchCourseMeta('course-1')).thenAnswer((_) async => course);
  when(
    () => repo.listCourseLessons('course-1'),
  ).thenAnswer((_) async => lessons);
  when(
    () => repo.listLessonMedia(any()),
  ).thenAnswer((_) async => const <StudioLessonMediaItem>[]);
  when(
    () => repo.fetchLessonMediaPlacements(any()),
  ).thenAnswer((_) async => const <StudioLessonMediaItem>[]);
  when(
    () => repo.fetchLessonMediaPreviews(any()),
  ).thenAnswer((_) async => StudioLessonMediaPreviewBatch(items: const []));
  when(() => repo.readLessonContent(any())).thenAnswer((invocation) {
    final lessonId = invocation.positionalArguments.first as String;
    return readContent?.call(lessonId) ??
        Future.value(
          _contentRead(
            lessonId: lessonId,
            contentMarkdown: lessonId == 'lesson-2'
                ? 'Second persisted content'
                : 'Persisted content',
            etag: lessonId == 'lesson-2' ? '"content-2-v1"' : '"content-v1"',
          ),
        );
  });
  when(
    () => repo.updateLessonStructure(
      any(),
      lessonTitle: any(named: 'lessonTitle'),
      position: any(named: 'position'),
    ),
  ).thenAnswer((invocation) async {
    final lessonId = invocation.positionalArguments.first as String;
    return LessonStudio(
      id: lessonId,
      courseId: 'course-1',
      lessonTitle: invocation.namedArguments[#lessonTitle] as String,
      position: invocation.namedArguments[#position] as int,
    );
  });
}

Future<void> _pumpCourseEditor(
  WidgetTester tester, {
  required _MockStudioRepository repo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://localhost:8080',
            subscriptionsEnabled: false,
          ),
        ),
        authControllerProvider.overrideWith((ref) => _FakeAuthController()),
        studioRepositoryProvider.overrideWithValue(repo),
        studioUploadQueueProvider.overrideWith(
          (ref) => _NoopUploadQueueNotifier(repo),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          quill.FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('sv')],
        home: CourseEditorScreen(studioRepository: repo),
      ),
    ),
  );
}

Future<void> _pumpUntilDocumentContains(
  WidgetTester tester,
  String expected,
) async {
  for (var i = 0; i < 80; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (editor_test_bridge.getDocument()?.contains(expected) ?? false) {
      return;
    }
  }
  fail('Editor document never contained "$expected"');
}

Future<void> _pumpUntilTextFound(WidgetTester tester, String expected) async {
  final finder = find.text(expected);
  await _pumpUntilFinderFound(tester, finder);
}

Future<void> _pumpUntilFinderFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 80; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsOneWidget);
}

void _insertAtDocumentEnd(String text) {
  final document = editor_test_bridge.getDocument();
  expect(document, isNotNull);
  final offset = document!.isEmpty ? 0 : document.length - 1;
  editor_test_bridge.setCursor(offset);
  editor_test_bridge.insertText(text);
}

void _selectWholeDocumentForDeletion() {
  final document = editor_test_bridge.getDocument();
  expect(document, isNotNull);
  final end = document!.isEmpty ? 0 : document.length - 1;
  editor_test_bridge.setSelection(0, end);
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  testWidgets(
    'editor hydrates from content endpoint and saves with read ETag',
    (tester) async {
      final repo = _MockStudioRepository();
      _stubBaseStudioData(repo);
      when(
        () => repo.updateLessonContent(
          'lesson-1',
          contentMarkdown: any(named: 'contentMarkdown'),
          ifMatch: any(named: 'ifMatch'),
        ),
      ).thenAnswer((invocation) async {
        return StudioLessonContentWriteResult(
          lessonId: 'lesson-1',
          contentMarkdown:
              invocation.namedArguments[#contentMarkdown] as String,
          etag: '"content-v2"',
        );
      });

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilDocumentContains(tester, 'Persisted content');

      verify(() => repo.readLessonContent('lesson-1')).called(2);
      _insertAtDocumentEnd(' updated');
      await tester.pump();

      final saveButton = find.text('Spara lektionsinnehåll');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final contentCapture = verify(
        () => repo.updateLessonContent(
          'lesson-1',
          contentMarkdown: captureAny(named: 'contentMarkdown'),
          ifMatch: '"content-v1"',
        ),
      )..called(1);
      expect(contentCapture.captured.single as String, contains('updated'));
      verify(
        () => repo.updateLessonStructure(
          'lesson-1',
          lessonTitle: any(named: 'lessonTitle'),
          position: any(named: 'position'),
        ),
      ).called(1);
    },
  );

  testWidgets(
    'selected lesson media list is reconstructed from canonical placements',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const imageId = 'lesson-media-image-1';
      const documentId = 'lesson-media-document-1';
      final repo = _MockStudioRepository();
      _stubBaseStudioData(
        repo,
        readContent: (lessonId) async => _contentRead(
          lessonId: lessonId,
          contentMarkdown: 'Persisted content with canonical media',
          media: const [
            StudioLessonContentMediaItem(
              lessonMediaId: documentId,
              position: 2,
              mediaType: 'document',
              state: 'ready',
              mediaAssetId: 'asset-$documentId',
            ),
            StudioLessonContentMediaItem(
              lessonMediaId: imageId,
              position: 1,
              mediaType: 'image',
              state: 'ready',
              mediaAssetId: 'asset-$imageId',
            ),
          ],
          etag: '"content-v1"',
        ),
      );
      when(() => repo.fetchLessonMediaPlacements(any())).thenAnswer((
        invocation,
      ) async {
        final ids = List<String>.from(
          invocation.positionalArguments.single as List,
        );
        final placements = [
          for (final id in ids)
            id == documentId ? _placementDocument(id) : _placementImage(id),
        ];
        placements.sort((a, b) => a.position.compareTo(b.position));
        return placements;
      });

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilDocumentContains(
        tester,
        'Persisted content with canonical media',
      );
      await _pumpUntilFinderFound(tester, find.text('media_$imageId'));
      await _pumpUntilFinderFound(tester, find.text('media_$documentId'));

      expect(
        tester.getTopLeft(find.text('media_$imageId')).dy,
        lessThan(tester.getTopLeft(find.text('media_$documentId')).dy),
      );
      final placementRead = verify(
        () => repo.fetchLessonMediaPlacements(captureAny()),
      )..called(1);
      expect(placementRead.captured.single, [documentId, imageId]);
      verifyNever(() => repo.listLessonMedia(any()));
    },
  );

  testWidgets('preview reads persisted canonical truth and stays read-only', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const embeddedImageId = 'lesson-media-image-1';
    const trailingDocumentId = 'lesson-media-document-1';
    final repo = _MockStudioRepository();
    _stubBaseStudioData(
      repo,
      course: _courseWithCover,
      readContent: (lessonId) async => _contentRead(
        lessonId: lessonId,
        contentMarkdown:
            'Persisted canonical text\n\n!image($embeddedImageId)\n',
        media: const [
          StudioLessonContentMediaItem(
            lessonMediaId: embeddedImageId,
            position: 1,
            mediaType: 'image',
            state: 'ready',
            mediaAssetId: 'asset-$embeddedImageId',
          ),
          StudioLessonContentMediaItem(
            lessonMediaId: trailingDocumentId,
            position: 2,
            mediaType: 'document',
            state: 'ready',
            mediaAssetId: 'asset-$trailingDocumentId',
          ),
        ],
        etag: '"content-v1"',
      ),
    );
    when(() => repo.fetchLessonMediaPlacements(any())).thenAnswer((
      invocation,
    ) async {
      final ids = List<String>.from(
        invocation.positionalArguments.single as List,
      );
      return [
        for (final id in ids)
          id == trailingDocumentId
              ? _placementDocument(id)
              : _placementImage(id),
      ];
    });
    when(() => repo.fetchLessonMediaPreviews(any())).thenAnswer((
      invocation,
    ) async {
      final ids = List<String>.from(
        invocation.positionalArguments.single as List,
      );
      return StudioLessonMediaPreviewBatch(
        items: [
          for (final id in ids)
            StudioLessonMediaPreviewItem(
              lessonMediaId: id,
              mediaType: 'image',
              authoritativeEditorReady: true,
              previewUrl: _editorTransientMediaPreviewUrl,
              fileName: 'canonical-lesson-image.webp',
            ),
        ],
      );
    });

    await _pumpCourseEditor(tester, repo: repo);
    await _pumpUntilDocumentContains(tester, 'Persisted canonical text');
    await tester.pump();

    expect(_networkImageFinder(_courseCoverUrl), findsOneWidget);
    expect(
      _networkImageFinder(_canonicalLessonMediaUrl),
      findsAtLeastNWidgets(1),
    );

    clearInteractions(repo);
    _insertAtDocumentEnd(' unsaved draft');
    await tester.pump();
    expect(editor_test_bridge.getDocument(), contains('unsaved draft'));

    final previewChip = find.byKey(
      const ValueKey<String>('lesson_preview_mode_chip'),
    );
    await _pumpUntilFinderFound(tester, previewChip);
    await tester.tap(previewChip);

    await _pumpUntilFinderFound(tester, find.byType(LessonPageRenderer));
    await _pumpUntilFinderFound(
      tester,
      find.text(
        'Skrivskyddad förhandsgranskning med samma renderingspipeline som elevvyn.',
      ),
    );
    await _pumpUntilFinderFound(
      tester,
      find.textContaining('Persisted canonical text', findRichText: true),
    );
    await _pumpUntilFinderFound(tester, find.text('Dokument'));
    await _pumpUntilFinderFound(tester, find.text('Ladda ner dokument'));

    expect(
      find.textContaining('unsaved draft', findRichText: true),
      findsNothing,
    );
    expect(
      _networkImageFinder(_canonicalLessonMediaUrl),
      findsAtLeastNWidgets(2),
    );
    expect(_networkImageFinder(_courseCoverUrl), findsAtLeastNWidgets(2));

    final placementRead = verify(
      () => repo.fetchLessonMediaPlacements(captureAny()),
    )..called(1);
    expect(placementRead.captured.single, [
      embeddedImageId,
      trailingDocumentId,
    ]);
    verify(() => repo.readLessonContent('lesson-1')).called(1);
    verify(() => repo.fetchCourseMeta('course-1')).called(1);
    verifyNever(() => repo.fetchLessonMediaPreviews(any()));
    verifyNever(
      () => repo.updateLessonContent(
        any(),
        contentMarkdown: any(named: 'contentMarkdown'),
        ifMatch: any(named: 'ifMatch'),
      ),
    );
    verifyNever(
      () => repo.updateLessonStructure(
        any(),
        lessonTitle: any(named: 'lessonTitle'),
        position: any(named: 'position'),
      ),
    );
  });

  testWidgets('failed content read keeps editor in fail-closed boot shell', (
    tester,
  ) async {
    final repo = _MockStudioRepository();
    _stubBaseStudioData(
      repo,
      readContent: (_) => Future<StudioLessonContentRead>.error(
        DioException(
          requestOptions: RequestOptions(
            path: '/studio/lessons/lesson-1/content',
          ),
          response: Response<void>(
            requestOptions: RequestOptions(
              path: '/studio/lessons/lesson-1/content',
            ),
            statusCode: 500,
          ),
        ),
      ),
    );
    when(
      () => repo.updateLessonContent(
        'lesson-1',
        contentMarkdown: any(named: 'contentMarkdown'),
        ifMatch: any(named: 'ifMatch'),
      ),
    ).thenAnswer(
      (_) async => const StudioLessonContentWriteResult(
        lessonId: 'lesson-1',
        contentMarkdown: '',
        etag: '"content-v2"',
      ),
    );

    await _pumpCourseEditor(tester, repo: repo);
    await _pumpUntilTextFound(tester, 'Lektionsinnehållet kunde inte laddas');

    expect(find.text('Lektionsinnehållet kunde inte laddas'), findsOneWidget);
    expect(find.text('Ladda om innehåll'), findsOneWidget);
    final resetButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Återställ'),
    );
    expect(resetButton.onPressed, isNull);
    _insertAtDocumentEnd(' should not edit');
    await tester.pump();
    verifyNever(
      () => repo.updateLessonContent(
        'lesson-1',
        contentMarkdown: any(named: 'contentMarkdown'),
        ifMatch: any(named: 'ifMatch'),
      ),
    );
  });

  testWidgets('missing content ETag blocks editing and saving', (tester) async {
    final repo = _MockStudioRepository();
    _stubBaseStudioData(
      repo,
      readContent: (lessonId) async => _contentRead(
        lessonId: lessonId,
        contentMarkdown: 'Persisted without token',
        etag: ' ',
      ),
    );
    when(
      () => repo.updateLessonContent(
        'lesson-1',
        contentMarkdown: any(named: 'contentMarkdown'),
        ifMatch: any(named: 'ifMatch'),
      ),
    ).thenAnswer(
      (_) async => const StudioLessonContentWriteResult(
        lessonId: 'lesson-1',
        contentMarkdown: 'should not write',
        etag: '"content-v2"',
      ),
    );

    await _pumpCourseEditor(tester, repo: repo);
    await _pumpUntilTextFound(tester, 'Lektionsinnehållet kunde inte laddas');

    _insertAtDocumentEnd(' forbidden edit');
    await tester.pump();

    verify(() => repo.readLessonContent('lesson-1')).called(2);
    verifyNever(
      () => repo.updateLessonContent(
        'lesson-1',
        contentMarkdown: any(named: 'contentMarkdown'),
        ifMatch: any(named: 'ifMatch'),
      ),
    );
    verifyNever(
      () => repo.updateLessonStructure(
        'lesson-1',
        lessonTitle: any(named: 'lessonTitle'),
        position: any(named: 'position'),
      ),
    );
  });

  testWidgets('stale content save fails closed without structure overwrite', (
    tester,
  ) async {
    final repo = _MockStudioRepository();
    _stubBaseStudioData(repo);
    when(
      () => repo.updateLessonContent(
        'lesson-1',
        contentMarkdown: any(named: 'contentMarkdown'),
        ifMatch: any(named: 'ifMatch'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(
          path: '/studio/lessons/lesson-1/content',
        ),
        response: Response<void>(
          requestOptions: RequestOptions(
            path: '/studio/lessons/lesson-1/content',
          ),
          statusCode: 412,
        ),
      ),
    );

    await _pumpCourseEditor(tester, repo: repo);
    await _pumpUntilDocumentContains(tester, 'Persisted content');
    _insertAtDocumentEnd(' stale edit');
    await tester.pump();

    final saveButton = find.text('Spara lektionsinnehåll');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    verify(
      () => repo.updateLessonContent(
        'lesson-1',
        contentMarkdown: any(named: 'contentMarkdown'),
        ifMatch: '"content-v1"',
      ),
    ).called(1);
    verifyNever(
      () => repo.updateLessonStructure(
        'lesson-1',
        lessonTitle: any(named: 'lessonTitle'),
        position: any(named: 'position'),
      ),
    );
    expect(find.text('Lektionsinnehållet kunde inte laddas'), findsOneWidget);
    expect(
      find.text(
        'Lektionsinnehållet har ändrats. Ladda om innehållet innan du sparar igen.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('intentional empty clear writes only after hydrated ETag', (
    tester,
  ) async {
    final repo = _MockStudioRepository();
    _stubBaseStudioData(repo);
    when(
      () => repo.updateLessonContent(
        'lesson-1',
        contentMarkdown: any(named: 'contentMarkdown'),
        ifMatch: any(named: 'ifMatch'),
      ),
    ).thenAnswer((invocation) async {
      return StudioLessonContentWriteResult(
        lessonId: 'lesson-1',
        contentMarkdown: invocation.namedArguments[#contentMarkdown] as String,
        etag: '"content-v2"',
      );
    });

    await _pumpCourseEditor(tester, repo: repo);
    await _pumpUntilDocumentContains(tester, 'Persisted content');
    _selectWholeDocumentForDeletion();
    await tester.pump();
    editor_test_bridge.deleteSelection();
    await tester.pump();

    final saveButton = find.text('Spara lektionsinnehåll');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final contentCapture = verify(
      () => repo.updateLessonContent(
        'lesson-1',
        contentMarkdown: captureAny(named: 'contentMarkdown'),
        ifMatch: '"content-v1"',
      ),
    )..called(1);
    expect(contentCapture.captured.single, '');
    verify(
      () => repo.updateLessonStructure(
        'lesson-1',
        lessonTitle: any(named: 'lessonTitle'),
        position: any(named: 'position'),
      ),
    ).called(1);
  });

  testWidgets('lesson switch loads selected lesson content without overwrite', (
    tester,
  ) async {
    final repo = _MockStudioRepository();
    _stubBaseStudioData(repo, lessons: const [_lesson, _secondLesson]);

    await _pumpCourseEditor(tester, repo: repo);
    await _pumpUntilDocumentContains(tester, 'Persisted content');

    await tester.ensureVisible(find.text('Fortsattning'));
    await tester.tap(find.text('Fortsattning'));
    await _pumpUntilDocumentContains(tester, 'Second persisted content');

    final document = editor_test_bridge.getDocument();
    expect(document, contains('Second persisted content'));
    expect(document, isNot(contains('Persisted content\n')));
    verify(() => repo.readLessonContent('lesson-1')).called(2);
    verify(() => repo.readLessonContent('lesson-2')).called(2);
    verifyNever(
      () => repo.updateLessonContent(
        any(),
        contentMarkdown: any(named: 'contentMarkdown'),
        ifMatch: any(named: 'ifMatch'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });
}
