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

const _familyLeadCourse = CourseStudio(
  id: 'course-2',
  title: 'Tarot Foundations',
  slug: 'tarot-foundations',
  courseGroupId: 'course-group-1',
  groupPosition: 0,
  dripEnabled: false,
  dripIntervalDays: null,
  coverMediaId: null,
  cover: null,
  priceAmountCents: 1200,
);

const _familyLeadCourseShifted = CourseStudio(
  id: 'course-2',
  title: 'Tarot Foundations',
  slug: 'tarot-foundations',
  courseGroupId: 'course-group-1',
  groupPosition: 1,
  dripEnabled: false,
  dripIntervalDays: null,
  coverMediaId: null,
  cover: null,
  priceAmountCents: 1200,
);

const _otherFamilyCourse = CourseStudio(
  id: 'course-3',
  title: 'Breathwork Flow',
  slug: 'breathwork-flow',
  courseGroupId: 'course-group-2',
  groupPosition: 0,
  dripEnabled: false,
  dripIntervalDays: null,
  coverMediaId: null,
  cover: null,
  priceAmountCents: 2100,
);

const _untitledFamilyLeadCourse = CourseStudio(
  id: 'course-untitled-intro',
  title: '',
  slug: 'untitled-intro',
  courseGroupId: 'course-group-untitled',
  groupPosition: 0,
  dripEnabled: false,
  dripIntervalDays: null,
  coverMediaId: null,
  cover: null,
  priceAmountCents: null,
);

