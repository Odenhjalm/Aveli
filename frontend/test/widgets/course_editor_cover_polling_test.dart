import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/application/studio_upload_queue.dart';
import 'package:aveli/features/studio/data/studio_repository.dart';
import 'package:aveli/features/studio/presentation/course_editor_page.dart';

class _MockStudioRepository extends Mock implements StudioRepository {}

class _MockMediaPipelineRepository extends Mock
    implements MediaPipelineRepository {}

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
  Future<void> loadSession() async {}
}

class _NoopUploadQueueNotifier extends UploadQueueNotifier {
  _NoopUploadQueueNotifier(super.repo);

  @override
  String enqueueUpload({
    required String courseId,
    required String lessonId,
    required Uint8List data,
    required String filename,
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
  testWidgets('cover polling error clears updating state', (tester) async {
    final studioRepo = _MockStudioRepository();
    final mediaRepo = _MockMediaPipelineRepository();

    when(() => studioRepo.fetchStatus()).thenAnswer(
      (_) async =>
          const StudioStatus(isTeacher: true, verifiedCertificates: 1, hasApplication: false),
    );
    when(() => studioRepo.myCourses()).thenAnswer(
      (_) async => [
        {'id': 'course-1', 'title': 'Testkurs'},
      ],
    );
    when(() => studioRepo.fetchCourseMeta('course-1')).thenAnswer(
      (_) async => {
        'title': 'Testkurs',
        'slug': 'testkurs',
        'description': 'Beskrivning',
        'price_cents': 0,
        'is_free_intro': false,
        'is_published': false,
      },
    );
    when(() => studioRepo.listModules('course-1')).thenAnswer(
      (_) async => [
        {'id': 'module-1', 'title': 'Modul', 'position': 1},
      ],
    );
    when(() => studioRepo.listLessons('module-1')).thenAnswer(
      (_) async => [
        {
          'id': 'lesson-1',
          'title': 'Lektion',
          'position': 1,
          'is_intro': false,
          'course_id': 'course-1',
        },
      ],
    );
    when(() => studioRepo.listLessonMedia('lesson-1')).thenAnswer(
      (_) async => [
        {
          'id': 'media-1',
          'kind': 'image',
          'storage_path': 'course-1/lesson-1/image.png',
          'storage_bucket': 'course-media',
          'position': 1,
          'lesson_id': 'lesson-1',
          'course_id': 'course-1',
        },
      ],
    );

    when(
      () => mediaRepo.requestCoverFromLessonMedia(
        courseId: any(named: 'courseId'),
        lessonMediaId: any(named: 'lessonMediaId'),
      ),
    ).thenAnswer(
      (_) async => const CoverMediaResponse(mediaId: 'cover-1', state: 'uploaded'),
    );
    when(() => mediaRepo.fetchStatus(any()))
        .thenThrow(Exception('fetch failed'));

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
          mediaPipelineRepositoryProvider.overrideWithValue(mediaRepo),
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

    final coverButton = find.byTooltip('Använd som kursbild');
    await tester.ensureVisible(coverButton);
    await tester.tap(coverButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Kunde inte hämta status för kursbilden. Försök igen.'),
      findsOneWidget,
    );
    expect(find.text('Uppdaterar...'), findsNothing);
  });
}
