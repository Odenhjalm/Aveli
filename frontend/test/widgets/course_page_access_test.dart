import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_page.dart';
import 'package:aveli/shared/utils/course_cover_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _TestAuthController extends AuthController {
  _TestAuthController({
    required AuthRepository repo,
    required AuthHttpObserver observer,
    Profile? profile,
  }) : super(repo, observer) {
    state = AuthState(profile: profile, isLoading: false);
  }
}

CourseDetailData _detail({
  required String courseId,
  required String slug,
  required String title,
  required int groupPosition,
  String? coverMediaId,
  CourseCoverData? cover,
  int? priceCents = 0,
  String? requiredEnrollmentSource = 'intro',
  bool enrollable = true,
  bool purchasable = false,
  bool dripEnabled = false,
  int? dripIntervalDays,
  List<LessonSummary>? lessons,
  String? shortDescription = 'Backendbeskriven kurs för startklara elever.',
}) {
  return CourseDetailData(
    course: CourseSummary(
      id: courseId,
      slug: slug,
      title: title,
      shortDescription: shortDescription,
      teacher: const CourseTeacherData(
        userId: 'teacher-1',
        displayName: 'Aveli Teacher',
      ),
      groupPosition: groupPosition,
      courseGroupId: 'group-1',
      coverMediaId: coverMediaId,
      cover: cover,
      priceCents: priceCents,
      dripEnabled: dripEnabled,
      dripIntervalDays: dripIntervalDays,
      requiredEnrollmentSource: requiredEnrollmentSource,
      enrollable: enrollable,
      purchasable: purchasable,
    ),
    lessons:
        lessons ??
        const [
          LessonSummary(id: 'lesson-1', lessonTitle: 'Lesson 1', position: 1),
        ],
    shortDescription: shortDescription,
  );
}

CourseAccessData _courseState(
  String courseId, {
  bool canAccess = true,
  bool isIntroCourse = true,
  bool selectionLocked = false,
  String? requiredEnrollmentSource = 'intro',
  bool enrollable = true,
  bool purchasable = false,
  int currentUnlockPosition = 1,
  String source = 'intro',
  DateTime? grantedAt,
  DateTime? nextUnlockAt,
}) {
  final effectiveGrantedAt = grantedAt ?? DateTime.utc(2024, 1, 1);
  return CourseAccessData(
    courseId: courseId,
    groupPosition: 0,
    requiredEnrollmentSource: requiredEnrollmentSource,
    enrollable: enrollable,
    purchasable: purchasable,
    isIntroCourse: isIntroCourse,
    selectionLocked: selectionLocked,
    canAccess: canAccess,
    nextUnlockAt: nextUnlockAt,
    enrollment: CourseEnrollmentRecord(
      id: 'enrollment-1',
      userId: 'user-1',
      courseId: courseId,
      source: source,
      grantedAt: effectiveGrantedAt,
      dripStartedAt: effectiveGrantedAt,
      currentUnlockPosition: currentUnlockPosition,
    ),
  );
}

CourseAccessData _enrolledState(String courseId) {
  return _courseState(courseId);
}

CourseAccessData _deniedStateWithEnrollment(String courseId) {
  return _courseState(
    courseId,
    canAccess: false,
    isIntroCourse: false,
    requiredEnrollmentSource: 'purchase',
    enrollable: false,
    purchasable: true,
    source: 'purchase',
  );
}