const _untitledFamilyStepCourse = CourseStudio(
  id: 'course-untitled-step',
  title: '',
  slug: 'untitled-step',
  courseGroupId: 'course-group-untitled',
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

const _createdCourse = CourseStudio(
  id: 'course-created',
  title: 'Backendutkast',
  slug: 'backend-draft',
  courseGroupId: 'course-group-created',
  groupPosition: 0,
  dripEnabled: false,
  dripIntervalDays: null,
  coverMediaId: null,
  cover: null,
  priceAmountCents: 49000,
);

const _createdCourseInCurrentFamily = CourseStudio(
  id: 'course-created',
  title: 'Backendutkast',
  slug: 'backend-draft',
  courseGroupId: 'course-group-1',
  groupPosition: 2,
  dripEnabled: false,
  dripIntervalDays: null,
  coverMediaId: null,
  cover: null,
  priceAmountCents: 49000,
);

const _reorderedCourse = CourseStudio(
  id: 'course-1',
  title: 'Tarot Basics',
  slug: 'tarot-basics',
  courseGroupId: 'course-group-1',
  groupPosition: 0,
  dripEnabled: false,
  dripIntervalDays: null,
  coverMediaId: null,
  cover: null,
  priceAmountCents: 1200,
);

const _movedCourse = CourseStudio(
  id: 'course-1',
  title: 'Tarot Basics',
  slug: 'tarot-basics',
  courseGroupId: 'course-group-2',
  groupPosition: 1,
  dripEnabled: false,
  dripIntervalDays: null,
  coverMediaId: null,
  cover: null,
  priceAmountCents: 1200,
);

const _publishedCourse = CourseStudio(
  id: 'course-1',
  title: 'Backendpublicerad',
  slug: 'backend-publicerad',
  courseGroupId: 'course-group-1',
  groupPosition: 1,
  dripEnabled: false,
  dripIntervalDays: null,
  coverMediaId: null,
  cover: null,
  priceAmountCents: 1200,
);

CourseFamilyStudio _family({
  required String id,
  required String name,
  required int courseCount,
}) {
  return CourseFamilyStudio(
    id: id,
    name: name,
    teacherId: 'teacher-1',
    createdAt: DateTime.utc(2026, 1, 1),
    courseCount: courseCount,
  );
}

List<CourseFamilyStudio> _derivedCourseFamilies(List<CourseStudio> courses) {
  final grouped = <String, List<CourseStudio>>{};
  final order = <String>[];
  for (final course in courses) {
    final courseGroupId = course.courseGroupId.trim();
    if (courseGroupId.isEmpty) continue;
    final bucket = grouped.putIfAbsent(courseGroupId, () {
      order.add(courseGroupId);
      return <CourseStudio>[];
    });
    bucket.add(course);
  }
  return [
    for (final familyId in order)
      _family(
        id: familyId,
        name:
            ([...grouped[familyId]!]..sort((left, right) {
                  final positionCompare = left.groupPosition.compareTo(
                    right.groupPosition,
                  );
                  if (positionCompare != 0) {
                    return positionCompare;
                  }
                  return left.id.compareTo(right.id);
                }))
                .map((course) => course.title.trim())
                .firstWhere(
                  (title) => title.isNotEmpty,
                  orElse: () => 'Course Family',
                ),
        courseCount: grouped[familyId]!.length,
      ),
  ];
}

const _canonicalLessonMediaUrl = 'https://cdn.test/canonical-lesson-image.webp';
const _canonicalTrailingDocumentUrl =
    'https://cdn.test/canonical-lesson-document.pdf';

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

const _thirdLesson = LessonStudio(
  id: 'lesson-3',
  courseId: 'course-1',
  lessonTitle: 'Fördjupning',
  position: 3,
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

StudioLessonMediaItem _placementImage(
  String lessonMediaId, {
  int position = 1,
}) {
  return StudioLessonMediaItem(
    lessonMediaId: lessonMediaId,
    lessonId: 'lesson-1',
    position: position,
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

StudioLessonMediaItem _placementDocument(
  String lessonMediaId, {
  int position = 2,
}) {
  return StudioLessonMediaItem(
    lessonMediaId: lessonMediaId,
    lessonId: 'lesson-1',
    position: position,
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

Finder _networkImageFinder(String url) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is NetworkImage &&
        (widget.image as NetworkImage).url == url,
    description: 'Image.network($url)',
  );
}

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
    description: 'TextField(labelText: $label)',
  );
}

List<_StyledTextSegment> _previewStyledTextSegments(WidgetTester tester) {
  final segments = <_StyledTextSegment>[];
  final richTextFinder = find.descendant(
    of: find.byType(LearnerLessonContentRenderer),
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

void _stubBaseStudioData(
  _MockStudioRepository repo, {
  CourseStudio course = _course,
  List<CourseStudio>? courses,
  List<CourseFamilyStudio>? courseFamilies,
  List<LessonStudio> lessons = const [_lesson],
  Future<StudioLessonContentRead> Function(String lessonId)? readContent,
}) {
  final studioCourses = List<CourseStudio>.unmodifiable(courses ?? [course]);
  final studioCourseFamilies = List<CourseFamilyStudio>.unmodifiable(
    courseFamilies ?? _derivedCourseFamilies(studioCourses),
  );
  final coursesById = <String, CourseStudio>{
    for (final item in studioCourses) item.id: item,
  };
  when(() => repo.fetchStatus()).thenAnswer((_) async => _V2TeacherStatus());
  when(() => repo.myCourses()).thenAnswer((_) async => studioCourses);
  when(
    () => repo.myCourseFamilies(),
  ).thenAnswer((_) async => studioCourseFamilies);
  when(() => repo.fetchCourseMeta(any())).thenAnswer((invocation) async {
    final courseId = invocation.positionalArguments.first as String;
    final matched = coursesById[courseId];
    if (matched == null) {
      throw StateError('Unknown course: $courseId');
    }
    return matched;
  });
  when(() => repo.listCourseLessons(any())).thenAnswer((invocation) async {
    final courseId = invocation.positionalArguments.first as String;
    if (courseId == course.id) {
      return lessons;
    }
    return const <LessonStudio>[];
  });
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

Future<void> _openLessonPreview(WidgetTester tester) async {
  final previewChip = find.byKey(
    const ValueKey<String>('lesson_preview_mode_chip'),
  );
  await _pumpUntilFinderFound(tester, previewChip);
  await tester.tap(previewChip);
  await tester.pump();
}

Future<void> _closeLessonPreview(WidgetTester tester) async {
  final editChip = find.byKey(const ValueKey<String>('lesson_edit_mode_chip'));
  await _pumpUntilFinderFound(tester, editChip);
  await tester.tap(editChip);
  await tester.pump();
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(<String, Object?>{});
  });

  testWidgets('course create uses canonical backend response as editor state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _MockStudioRepository();
    final initialFamily = _family(
      id: 'course-group-created',
      name: 'Backend Family',
      courseCount: 0,
    );
    final populatedFamily = _family(
      id: 'course-group-created',
      name: 'Backend Family',
      courseCount: 1,
    );
    when(() => repo.fetchStatus()).thenAnswer((_) async => _V2TeacherStatus());
    var myCoursesCalls = 0;
    when(() => repo.myCourses()).thenAnswer((_) async {
      myCoursesCalls += 1;
      return myCoursesCalls == 1
          ? const <CourseStudio>[]
          : const <CourseStudio>[_createdCourse];
    });
    var myFamiliesCalls = 0;
    when(() => repo.myCourseFamilies()).thenAnswer((_) async {
      myFamiliesCalls += 1;
      return myFamiliesCalls == 1
          ? <CourseFamilyStudio>[initialFamily]
          : <CourseFamilyStudio>[populatedFamily];
    });
    when(
      () => repo.createCourse(
        title: any(named: 'title'),
        slug: any(named: 'slug'),
        courseGroupId: any(named: 'courseGroupId'),
        priceAmountCents: any(named: 'priceAmountCents'),
        dripEnabled: any(named: 'dripEnabled'),
        dripIntervalDays: any(named: 'dripIntervalDays'),
        coverMediaId: any(named: 'coverMediaId'),
      ),
    ).thenAnswer((_) async => _createdCourse);
    when(
      () => repo.fetchCourseMeta('course-created'),
    ).thenAnswer((_) async => _createdCourse);
    when(
      () => repo.listCourseLessons('course-created'),
    ).thenAnswer((_) async => const <LessonStudio>[]);

    await _pumpCourseEditor(tester, repo: repo);
    await _pumpUntilTextFound(tester, 'Skapa kurs');

    await tester.tap(find.text('Skapa kurs'));
    await tester.pumpAndSettle();
    expect(find.text('Skapa ny kurs'), findsOneWidget);

    final dialog = find.byType(AlertDialog);
    final dialogFields = find.descendant(
      of: dialog,
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogFields.at(0), 'Min kurs');
    await tester.enterText(dialogFields.at(1), 'min-kurs');
    await tester.enterText(dialogFields.at(2), '490');
    await tester.tap(find.text('Skapa kurs').last);
    await tester.pumpAndSettle();
    await _pumpUntilTextFound(tester, 'Backendutkast');

    final create = verify(
      () => repo.createCourse(
        title: 'Min kurs',
        slug: 'min-kurs',
        courseGroupId: captureAny(named: 'courseGroupId'),
        priceAmountCents: 49000,
        dripEnabled: false,
        dripIntervalDays: null,
        coverMediaId: null,
      ),
    );
    create.called(1);
    expect(create.captured.single as String, 'course-group-created');
    verify(() => repo.fetchCourseMeta('course-created')).called(1);
    verify(() => repo.listCourseLessons('course-created')).called(1);
  });

  testWidgets('course create failure does not fabricate a local draft', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _MockStudioRepository();
    when(() => repo.fetchStatus()).thenAnswer((_) async => _V2TeacherStatus());
    when(
      () => repo.myCourses(),
    ).thenAnswer((_) async => const <CourseStudio>[]);
    when(() => repo.myCourseFamilies()).thenAnswer(
      (_) async => <CourseFamilyStudio>[
        _family(id: 'course-group-1', name: 'Course Family', courseCount: 0),
      ],
    );
    when(
      () => repo.createCourse(
        title: any(named: 'title'),
        slug: any(named: 'slug'),
        courseGroupId: any(named: 'courseGroupId'),
        priceAmountCents: any(named: 'priceAmountCents'),
        dripEnabled: any(named: 'dripEnabled'),
        dripIntervalDays: any(named: 'dripIntervalDays'),
        coverMediaId: any(named: 'coverMediaId'),
      ),
    ).thenThrow(StateError('backend unavailable'));

    await _pumpCourseEditor(tester, repo: repo);
    await _pumpUntilTextFound(tester, 'Skapa kurs');

    await tester.tap(find.text('Skapa kurs'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Min kurs');
    await tester.enterText(find.byType(TextField).at(1), 'min-kurs');
    await tester.tap(find.text('Skapa kurs').last);
    await tester.pumpAndSettle();

    expect(find.text('Backendutkast'), findsNothing);
    expect(find.textContaining('Kunde inte skapa kurs'), findsOneWidget);
    verifyNever(() => repo.fetchCourseMeta(any()));
    verifyNever(() => repo.listCourseLessons(any()));
  });

  testWidgets(
    'course create dialog exposes drip controls and persists enabled drip',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockStudioRepository();
      final createdDripCourse = _createdCourse.copyWith(
        dripEnabled: true,
        dripIntervalDays: 7,
      );
      final initialFamily = _family(
        id: 'course-group-created',
        name: 'Backend Family',
        courseCount: 0,
      );
      final populatedFamily = _family(
        id: 'course-group-created',
        name: 'Backend Family',
        courseCount: 1,
      );
      when(
        () => repo.fetchStatus(),
      ).thenAnswer((_) async => _V2TeacherStatus());
      var myCoursesCalls = 0;
      when(() => repo.myCourses()).thenAnswer((_) async {
        myCoursesCalls += 1;
        return myCoursesCalls == 1
            ? const <CourseStudio>[]
            : <CourseStudio>[createdDripCourse];
      });
      var myFamiliesCalls = 0;
      when(() => repo.myCourseFamilies()).thenAnswer((_) async {
        myFamiliesCalls += 1;
        return myFamiliesCalls == 1
            ? <CourseFamilyStudio>[initialFamily]
            : <CourseFamilyStudio>[populatedFamily];
      });
      when(
        () => repo.createCourse(
          title: any(named: 'title'),
          slug: any(named: 'slug'),
          courseGroupId: any(named: 'courseGroupId'),
          priceAmountCents: any(named: 'priceAmountCents'),
          dripEnabled: any(named: 'dripEnabled'),
          dripIntervalDays: any(named: 'dripIntervalDays'),
          coverMediaId: any(named: 'coverMediaId'),
        ),
      ).thenAnswer((_) async => createdDripCourse);
      when(
        () => repo.fetchCourseMeta('course-created'),
      ).thenAnswer((_) async => createdDripCourse);
      when(
        () => repo.listCourseLessons('course-created'),
      ).thenAnswer((_) async => const <LessonStudio>[]);

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilTextFound(tester, 'Skapa kurs');

      await tester.tap(find.text('Skapa kurs'));
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: _textFieldWithLabel('Antal dagar mellan lektioner'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(
            'Ändringar påverkar alla nuvarande deltagare i kursen.',
          ),
        ),
        findsNothing,
      );

      final dripToggle = find.descendant(
        of: dialog,
        matching: find.widgetWithText(
          SwitchListTile,
          'Aktivera lektionssläpp (drip)',
        ),
      );
      await tester.tap(dripToggle);
      await tester.pumpAndSettle();

      final dripIntervalField = find.descendant(
        of: dialog,
        matching: _textFieldWithLabel('Antal dagar mellan lektioner'),
      );
      expect(dripIntervalField, findsOneWidget);
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(
            'Ändringar påverkar alla nuvarande deltagare i kursen.',
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(dripToggle);
      await tester.pumpAndSettle();
      expect(dripIntervalField, findsNothing);

      await tester.tap(dripToggle);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: dialog, matching: _textFieldWithLabel('Titel')),
        'Min kurs',
      );
      await tester.enterText(
        find.descendant(
          of: dialog,
          matching: _textFieldWithLabel('Kursadress'),
        ),
        'min-kurs',
      );

      await tester.tap(find.text('Skapa kurs').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Antal dagar måste vara ett heltal större än 0.'),
        findsOneWidget,
      );
      verifyNever(
        () => repo.createCourse(
          title: any(named: 'title'),
          slug: any(named: 'slug'),
          courseGroupId: any(named: 'courseGroupId'),
          priceAmountCents: any(named: 'priceAmountCents'),
          dripEnabled: any(named: 'dripEnabled'),
          dripIntervalDays: any(named: 'dripIntervalDays'),
          coverMediaId: any(named: 'coverMediaId'),
        ),
      );

      final visibleDripIntervalField = find.descendant(
        of: dialog,
        matching: _textFieldWithLabel('Antal dagar mellan lektioner'),
      );
      await tester.enterText(visibleDripIntervalField, '0');
      await tester.tap(find.text('Skapa kurs').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Antal dagar måste vara ett heltal större än 0.'),
        findsOneWidget,
      );

      await tester.enterText(visibleDripIntervalField, '7');
      await tester.tap(find.text('Skapa kurs').last);
      await tester.pumpAndSettle();
      await _pumpUntilTextFound(tester, 'Backendutkast');

      verify(
        () => repo.createCourse(
          title: 'Min kurs',
          slug: 'min-kurs',
          courseGroupId: 'course-group-created',
          priceAmountCents: null,
          dripEnabled: true,
          dripIntervalDays: 7,
          coverMediaId: null,
        ),
      ).called(1);
    },
  );

  testWidgets('course family can be created before any course exists', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _MockStudioRepository();
    when(() => repo.fetchStatus()).thenAnswer((_) async => _V2TeacherStatus());
    when(
      () => repo.myCourses(),
    ).thenAnswer((_) async => const <CourseStudio>[]);
    var myCourseFamiliesCalls = 0;
    when(() => repo.myCourseFamilies()).thenAnswer((_) async {
      myCourseFamiliesCalls += 1;
      return myCourseFamiliesCalls == 1
          ? const <CourseFamilyStudio>[]
          : <CourseFamilyStudio>[
              _family(
                id: 'course-group-created',
                name: 'My Family',
                courseCount: 0,
              ),
            ];
    });
    when(() => repo.createCourseFamily(name: any(named: 'name'))).thenAnswer(
      (_) async => _family(
        id: 'course-group-created',
        name: 'My Family',
        courseCount: 0,
      ),
    );

    await _pumpCourseEditor(tester, repo: repo);
    await _pumpUntilTextFound(tester, 'Skapa familj');

    await tester.tap(find.text('Skapa familj'));
    await tester.pumpAndSettle();
    expect(find.text('Skapa kursfamilj'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'My Family');
    await tester.tap(find.text('Skapa familj').last);
    await tester.pumpAndSettle();
    await _pumpUntilTextFound(tester, 'Current Family: My Family');

    verify(() => repo.createCourseFamily(name: 'My Family')).called(1);
    expect(find.textContaining('course_group_id'), findsNothing);
  });

  testWidgets(
    'course family card is topmost and never renders raw course_group_id text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockStudioRepository();
      _stubBaseStudioData(
        repo,
        course: _course,
        courses: const <CourseStudio>[
          _course,
          _familyLeadCourse,
          _otherFamilyCourse,
        ],
      );

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilTextFound(tester, 'Current Family: Tarot Foundations');
      await tester.pumpAndSettle();

      final familySectionTop = tester.getTopLeft(find.text('Course Family')).dy;
      final courseSectionTop = tester.getTopLeft(find.text('Välj kurs')).dy;

      expect(familySectionTop, lessThan(courseSectionTop));
      expect(find.text('Stage: Step 1'), findsOneWidget);
      expect(find.text('Introduction · Tarot Foundations'), findsOneWidget);
      expect(find.text('Step 1 · Tarot Basics'), findsOneWidget);
      expect(find.textContaining('course_group_id'), findsNothing);
      expect(find.textContaining('course-group-1'), findsNothing);
      expect(find.textContaining('course-group-2'), findsNothing);
    },
  );

  testWidgets(
    'course family falls back to default name when no course title exists',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockStudioRepository();
      _stubBaseStudioData(
        repo,
        course: _untitledFamilyStepCourse,
        courses: const <CourseStudio>[
          _untitledFamilyStepCourse,
          _untitledFamilyLeadCourse,
        ],
        lessons: const <LessonStudio>[],
      );

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilTextFound(tester, 'Current Family: Course Family');
      await tester.pumpAndSettle();

      expect(find.text('Stage: Step 1'), findsOneWidget);
      expect(find.text('Introduction · Untitled course'), findsOneWidget);
      expect(find.text('Step 1 · Untitled course'), findsOneWidget);
      expect(find.textContaining('course-group-untitled'), findsNothing);
    },
  );

  testWidgets(
    'course create appends into the selected family without raw position input',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockStudioRepository();
      var myCoursesCalls = 0;
      when(
        () => repo.fetchStatus(),
      ).thenAnswer((_) async => _V2TeacherStatus());
      when(() => repo.myCourses()).thenAnswer((_) async {
        myCoursesCalls += 1;
        return myCoursesCalls == 1
            ? const <CourseStudio>[
                _course,
                _familyLeadCourse,
                _otherFamilyCourse,
              ]
            : const <CourseStudio>[
                _course,
                _familyLeadCourse,
                _otherFamilyCourse,
                _createdCourseInCurrentFamily,
              ];
      });
      when(() => repo.myCourseFamilies()).thenAnswer((_) async {
        return <CourseFamilyStudio>[
          _family(
            id: 'course-group-1',
            name: 'Tarot Foundations',
            courseCount: 3,
          ),
          _family(
            id: 'course-group-2',
            name: 'Breathwork Flow',
            courseCount: 1,
          ),
        ];
      });
      when(
        () => repo.createCourse(
          title: any(named: 'title'),
          slug: any(named: 'slug'),
          courseGroupId: any(named: 'courseGroupId'),
          priceAmountCents: any(named: 'priceAmountCents'),
          dripEnabled: any(named: 'dripEnabled'),
          dripIntervalDays: any(named: 'dripIntervalDays'),
          coverMediaId: any(named: 'coverMediaId'),
        ),
      ).thenAnswer((_) async => _createdCourseInCurrentFamily);
      when(
        () => repo.fetchCourseMeta('course-created'),
      ).thenAnswer((_) async => _createdCourseInCurrentFamily);
      when(
        () => repo.listCourseLessons('course-1'),
      ).thenAnswer((_) async => const <LessonStudio>[_lesson]);
      when(
        () => repo.listCourseLessons('course-created'),
      ).thenAnswer((_) async => const <LessonStudio>[]);
      when(
        () => repo.fetchCourseMeta('course-1'),
      ).thenAnswer((_) async => _course);
      when(() => repo.readLessonContent(any())).thenAnswer((invocation) async {
        final lessonId = invocation.positionalArguments.first as String;
        return _contentRead(
          lessonId: lessonId,
          contentMarkdown: 'Persisted content',
          etag: '"content-v1"',
        );
      });
      when(
        () => repo.fetchLessonMediaPlacements(any()),
      ).thenAnswer((_) async => const <StudioLessonMediaItem>[]);
      when(
        () => repo.fetchLessonMediaPreviews(any()),
      ).thenAnswer((_) async => StudioLessonMediaPreviewBatch(items: const []));

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilTextFound(tester, 'Course Family');

      await tester.tap(find.text('Skapa kurs'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      final dialogFields = find.descendant(
        of: dialog,
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogFields.at(0), 'Min kurs');
      await tester.enterText(dialogFields.at(1), 'min-kurs');
      await tester.tap(find.text('Skapa kurs').last);
      await tester.pumpAndSettle();
      await _pumpUntilTextFound(tester, 'Backendutkast');

      verify(
        () => repo.createCourse(
          title: 'Min kurs',
          slug: 'min-kurs',
          courseGroupId: 'course-group-1',
          priceAmountCents: null,
          dripEnabled: false,
          dripIntervalDays: null,
          coverMediaId: null,
        ),
      ).called(1);
      verify(() => repo.fetchCourseMeta('course-created')).called(1);
      verify(() => repo.listCourseLessons('course-created')).called(1);
    },
  );

  testWidgets(
    'course family reorder uses canonical endpoint and refreshes editor state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockStudioRepository();
      var reordered = false;
      when(
        () => repo.fetchStatus(),
      ).thenAnswer((_) async => _V2TeacherStatus());
      when(() => repo.myCourses()).thenAnswer((_) async {
        return reordered
            ? const <CourseStudio>[
                _reorderedCourse,
                _familyLeadCourseShifted,
                _otherFamilyCourse,
              ]
            : const <CourseStudio>[
                _course,
                _familyLeadCourse,
                _otherFamilyCourse,
              ];
      });
      when(() => repo.myCourseFamilies()).thenAnswer((_) async {
        final courses = reordered
            ? const <CourseStudio>[
                _reorderedCourse,
                _familyLeadCourseShifted,
                _otherFamilyCourse,
              ]
            : const <CourseStudio>[
                _course,
                _familyLeadCourse,
                _otherFamilyCourse,
              ];
        return _derivedCourseFamilies(courses);
      });
      when(
        () => repo.fetchCourseMeta('course-1'),
      ).thenAnswer((_) async => reordered ? _reorderedCourse : _course);
      when(
        () => repo.listCourseLessons('course-1'),
      ).thenAnswer((_) async => const <LessonStudio>[_lesson]);
      when(
        () => repo.reorderCourseWithinFamily('course-1', groupPosition: 0),
      ).thenAnswer((_) async {
        reordered = true;
        return _reorderedCourse;
      });
      when(() => repo.readLessonContent(any())).thenAnswer((invocation) async {
        final lessonId = invocation.positionalArguments.first as String;
        return _contentRead(
          lessonId: lessonId,
          contentMarkdown: 'Persisted content',
          etag: '"content-v1"',
        );
      });
      when(
        () => repo.fetchLessonMediaPlacements(any()),
      ).thenAnswer((_) async => const <StudioLessonMediaItem>[]);
      when(
        () => repo.fetchLessonMediaPreviews(any()),
      ).thenAnswer((_) async => StudioLessonMediaPreviewBatch(items: const []));

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilTextFound(tester, 'Stage: Step 1');

      final moveUpButton = find.byKey(
        const ValueKey<String>('course_family_move_up_button'),
      );
      await tester.ensureVisible(moveUpButton);
      await tester.tap(moveUpButton);
      await tester.pumpAndSettle();
      await _pumpUntilTextFound(tester, 'Stage: Introduction');

      verify(
        () => repo.reorderCourseWithinFamily('course-1', groupPosition: 0),
      ).called(1);
      expect(find.text('Introduction · Tarot Basics'), findsOneWidget);
    },
  );

  testWidgets(
    'course family move uses canonical endpoint and refreshes editor state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockStudioRepository();
      var moved = false;
      when(
        () => repo.fetchStatus(),
      ).thenAnswer((_) async => _V2TeacherStatus());
      when(() => repo.myCourses()).thenAnswer((_) async {
        return moved
            ? const <CourseStudio>[
                _movedCourse,
                _familyLeadCourse,
                _otherFamilyCourse,
              ]
            : const <CourseStudio>[
                _course,
                _familyLeadCourse,
                _otherFamilyCourse,
              ];
      });
      when(() => repo.myCourseFamilies()).thenAnswer((_) async {
        final courses = moved
            ? const <CourseStudio>[
                _movedCourse,
                _familyLeadCourse,
                _otherFamilyCourse,
              ]
            : const <CourseStudio>[
                _course,
                _familyLeadCourse,
                _otherFamilyCourse,
              ];
        return _derivedCourseFamilies(courses);
      });
      when(
        () => repo.fetchCourseMeta('course-1'),
      ).thenAnswer((_) async => moved ? _movedCourse : _course);
      when(
        () => repo.listCourseLessons('course-1'),
      ).thenAnswer((_) async => const <LessonStudio>[_lesson]);
      when(
        () => repo.moveCourseToFamily(
          'course-1',
          courseGroupId: 'course-group-2',
        ),
      ).thenAnswer((_) async {
        moved = true;
        return _movedCourse;
      });
      when(() => repo.readLessonContent(any())).thenAnswer((invocation) async {
        final lessonId = invocation.positionalArguments.first as String;
        return _contentRead(
          lessonId: lessonId,
          contentMarkdown: 'Persisted content',
          etag: '"content-v1"',
        );
      });
      when(
        () => repo.fetchLessonMediaPlacements(any()),
      ).thenAnswer((_) async => const <StudioLessonMediaItem>[]);
      when(
        () => repo.fetchLessonMediaPreviews(any()),
      ).thenAnswer((_) async => StudioLessonMediaPreviewBatch(items: const []));

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilTextFound(tester, 'Current Family: Tarot Foundations');

      final moveButton = find.byKey(
        const ValueKey<String>('course_family_move_submit_button'),
      );
      await tester.ensureVisible(moveButton);
      await tester.tap(moveButton);
      await tester.pumpAndSettle();
      await _pumpUntilTextFound(tester, 'Current Family: Breathwork Flow');

      verify(
        () => repo.moveCourseToFamily(
          'course-1',
          courseGroupId: 'course-group-2',
        ),
      ).called(1);
      expect(find.text('Step 1 · Tarot Basics'), findsOneWidget);
    },
  );

  testWidgets(
    'course metadata save excludes raw family and position patch fields',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockStudioRepository();
      _stubBaseStudioData(repo);
      when(
        () => repo.updateCourse('course-1', any()),
      ).thenAnswer((_) async => _course);

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilTextFound(tester, 'Spara kurs');

      final saveButton = find.text('Spara kurs');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final updateCapture = verify(
        () => repo.updateCourse('course-1', captureAny()),
      );
      updateCapture.called(1);
      final patch = Map<String, Object?>.from(
        updateCapture.captured.single as Map,
      );
      expect(patch['title'], 'Tarot Basics');
      expect(patch['slug'], 'tarot-basics');
      expect(patch['price_amount_cents'], 1200);
      expect(patch.containsKey('drip_enabled'), isFalse);
      expect(patch.containsKey('drip_interval_days'), isFalse);
      expect(patch.containsKey('course_group_id'), isFalse);
      expect(patch.containsKey('group_position'), isFalse);
      expect(patch.containsKey('current_unlock_position'), isFalse);
      expect(patch.containsKey('drip_started_at'), isFalse);
      verifyNever(() => repo.updateCourseDripAuthoring(any(), any()));
    },
  );

  testWidgets(
    'course schedule hydrates custom rows and saves full payload via drip-authoring endpoint',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockStudioRepository();
      var currentCourse = _course.copyWith(
        dripAuthoring: DripAuthoring.custom(
          rows: const [
            CustomScheduleRow(lessonId: 'lesson-1', unlockOffsetDays: 0),
            CustomScheduleRow(lessonId: 'lesson-2', unlockOffsetDays: 3),
          ],
        ),
      );
      Map<String, Object?>? payload;
      _stubBaseStudioData(
        repo,
        course: currentCourse,
        lessons: const [_lesson, _secondLesson],
      );
      when(
        () => repo.fetchCourseMeta('course-1'),
      ).thenAnswer((_) async => currentCourse);
      when(() => repo.updateCourseDripAuthoring('course-1', any())).thenAnswer((
        invocation,
      ) async {
        payload = Map<String, Object?>.from(
          invocation.positionalArguments[1] as Map,
        );
        currentCourse = currentCourse.copyWith(
          dripAuthoring: DripAuthoring.custom(
            rows: const [
              CustomScheduleRow(lessonId: 'lesson-1', unlockOffsetDays: 0),
              CustomScheduleRow(lessonId: 'lesson-2', unlockOffsetDays: 5),
            ],
          ),
        );
        return currentCourse;
      });

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilTextFound(tester, 'Lektionsschema');

      final firstOffsetField = find.byKey(
        const ValueKey<String>('course-custom-offset-lesson-1'),
      );
      final secondOffsetField = find.byKey(
        const ValueKey<String>('course-custom-offset-lesson-2'),
      );
      await _pumpUntilFinderFound(tester, firstOffsetField);
      await tester.ensureVisible(firstOffsetField);
      expect(firstOffsetField, findsOneWidget);
      expect(secondOffsetField, findsOneWidget);
      expect(tester.widget<TextField>(firstOffsetField).controller?.text, '0');
      expect(tester.widget<TextField>(secondOffsetField).controller?.text, '3');

      await tester.enterText(secondOffsetField, '5');
      final saveButton = find.byKey(
        const ValueKey<String>('course-schedule-save-button'),
      );
      await tester.ensureVisible(saveButton);
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      verify(() => repo.updateCourseDripAuthoring('course-1', any())).called(1);
      expect(payload, isNotNull);
      expect(payload!.keys, {'mode', 'custom_schedule'});
      expect(payload!['mode'], 'custom_lesson_offsets');
      expect(payload!['custom_schedule'], {
        'rows': [
          {'lesson_id': 'lesson-1', 'unlock_offset_days': 0},
          {'lesson_id': 'lesson-2', 'unlock_offset_days': 5},
        ],
      });
      expect(tester.widget<TextField>(secondOffsetField).controller?.text, '5');
      verifyNever(() => repo.updateCourse('course-1', any()));
    },
  );

  testWidgets(
    'custom course schedule renders timeline summary and first-lesson guidance',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockStudioRepository();
      final currentCourse = _course.copyWith(
        dripAuthoring: DripAuthoring.custom(
          rows: const [
            CustomScheduleRow(lessonId: 'lesson-1', unlockOffsetDays: 0),
            CustomScheduleRow(lessonId: 'lesson-2', unlockOffsetDays: 3),
          ],
        ),
      );
      _stubBaseStudioData(
        repo,
        course: currentCourse,
        lessons: const [_lesson, _secondLesson],
      );
      when(
        () => repo.fetchCourseMeta('course-1'),
      ).thenAnswer((_) async => currentCourse);

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilTextFound(tester, 'Lektionsschema');
      await _pumpUntilFinderFound(
        tester,
        find.byKey(const ValueKey<String>('course-custom-summary')),
      );

      expect(
        find.byKey(
          const ValueKey<String>('course-custom-timeline-row-lesson-1'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('course-custom-timeline-row-lesson-2'),
        ),
        findsOneWidget,
      );
      expect(find.text('Dag 0'), findsWidgets);
      expect(find.text('Dag 3'), findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('course-custom-first-lesson-note')),
        findsOneWidget,
      );
      expect(find.text('2 lektioner'), findsOneWidget);
      expect(find.text('Start: dag 0'), findsOneWidget);
      expect(find.text('Sista lektionen: dag 3'), findsOneWidget);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('custom course schedule shows inline row validation states', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _MockStudioRepository();
    final currentCourse = _course.copyWith(
      dripAuthoring: DripAuthoring.custom(
        rows: const [
          CustomScheduleRow(lessonId: 'lesson-1', unlockOffsetDays: 0),
          CustomScheduleRow(lessonId: 'lesson-2', unlockOffsetDays: 3),
          CustomScheduleRow(lessonId: 'lesson-3', unlockOffsetDays: 7),
        ],
      ),
    );
    _stubBaseStudioData(
      repo,
      course: currentCourse,
      lessons: const [_lesson, _secondLesson, _thirdLesson],
    );
    when(
      () => repo.fetchCourseMeta('course-1'),
    ).thenAnswer((_) async => currentCourse);

    await _pumpCourseEditor(tester, repo: repo);
    await _pumpUntilTextFound(tester, 'Lektionsschema');

    final thirdOffsetField = find.byKey(
      const ValueKey<String>('course-custom-offset-lesson-3'),
    );
    await _pumpUntilFinderFound(tester, thirdOffsetField);
    await tester.ensureVisible(thirdOffsetField);

    await tester.enterText(thirdOffsetField, '');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(thirdOffsetField).controller?.text, '');
    expect(find.text('Ange antal dagar innan upplåsning.'), findsOneWidget);

    await tester.enterText(thirdOffsetField, '-2');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(thirdOffsetField).controller?.text, '-2');
    expect(find.text('Värdet kan inte vara negativt.'), findsOneWidget);

    await tester.enterText(thirdOffsetField, '1');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(thirdOffsetField).controller?.text, '1');
    expect(
      find.text('Kan inte vara tidigare än dag 3 för föregående lektion.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'course schedule mode switches use only the drip-authoring endpoint',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockStudioRepository();
      var currentCourse = _course.copyWith(
        dripAuthoring: DripAuthoring.legacyUniform(dripIntervalDays: 7),
      );
      final payloads = <Map<String, Object?>>[];
      _stubBaseStudioData(
        repo,
        course: currentCourse,
        lessons: const [_lesson, _secondLesson],
      );
      when(
        () => repo.fetchCourseMeta('course-1'),
      ).thenAnswer((_) async => currentCourse);
      when(() => repo.updateCourseDripAuthoring('course-1', any())).thenAnswer((
        invocation,
      ) async {
        final nextPayload = Map<String, Object?>.from(
          invocation.positionalArguments[1] as Map,
        );
        payloads.add(nextPayload);
        final mode = nextPayload['mode'] as String;
        if (mode == 'custom_lesson_offsets') {
          currentCourse = currentCourse.copyWith(
            dripAuthoring: DripAuthoring.custom(
              rows: const [
                CustomScheduleRow(lessonId: 'lesson-1', unlockOffsetDays: 0),
                CustomScheduleRow(lessonId: 'lesson-2', unlockOffsetDays: 4),
              ],
            ),
          );
        } else if (mode == 'legacy_uniform_drip') {
          final legacyUniform = Map<String, Object?>.from(
            nextPayload['legacy_uniform'] as Map,
          );
          currentCourse = currentCourse.copyWith(
            dripAuthoring: DripAuthoring.legacyUniform(
              dripIntervalDays: legacyUniform['drip_interval_days'] as int,
            ),
          );
        } else {
          currentCourse = currentCourse.copyWith(
            dripAuthoring: const DripAuthoring.immediateAccess(),
          );
        }
        return currentCourse;
      });

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilTextFound(tester, 'Lektionsschema');

      final legacyModeDropdown = find.byKey(
        const ValueKey<String>('course-drip-mode-legacy_uniform_drip'),
      );
      await tester.ensureVisible(legacyModeDropdown);
      await tester.tap(legacyModeDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anpassat schema').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Anpassat schema ersätter fast intervall för kursen.'),
        findsOneWidget,
      );

      final secondOffsetField = find.byKey(
        const ValueKey<String>('course-custom-offset-lesson-2'),
      );
      await _pumpUntilFinderFound(tester, secondOffsetField);
      await tester.ensureVisible(secondOffsetField);
      await tester.enterText(secondOffsetField, '4');
      final scheduleSaveButton = find.byKey(
        const ValueKey<String>('course-schedule-save-button'),
      );
      await tester.ensureVisible(scheduleSaveButton);
      await tester.tap(scheduleSaveButton);
      await tester.pumpAndSettle();

      final customModeDropdown = find.byKey(
        const ValueKey<String>('course-drip-mode-custom_lesson_offsets'),
      );
      await tester.ensureVisible(customModeDropdown);
      await tester.tap(customModeDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fast intervall').last);
      await tester.pumpAndSettle();

      final legacyIntervalField = find.byKey(
        const ValueKey<String>('course-legacy-interval-field'),
      );
      await _pumpUntilFinderFound(tester, legacyIntervalField);
      await tester.ensureVisible(legacyIntervalField);
      await tester.enterText(legacyIntervalField, '9');
      await tester.ensureVisible(scheduleSaveButton);
      await tester.tap(scheduleSaveButton);
      await tester.pumpAndSettle();

      final legacyModeDropdownAfterSave = find.byKey(
        const ValueKey<String>('course-drip-mode-legacy_uniform_drip'),
      );
      await tester.ensureVisible(legacyModeDropdownAfterSave);
      await tester.tap(legacyModeDropdownAfterSave);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Direkt tillgång').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(scheduleSaveButton);
      await tester.tap(scheduleSaveButton);
      await tester.pumpAndSettle();

      final noDripModeDropdown = find.byKey(
        const ValueKey<String>('course-drip-mode-no_drip_immediate_access'),
      );
      await tester.ensureVisible(noDripModeDropdown);
      await tester.tap(noDripModeDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anpassat schema').last);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Du anger nu när varje lektion blir tillgänglig i kursens ordning.',
        ),
        findsOneWidget,
      );

      expect(payloads, hasLength(3));
      expect(payloads[0], {
        'mode': 'custom_lesson_offsets',
        'custom_schedule': {
          'rows': [
            {'lesson_id': 'lesson-1', 'unlock_offset_days': 0},
            {'lesson_id': 'lesson-2', 'unlock_offset_days': 4},
          ],
        },
      });
      expect(payloads[1], {
        'mode': 'legacy_uniform_drip',
        'legacy_uniform': {'drip_interval_days': 9},
      });
      expect(payloads[2], {'mode': 'no_drip_immediate_access'});
      verifyNever(() => repo.updateCourse('course-1', any()));
    },
  );

  testWidgets('locked course schedule state disables schedule controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _MockStudioRepository();
    final lockedCourse = _course.copyWith(
      dripAuthoring: DripAuthoring.custom(
        rows: const [
          CustomScheduleRow(lessonId: 'lesson-1', unlockOffsetDays: 0),
          CustomScheduleRow(lessonId: 'lesson-2', unlockOffsetDays: 2),
        ],
        scheduleLocked: true,
        lockReason: DripAuthoringLockReason.firstEnrollmentExists,
      ),
    );
    _stubBaseStudioData(
      repo,
      course: lockedCourse,
      lessons: const [_lesson, _secondLesson],
    );
    when(
      () => repo.fetchCourseMeta('course-1'),
    ).thenAnswer((_) async => lockedCourse);

    await _pumpCourseEditor(tester, repo: repo);
    await _pumpUntilTextFound(tester, 'Lektionsschema');
    await _pumpUntilTextFound(
      tester,
      'Detta schema är låst eftersom kursen har deltagare.',
    );
    final modeField = tester.widget<DropdownButtonFormField<DripAuthoringMode>>(
      find.byKey(
        const ValueKey<String>('course-drip-mode-custom_lesson_offsets'),
      ),
    );
    expect(modeField.onChanged, isNull);
    final secondOffsetField = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('course-custom-offset-lesson-2')),
    );
    expect(secondOffsetField.readOnly, isTrue);
    verifyNever(() => repo.updateCourseDripAuthoring(any(), any()));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'course schedule lock rejection stays on drip-authoring authority path',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockStudioRepository();
      final currentCourse = _course.copyWith(
        dripAuthoring: DripAuthoring.custom(
          rows: const [
            CustomScheduleRow(lessonId: 'lesson-1', unlockOffsetDays: 0),
            CustomScheduleRow(lessonId: 'lesson-2', unlockOffsetDays: 2),
          ],
        ),
      );
      _stubBaseStudioData(
        repo,
        course: currentCourse,
        lessons: const [_lesson, _secondLesson],
      );
      when(
        () => repo.fetchCourseMeta('course-1'),
      ).thenAnswer((_) async => currentCourse);
      when(() => repo.updateCourseDripAuthoring('course-1', any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(
            path: '/studio/courses/course-1/drip-authoring',
          ),
          response: Response<Object?>(
            requestOptions: RequestOptions(
              path: '/studio/courses/course-1/drip-authoring',
            ),
            statusCode: 409,
            data: <String, Object?>{
              'code': 'studio_course_schedule_locked',
              'detail':
                  'Schedule-affecting edits are locked after first enrollment.',
              'course_id': 'course-1',
              'schedule_locked': true,
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilTextFound(tester, 'Lektionsschema');
      final secondOffsetField = find.byKey(
        const ValueKey<String>('course-custom-offset-lesson-2'),
      );
      await _pumpUntilFinderFound(tester, secondOffsetField);

      final scheduleSaveButton = find.byKey(
        const ValueKey<String>('course-schedule-save-button'),
      );
      await tester.ensureVisible(scheduleSaveButton);
      await tester.tap(scheduleSaveButton);
      await tester.pumpAndSettle();

      verify(() => repo.updateCourseDripAuthoring('course-1', any())).called(1);
      verifyNever(() => repo.updateCourse('course-1', any()));
    },
  );

  testWidgets(
    'course publish uses canonical backend response as editor state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockStudioRepository();
      _stubBaseStudioData(repo);
      var published = false;
      when(() => repo.fetchCourseMeta('course-1')).thenAnswer((_) async {
        return published ? _publishedCourse : _course;
      });
      when(() => repo.publishCourse('course-1')).thenAnswer((_) async {
        published = true;
        return _publishedCourse;
      });

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilTextFound(tester, 'Publicera kurs');

      final publishButton = find.text('Publicera kurs');
      await tester.ensureVisible(publishButton);
      await tester.tap(publishButton);
      await tester.pumpAndSettle();
      await _pumpUntilTextFound(tester, 'Backendpublicerad');

      verify(() => repo.publishCourse('course-1')).called(1);
      verify(() => repo.fetchCourseMeta('course-1')).called(2);
    },
  );

  testWidgets('course publish failure does not fabricate published state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _MockStudioRepository();
    _stubBaseStudioData(repo);
    when(
      () => repo.publishCourse('course-1'),
    ).thenThrow(StateError('backend unavailable'));

    await _pumpCourseEditor(tester, repo: repo);
    await _pumpUntilTextFound(tester, 'Publicera kurs');

    final publishButton = find.text('Publicera kurs');
    await tester.ensureVisible(publishButton);
    await tester.tap(publishButton);
    await tester.pumpAndSettle();

    expect(find.text('Backendpublicerad'), findsNothing);
    expect(find.textContaining('Kunde inte publicera kurs'), findsOneWidget);
    verify(() => repo.publishCourse('course-1')).called(1);
    verify(() => repo.fetchCourseMeta('course-1')).called(1);
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
    'formatted lesson content with redundant blank lines still saves',
    (tester) async {
      final repo = _MockStudioRepository();
      _stubBaseStudioData(
        repo,
        readContent: (lessonId) async => _contentRead(
          lessonId: lessonId,
          contentMarkdown: '## Heading\n\n**Bold** *Italic*\n\n\n\nBody',
          etag: '"content-v1"',
        ),
      );
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
      await _pumpUntilDocumentContains(tester, 'Bold Italic');
      _insertAtDocumentEnd(' updated');
      await tester.pump();

      final saveButton = find.text('Spara lektionsinnehåll');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      verify(
        () => repo.updateLessonContent(
          'lesson-1',
          contentMarkdown: captureAny(named: 'contentMarkdown'),
          ifMatch: '"content-v1"',
        ),
      ).called(1);
      verify(
        () => repo.updateLessonStructure(
          'lesson-1',
          lessonTitle: any(named: 'lessonTitle'),
          position: any(named: 'position'),
        ),
      ).called(1);
      expect(
        find.textContaining('Ogiltig formatering', findRichText: true),
        findsNothing,
      );
    },
  );

  testWidgets(
    'heading followed by bold and italic lines saves and renders in preview',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockStudioRepository();
      _stubBaseStudioData(
        repo,
        readContent: (lessonId) async => _contentRead(
          lessonId: lessonId,
          contentMarkdown: '### Heading3\n\n**Bold**\n*Italic*',
          etag: '"content-v1"',
        ),
      );
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
      await _pumpUntilDocumentContains(tester, 'Heading3');
      await _pumpUntilDocumentContains(tester, 'Bold');
      await _pumpUntilDocumentContains(tester, 'Italic');

      await _openLessonPreview(tester);
      await _pumpUntilFinderFound(
        tester,
        find.byType(LearnerLessonContentRenderer),
      );

      final previewText = _renderedPreviewText(tester);
      final headingSizes = _previewTextStylesForText(tester, 'Heading3')
          .map((style) => style?.fontSize)
          .whereType<double>()
          .toList(growable: false);
      final bodySizes = _previewTextStylesForText(tester, 'Bold')
          .map((style) => style?.fontSize)
          .whereType<double>()
          .toList(growable: false);
      final boldStyles = _previewTextStylesForText(tester, 'Bold');
      final italicStyles = _previewTextStylesForText(tester, 'Italic');

      expect(previewText, contains('Heading3'));
      expect(previewText, contains('Bold'));
      expect(previewText, contains('Italic'));
      expect(
        boldStyles.any((style) => style?.fontWeight == FontWeight.bold),
        isTrue,
      );
      expect(
        italicStyles.any((style) => style?.fontStyle == FontStyle.italic),
        isTrue,
      );
      expect(headingSizes, isNotEmpty);
      expect(bodySizes, isNotEmpty);
      expect(
        headingSizes.reduce((a, b) => a > b ? a : b),
        greaterThan(bodySizes.reduce((a, b) => a < b ? a : b)),
      );

      await _closeLessonPreview(tester);
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
      final savedMarkdown = contentCapture.captured.single as String;
      expect(savedMarkdown, contains('### Heading3'));
      expect(savedMarkdown, contains('**Bold**'));
      expect(savedMarkdown, contains('Italic'));
      expect(
        find.textContaining('Ogiltig formatering', findRichText: true),
        findsNothing,
      );
    },
  );

  testWidgets('malformed lesson markdown is blocked before repository write', (
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

    _insertAtDocumentEnd(' *italic*');
    await tester.pump();

    final saveButton = find.text('Spara lektionsinnehåll');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Ogiltig formatering i lektionsinnehallet. Korrigera formateringen innan du sparar.',
      ),
      findsOneWidget,
    );
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

  testWidgets(
    'preview renders persisted markdown and media without saved mirror UI',
    (tester) async {
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
              '## Heading\n\n'
              '**Bold** *Italic* <u>Underline</u>\n\n'
              'Body text\n\n'
              '1. Ordered item\n'
              '2. Ordered follow-up\n\n'
              '- Bullet item\n\n'
              '!image($embeddedImageId)\n',
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
        final placements = <StudioLessonMediaItem>[
          for (final id in ids)
            if (id == trailingDocumentId)
              _placementDocument(id, position: 2)
            else
              _placementImage(id, position: 1),
        ];
        placements.sort((a, b) => a.position.compareTo(b.position));
        return placements;
      });

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilDocumentContains(tester, 'Body text');
      await tester.pumpAndSettle();

      clearInteractions(repo);
      _insertAtDocumentEnd(' unsaved draft');
      await tester.pump();
      expect(editor_test_bridge.getDocument(), contains('unsaved draft'));

      await _openLessonPreview(tester);
      await _pumpUntilFinderFound(
        tester,
        find.byType(LearnerLessonContentRenderer),
      );
      await _pumpUntilFinderFound(
        tester,
        find.byKey(const ValueKey<String>('lesson_preview_live_badge')),
      );
      await _pumpUntilFinderFound(
        tester,
        _networkImageFinder(_canonicalLessonMediaUrl),
      );
      await _pumpUntilFinderFound(tester, find.text('Dokument'));
      await _pumpUntilFinderFound(tester, find.text('Ladda ner dokument'));

      final previewText = _renderedPreviewText(tester);
      final headingSizes = _previewTextStylesForText(tester, 'Heading')
          .map((style) => style?.fontSize)
          .whereType<double>()
          .toList(growable: false);
      final bodySizes = _previewTextStylesForText(tester, 'Body text')
          .map((style) => style?.fontSize)
          .whereType<double>()
          .toList(growable: false);
      final boldStyles = _previewTextStylesForText(tester, 'Bold');
      final italicStyles = _previewTextStylesForText(tester, 'Italic');
      final underlineStyles = _previewTextStylesForText(tester, 'Underline');

      expect(find.text('Saved mirror'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('lesson_preview_saved_source_chip')),
        findsNothing,
      );
      expect(previewText, contains('Heading'));
      expect(previewText, contains('Bold'));
      expect(previewText, contains('Italic'));
      expect(previewText, contains('Underline'));
      expect(previewText, contains('Body text'));
      expect(previewText, contains('Ordered item'));
      expect(previewText, contains('Bullet item'));
      expect(previewText, isNot(contains('unsaved draft')));
      expect(
        boldStyles.any((style) => style?.fontWeight == FontWeight.bold),
        isTrue,
      );
      expect(
        italicStyles.any((style) => style?.fontStyle == FontStyle.italic),
        isTrue,
      );
      expect(
        underlineStyles.any(
          (style) =>
              style?.decoration?.contains(TextDecoration.underline) ?? false,
        ),
        isTrue,
      );
      expect(headingSizes, isNotEmpty);
      expect(bodySizes, isNotEmpty);
      final maxHeadingSize = headingSizes.reduce((a, b) => a > b ? a : b);
      final minBodySize = bodySizes.reduce((a, b) => a < b ? a : b);
      expect(maxHeadingSize, greaterThan(minBodySize));
      expect(
        _networkImageFinder(_canonicalLessonMediaUrl),
        findsAtLeastNWidgets(1),
      );

      verify(() => repo.readLessonContent(any())).called(1);
      verifyNever(() => repo.fetchLessonMediaPlacements(any()));
      verifyNever(() => repo.fetchCourseMeta(any()));
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
    },
  );

  testWidgets(
    'preview ignores unsaved editor changes and refetches persisted content',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _MockStudioRepository();
      _stubBaseStudioData(repo);

      await _pumpCourseEditor(tester, repo: repo);
      await _pumpUntilDocumentContains(tester, 'Persisted content');
      await tester.pumpAndSettle();
      clearInteractions(repo);

      _insertAtDocumentEnd(' draft one');
      await tester.pump();
      await _openLessonPreview(tester);
      await _pumpUntilFinderFound(
        tester,
        find.textContaining('Persisted content', findRichText: true),
      );
      expect(_renderedPreviewText(tester), isNot(contains('draft one')));

      await _closeLessonPreview(tester);
      _insertAtDocumentEnd(' draft two');
      await tester.pump();

      await _openLessonPreview(tester);
      await _pumpUntilFinderFound(
        tester,
        find.textContaining('Persisted content', findRichText: true),
      );
      expect(_renderedPreviewText(tester), isNot(contains('draft one')));
      expect(_renderedPreviewText(tester), isNot(contains('draft two')));
      verify(() => repo.readLessonContent(any())).called(2);
      verifyNever(() => repo.fetchLessonMediaPlacements(any()));
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
