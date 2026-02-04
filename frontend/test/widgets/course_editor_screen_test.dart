import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;

import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/presentation/course_editor_page.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/application/studio_upload_queue.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import '../helpers/backend_asset_resolver_stub.dart';

class _MockStudioRepository extends Mock implements StudioRepository {}

class _MockCoursesRepository extends Mock implements CoursesRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _FakeAuthController extends AuthController {
  _FakeAuthController() : super(_MockAuthRepository(), AuthHttpObserver()) {
    state = AuthState(
      profile: Profile(
        id: 'user-1',
        email: 'teacher@example.com',
        userRole: UserRole.teacher,
        isAdmin: false,
        createdAt: DateTime.utc(2024, 1, 1),
        updatedAt: DateTime.utc(2024, 1, 1),
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
    required bool isIntro,
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

void main() {
  setUpAll(() {
    registerFallbackValue(const Duration());
    registerFallbackValue(<String, dynamic>{});
  });

  testWidgets('CourseEditorScreen renders provided course data', (
    tester,
  ) async {
    final studioRepo = _MockStudioRepository();
    final coursesRepo = _MockCoursesRepository();

    when(() => studioRepo.myCourses()).thenAnswer(
      (_) async => [
        {'id': 'course-1', 'title': 'Tarot Basics'},
      ],
    );
    when(() => studioRepo.fetchStatus()).thenAnswer(
      (_) async => const StudioStatus(
        isTeacher: true,
        verifiedCertificates: 1,
        hasApplication: false,
      ),
    );
    when(() => studioRepo.fetchCourseMeta('course-1')).thenAnswer(
      (_) async => {
        'title': 'Tarot Basics',
        'slug': 'tarot-basics',
        'description': 'Lär dig läsa korten',
        'price_amount_cents': 1200,
        'is_free_intro': true,
        'is_published': false,
      },
    );
    when(() => studioRepo.listCourseLessons('course-1')).thenAnswer(
      (_) async => [
        {
          'id': 'lesson-1',
          'title': 'Välkommen',
          'position': 1,
          'is_intro': true,
          'course_id': 'course-1',
        },
      ],
    );
    when(() => studioRepo.listLessonMedia('lesson-1')).thenAnswer(
      (_) async => [
        {
          'id': 'media-1',
          'kind': 'video',
          'storage_path': 'course-1/lesson-1/video.mp4',
          'storage_bucket': 'public-media',
          'position': 1,
        },
        {
          'id': 'media-2',
          'kind': 'pdf',
          'media_asset_id': 'asset-2',
          'media_state': 'processing',
          'original_name': 'material.pdf',
          'position': 2,
        },
      ],
    );

    final courseDetail = CourseDetailData(
      course: const CourseSummary(
        id: 'course-1',
        slug: 'tarot-basics',
        title: 'Tarot Basics',
        description: 'Lär dig läsa korten',
        coverUrl: null,
        videoUrl: null,
        isFreeIntro: true,
        isPublished: true,
        priceCents: 1200,
      ),
      modules: const [
        CourseModule(id: 'module-1', title: 'Intro', position: 1),
      ],
      lessonsByModule: {
        'module-1': const [
          LessonSummary(
            id: 'lesson-1',
            title: 'Välkommen',
            position: 1,
            isIntro: true,
            contentMarkdown: null,
          ),
        ],
      },
      freeConsumed: 0,
      freeLimit: 3,
      isEnrolled: false,
      latestOrder: null,
    );
    when(
      () => coursesRepo.fetchCourseDetailBySlug(any()),
    ).thenAnswer((_) async => courseDetail);

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
          backendAssetResolverProvider.overrideWith(
            (ref) => TestBackendAssetResolver(),
          ),
          authControllerProvider.overrideWith((ref) => _FakeAuthController()),
          studioRepositoryProvider.overrideWithValue(studioRepo),
          coursesRepositoryProvider.overrideWithValue(coursesRepo),
          studioStatusProvider.overrideWith(
            (ref) async => const StudioStatus(
              isTeacher: true,
              verifiedCertificates: 1,
              hasApplication: false,
            ),
          ),
          studioUploadQueueProvider.overrideWith(
            (ref) => _NoopUploadQueueNotifier(studioRepo),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('sv')],
          home: CourseEditorScreen(
            studioRepository: studioRepo,
            coursesRepository: coursesRepo,
          ),
        ),
      ),
    );

    // Pump a few frames to allow async futures to resolve without waiting for
    // the continuously updating video player streams to settle.
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Tarot Basics'), findsWidgets);
    expect(find.text('Lektioner i kursen'), findsOneWidget);
    expect(find.text('Välkommen'), findsWidgets);
    expect(find.text('Spara lektionsinnehåll'), findsOneWidget);
    expect(find.text('Ladda upp WAV'), findsOneWidget);
    expect(find.text('material.pdf'), findsOneWidget);
    expect(find.text('processing'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    final uploadButton = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Ladda upp WAV'),
        matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
      ),
    );
    expect(uploadButton.onPressed, isNotNull);
  });

  testWidgets('CourseEditorScreen creates lessons directly under course', (
    tester,
  ) async {
    final studioRepo = _MockStudioRepository();

    when(() => studioRepo.myCourses()).thenAnswer(
      (_) async => [
        {'id': 'course-1', 'title': 'Tarot Basics'},
      ],
    );
    when(() => studioRepo.fetchStatus()).thenAnswer(
      (_) async => const StudioStatus(
        isTeacher: true,
        verifiedCertificates: 1,
        hasApplication: false,
      ),
    );
    when(() => studioRepo.fetchCourseMeta('course-1')).thenAnswer(
      (_) async => {
        'title': 'Tarot Basics',
        'slug': 'tarot-basics',
        'description': 'Lär dig läsa korten',
        'price_amount_cents': 1200,
        'is_free_intro': true,
        'is_published': false,
      },
    );
    when(
      () => studioRepo.listCourseLessons('course-1'),
    ).thenAnswer((_) async => []);
    when(
      () => studioRepo.upsertLesson(
        courseId: 'course-1',
        title: any(named: 'title'),
        position: any(named: 'position'),
        isIntro: any(named: 'isIntro'),
        createId: any(named: 'createId'),
      ),
    ).thenAnswer((invocation) async {
      final createId = invocation.namedArguments[#createId] as String;
      final title = invocation.namedArguments[#title] as String;
      final position = invocation.namedArguments[#position] as int;
      return {
        'id': createId,
        'title': title,
        'position': position,
        'is_intro': false,
        'course_id': 'course-1',
      };
    });
    when(() => studioRepo.listLessonMedia(any())).thenAnswer((_) async => []);

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
          studioRepositoryProvider.overrideWithValue(studioRepo),
          studioUploadQueueProvider.overrideWith(
            (ref) => _NoopUploadQueueNotifier(studioRepo),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('sv')],
          home: CourseEditorScreen(studioRepository: studioRepo),
        ),
      ),
    );

    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Inga lektioner ännu.'), findsOneWidget);

    final addLesson = find.text('Lägg till lektion').first;
    await tester.ensureVisible(addLesson);
    await tester.tap(addLesson);
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    verify(
      () => studioRepo.upsertLesson(
        courseId: 'course-1',
        title: 'Ny lektion',
        position: any(named: 'position'),
        isIntro: false,
        createId: any(named: 'createId'),
      ),
    ).called(1);
    expect(find.text('Ny lektion'), findsWidgets);
  });

  testWidgets(
    'CourseEditorScreen renders missing pipeline reference as error row',
    (tester) async {
      final studioRepo = _MockStudioRepository();
      final coursesRepo = _MockCoursesRepository();

      when(() => studioRepo.myCourses()).thenAnswer(
        (_) async => [
          {'id': 'course-1', 'title': 'Tarot Basics'},
        ],
      );
      when(() => studioRepo.fetchStatus()).thenAnswer(
        (_) async => const StudioStatus(
          isTeacher: true,
          verifiedCertificates: 1,
          hasApplication: false,
        ),
      );
      when(() => studioRepo.fetchCourseMeta('course-1')).thenAnswer(
        (_) async => {
          'title': 'Tarot Basics',
          'slug': 'tarot-basics',
          'description': 'Lär dig läsa korten',
          'price_amount_cents': 1200,
          'is_free_intro': true,
          'is_published': false,
        },
      );
      when(() => studioRepo.listCourseLessons('course-1')).thenAnswer(
        (_) async => [
          {
            'id': 'lesson-1',
            'title': 'Välkommen',
            'position': 1,
            'is_intro': true,
            'course_id': 'course-1',
          },
        ],
      );
      when(() => studioRepo.listLessonMedia('lesson-1')).thenAnswer(
        (_) async => [
          {
            'id': 'media-1',
            'kind': 'pdf',
            'media_asset_id': 'missing-asset',
            'original_name': 'missing.pdf',
            'position': 1,
          },
        ],
      );

      final courseDetail = CourseDetailData(
        course: const CourseSummary(
          id: 'course-1',
          slug: 'tarot-basics',
          title: 'Tarot Basics',
          description: 'Lär dig läsa korten',
          coverUrl: null,
          videoUrl: null,
          isFreeIntro: true,
          isPublished: true,
          priceCents: 1200,
        ),
        modules: const [
          CourseModule(id: 'module-1', title: 'Intro', position: 1),
        ],
        lessonsByModule: {
          'module-1': const [
            LessonSummary(
              id: 'lesson-1',
              title: 'Välkommen',
              position: 1,
              isIntro: true,
              contentMarkdown: null,
            ),
          ],
        },
        freeConsumed: 0,
        freeLimit: 3,
        isEnrolled: false,
        latestOrder: null,
      );
      when(
        () => coursesRepo.fetchCourseDetailBySlug(any()),
      ).thenAnswer((_) async => courseDetail);

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
            backendAssetResolverProvider.overrideWith(
              (ref) => TestBackendAssetResolver(),
            ),
            authControllerProvider.overrideWith((ref) => _FakeAuthController()),
            studioRepositoryProvider.overrideWithValue(studioRepo),
            coursesRepositoryProvider.overrideWithValue(coursesRepo),
            studioStatusProvider.overrideWith(
              (ref) async => const StudioStatus(
                isTeacher: true,
                verifiedCertificates: 1,
                hasApplication: false,
              ),
            ),
            studioUploadQueueProvider.overrideWith(
              (ref) => _NoopUploadQueueNotifier(studioRepo),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              FlutterQuillLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('sv')],
            home: CourseEditorScreen(
              studioRepository: studioRepo,
              coursesRepository: coursesRepo,
            ),
          ),
        ),
      );

      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('missing.pdf'), findsOneWidget);
      expect(find.text('failed'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    },
  );

  testWidgets('CourseEditorScreen saves price_amount_cents', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final studioRepo = _MockStudioRepository();
    final coursesRepo = _MockCoursesRepository();

    when(() => studioRepo.myCourses()).thenAnswer(
      (_) async => [
        {'id': 'course-1', 'title': 'Tarot Basics'},
      ],
    );
    when(() => studioRepo.fetchStatus()).thenAnswer(
      (_) async => const StudioStatus(
        isTeacher: true,
        verifiedCertificates: 1,
        hasApplication: false,
      ),
    );
    when(() => studioRepo.fetchCourseMeta('course-1')).thenAnswer(
      (_) async => {
        'title': 'Tarot Basics',
        'slug': 'tarot-basics',
        'description': 'Lär dig läsa korten',
        'price_amount_cents': 1200,
        'is_free_intro': true,
        'is_published': false,
      },
    );
    when(
      () => studioRepo.listCourseLessons('course-1'),
    ).thenAnswer((_) async => []);
    when(() => studioRepo.updateCourse(any(), any())).thenAnswer((
      invocation,
    ) async {
      final courseId = invocation.positionalArguments[0] as String;
      final patch = Map<String, dynamic>.from(
        invocation.positionalArguments[1] as Map,
      );
      return {'id': courseId, ...patch};
    });

    final courseDetail = CourseDetailData(
      course: const CourseSummary(
        id: 'course-1',
        slug: 'tarot-basics',
        title: 'Tarot Basics',
        description: 'Lär dig läsa korten',
        coverUrl: null,
        videoUrl: null,
        isFreeIntro: true,
        isPublished: true,
        priceCents: 1200,
      ),
      modules: const [],
      lessonsByModule: const {},
      freeConsumed: 0,
      freeLimit: 3,
      isEnrolled: false,
      latestOrder: null,
    );
    when(
      () => coursesRepo.fetchCourseDetailBySlug(any()),
    ).thenAnswer((_) async => courseDetail);

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
          backendAssetResolverProvider.overrideWith(
            (ref) => TestBackendAssetResolver(),
          ),
          authControllerProvider.overrideWith((ref) => _FakeAuthController()),
          studioRepositoryProvider.overrideWithValue(studioRepo),
          coursesRepositoryProvider.overrideWithValue(coursesRepo),
          studioStatusProvider.overrideWith(
            (ref) async => const StudioStatus(
              isTeacher: true,
              verifiedCertificates: 1,
              hasApplication: false,
            ),
          ),
          studioUploadQueueProvider.overrideWith(
            (ref) => _NoopUploadQueueNotifier(studioRepo),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('sv')],
          home: CourseEditorScreen(
            studioRepository: studioRepo,
            coursesRepository: coursesRepo,
          ),
        ),
      ),
    );

    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final priceField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Pris (SEK)',
    );
    expect(priceField, findsOneWidget);

    await tester.ensureVisible(priceField);
    final introToggle = find.widgetWithText(
      SwitchListTile,
      'Introduktionskurs',
    );
    expect(introToggle, findsOneWidget);
    await tester.tap(introToggle);
    await tester.pump();

    await tester.enterText(priceField, '99');

    final saveButton = find.text('Spara kurs');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);

    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final captured = verify(
      () => studioRepo.updateCourse('course-1', captureAny()),
    ).captured;
    expect(captured, hasLength(1));
    final patch = Map<String, dynamic>.from(captured.single as Map);
    expect(patch['price_amount_cents'], 9900);
    expect(patch.containsKey('price_cents'), isFalse);
  });
}
