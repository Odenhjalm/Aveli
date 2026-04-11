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
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/application/studio_upload_queue.dart';
import 'package:aveli/features/studio/data/studio_models.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/presentation/course_editor_page.dart';
import 'package:aveli/features/studio/presentation/editor_test_bridge.dart'
    as editor_test_bridge;

class _MockStudioRepository extends Mock implements StudioRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _FakeAuthController extends AuthController {
  _FakeAuthController() : super(_MockAuthRepository(), AuthHttpObserver()) {
    state = AuthState(
      profile: Profile(
        id: 'teacher-1',
        email: 'teacher@example.com',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
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
  step: 'foundation',
  dripEnabled: false,
  dripIntervalDays: null,
  coverMediaId: null,
  cover: null,
  priceAmountCents: 1200,
);

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
}) {
  return StudioLessonContentRead(
    lessonId: lessonId,
    contentMarkdown: contentMarkdown,
    media: const [],
    etag: etag,
  );
}

void _stubBaseStudioData(
  _MockStudioRepository repo, {
  List<LessonStudio> lessons = const [_lesson],
  Future<StudioLessonContentRead> Function(String lessonId)? readContent,
}) {
  when(() => repo.fetchStatus()).thenAnswer(
    (_) async => const StudioStatus(
      isTeacher: true,
      verifiedCertificates: 1,
      hasApplication: false,
    ),
  );
  when(() => repo.myCourses()).thenAnswer((_) async => const [_course]);
  when(() => repo.fetchCourseMeta('course-1')).thenAnswer((_) async => _course);
  when(
    () => repo.listCourseLessons('course-1'),
  ).thenAnswer((_) async => lessons);
  when(
    () => repo.listLessonMedia(any()),
  ).thenAnswer((_) async => const <StudioLessonMediaItem>[]);
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
            stripePublishableKey: 'pk_test_stub',
            stripeMerchantDisplayName: 'Test Merchant',
            subscriptionsEnabled: false,
          ),
        ),
        authControllerProvider.overrideWith((ref) => _FakeAuthController()),
        studioRepositoryProvider.overrideWithValue(repo),
        studioStatusProvider.overrideWith(
          (ref) async => const StudioStatus(
            isTeacher: true,
            verifiedCertificates: 1,
            hasApplication: false,
          ),
        ),
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

      verify(() => repo.readLessonContent('lesson-1')).called(1);
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

    verify(() => repo.readLessonContent('lesson-1')).called(1);
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
    verify(() => repo.readLessonContent('lesson-1')).called(1);
    verify(() => repo.readLessonContent('lesson-2')).called(1);
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