void main() {
  Override authOverride({Profile? profile}) {
    final repo = _MockAuthRepository();
    final observer = AuthHttpObserver();
    return authControllerProvider.overrideWith(
      (ref) =>
          _TestAuthController(repo: repo, observer: observer, profile: profile),
    );
  }

  testWidgets('intro CTA renders only from backend unlocked intro state', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-intro',
      slug: 'intro-course',
      title: 'Intro Course',
      groupPosition: 2,
      enrollable: true,
      purchasable: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith(
            (ref, courseId) async => _courseState(courseId, canAccess: false),
          ),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'intro-course')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Starta introduktion'), findsOneWidget);
  });

  testWidgets(
    'intro CTA does not fall back to course enrollable when access state is absent',
    (tester) async {
      final detail = _detail(
        courseId: 'course-intro-null',
        slug: 'intro-course-null',
        title: 'Intro Course Null',
        groupPosition: 2,
        enrollable: true,
        purchasable: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(
                apiBaseUrl: 'http://localhost:8080',
                subscriptionsEnabled: true,
              ),
            ),
            authOverride(),
            courseDetailProvider.overrideWith((ref, slug) async => detail),
            courseStateProvider.overrideWith((ref, courseId) async => null),
          ],
          child: const MaterialApp(home: CoursePage(slug: 'intro-course-null')),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Starta introduktion'), findsNothing);
    },
  );

  testWidgets('selection-locked intro courses do not show enrollment CTA', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-intro-locked',
      slug: 'intro-course-locked',
      title: 'Locked Intro Course',
      groupPosition: 2,
      enrollable: true,
      purchasable: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith(
            (ref, courseId) async =>
                _courseState(courseId, canAccess: false, selectionLocked: true),
          ),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'intro-course-locked')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Starta introduktion'), findsNothing);
    expect(
      find.text(
        'Du behöver slutföra din pågående introduktion innan du kan välja en ny.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('course detail renders backend teacher and description', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-detail',
      slug: 'detail-course',
      title: 'Detail Course',
      groupPosition: 0,
      shortDescription: 'En tydlig kursbeskrivning från backend.',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith((ref, courseId) async => null),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'detail-course')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Lärare: Aveli Teacher'), findsOneWidget);
    expect(
      find.text('En tydlig kursbeskrivning från backend.'),
      findsOneWidget,
    );
  });

  testWidgets('sellable position-zero courses do not show enrollment CTA', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-paid-zero',
      slug: 'paid-zero-course',
      title: 'Paid Zero Course',
      groupPosition: 0,
      priceCents: 9900,
      requiredEnrollmentSource: 'purchase',
      enrollable: false,
      purchasable: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith((ref, courseId) async => null),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'paid-zero-course')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Starta introduktion'), findsNothing);
  });

  testWidgets('enrolled learners continue with unlocked lessons', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-enrolled',
      slug: 'enrolled-course',
      title: 'Enrolled Course',
      groupPosition: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith(
            (ref, courseId) async => _enrolledState(courseId),
          ),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'enrolled-course')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Forts'), findsOneWidget);
    expect(find.text('Lesson 1'), findsOneWidget);
  });

  testWidgets('drip learners see availability states and next countdown', (
    tester,
  ) async {
    final nextUnlockAt = DateTime.now().toUtc().add(const Duration(days: 7));
    final detail = _detail(
      courseId: 'course-drip',
      slug: 'drip-course',
      title: 'Drip Course',
      groupPosition: 0,
      dripEnabled: true,
      dripIntervalDays: 7,
      lessons: const [
        LessonSummary(id: 'lesson-1', lessonTitle: 'Lesson 1', position: 1),
        LessonSummary(id: 'lesson-2', lessonTitle: 'Lesson 2', position: 2),
        LessonSummary(id: 'lesson-3', lessonTitle: 'Lesson 3', position: 3),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith(
            (ref, courseId) async => _courseState(
              courseId,
              currentUnlockPosition: 1,
              nextUnlockAt: nextUnlockAt,
            ),
          ),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'drip-course')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Kursen släpps stegvis'), findsOneWidget);
    expect(find.text('Nästa lektion om 7 dagar'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Lesson 3'), 200);
    await tester.pumpAndSettle();

    expect(find.text('Lesson 2'), findsOneWidget);
    expect(find.text('Låst'), findsWidgets);
    expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);
  });

  testWidgets('fully unlocked learner courses show all lessons available', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-open',
      slug: 'open-course',
      title: 'Open Course',
      groupPosition: 0,
      lessons: const [
        LessonSummary(id: 'lesson-1', lessonTitle: 'Lesson 1', position: 1),
        LessonSummary(id: 'lesson-2', lessonTitle: 'Lesson 2', position: 2),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith(
            (ref, courseId) async =>
                _courseState(courseId, currentUnlockPosition: 2),
          ),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'open-course')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Alla lektioner tillgängliga'), findsOneWidget);
    expect(find.text('Kursen släpps stegvis'), findsNothing);
  });

  testWidgets('locked lesson taps show the learner drip lock message', (
    tester,
  ) async {
    final nextUnlockAt = DateTime.now().toUtc().add(const Duration(days: 7));
    final detail = _detail(
      courseId: 'course-tap-lock',
      slug: 'tap-lock-course',
      title: 'Tap Lock Course',
      groupPosition: 0,
      dripEnabled: true,
      dripIntervalDays: 7,
      lessons: const [
        LessonSummary(id: 'lesson-1', lessonTitle: 'Lesson 1', position: 1),
        LessonSummary(id: 'lesson-2', lessonTitle: 'Lesson 2', position: 2),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith(
            (ref, courseId) async => _courseState(
              courseId,
              currentUnlockPosition: 1,
              nextUnlockAt: nextUnlockAt,
            ),
          ),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'tap-lock-course')),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Lesson 2'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lesson 2'));
    await tester.pump();

    expect(
      find.text('Den här lektionen blir tillgänglig om 7 dagar'),
      findsOneWidget,
    );
  });

  testWidgets(
    'custom drip courses render backend-authored next unlock timing',
    (tester) async {
      final nextUnlockAt = DateTime.now().toUtc().add(const Duration(days: 3));
      final detail = _detail(
        courseId: 'course-custom',
        slug: 'custom-course',
        title: 'Custom Course',
        groupPosition: 0,
        lessons: const [
          LessonSummary(id: 'lesson-1', lessonTitle: 'Lesson 1', position: 1),
          LessonSummary(id: 'lesson-2', lessonTitle: 'Lesson 2', position: 2),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(
                apiBaseUrl: 'http://localhost:8080',
                subscriptionsEnabled: true,
              ),
            ),
            authOverride(),
            courseDetailProvider.overrideWith((ref, slug) async => detail),
            courseStateProvider.overrideWith(
              (ref, courseId) async => _courseState(
                courseId,
                currentUnlockPosition: 1,
                nextUnlockAt: nextUnlockAt,
              ),
            ),
          ],
          child: const MaterialApp(home: CoursePage(slug: 'custom-course')),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Kursen släpps stegvis'), findsOneWidget);
      expect(find.text('Nästa lektion om 3 dagar'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Lesson 2'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lesson 2'));
      await tester.pump();

      expect(
        find.text('Den här lektionen blir tillgänglig om 3 dagar'),
        findsOneWidget,
      );
    },
  );

  testWidgets('course page locks lessons when backend can_access is false', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-denied',
      slug: 'denied-course',
      title: 'Denied Course',
      groupPosition: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith(
            (ref, courseId) async => _deniedStateWithEnrollment(courseId),
          ),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'denied-course')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Forts'), findsNothing);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
  });

  testWidgets('learner course page renders backend cover resolved url', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-cover',
      slug: 'cover-course',
      title: 'Cover Course',
      groupPosition: 0,
      coverMediaId: 'media-1',
      cover: const CourseCoverData(
        mediaId: 'media-1',
        state: 'ready',
        resolvedUrl: 'https://cdn.test/course-cover.jpg',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith((ref, courseId) async => null),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'cover-course')),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url ==
                'https://cdn.test/course-cover.jpg',
        description: 'Image.network(https://cdn.test/course-cover.jpg)',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isA<NetworkImageLoadException>());
  });

  testWidgets('paid course page renders cover without enrollment state', (
    tester,
  ) async {
    final detail = _detail(
      courseId: 'course-paid-cover',
      slug: 'paid-cover-course',
      title: 'Paid Cover Course',
      groupPosition: 1,
      priceCents: 9900,
      requiredEnrollmentSource: 'purchase',
      enrollable: false,
      purchasable: true,
      coverMediaId: 'media-1',
      cover: const CourseCoverData(
        mediaId: 'media-1',
        state: 'ready',
        resolvedUrl: 'https://cdn.test/paid-course-cover.jpg',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith((ref, slug) async => detail),
          courseStateProvider.overrideWith((ref, courseId) async => null),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'paid-cover-course')),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url ==
                'https://cdn.test/paid-course-cover.jpg',
        description: 'Image.network(https://cdn.test/paid-course-cover.jpg)',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isA<NetworkImageLoadException>());
  });

  testWidgets('course page load error hides raw backend or parser text', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost:8080',
              subscriptionsEnabled: true,
            ),
          ),
          authOverride(),
          courseDetailProvider.overrideWith(
            (ref, slug) async =>
                throw StateError('Course not found: backend internal text'),
          ),
        ],
        child: const MaterialApp(home: CoursePage(slug: 'missing-course')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Kursen kunde inte laddas.'), findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.textContaining('Course not found'), findsNothing);
    expect(find.textContaining('backend internal'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
