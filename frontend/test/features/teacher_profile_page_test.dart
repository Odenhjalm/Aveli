import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/routing/route_session.dart';
import 'package:aveli/data/models/certificate.dart';
import 'package:aveli/data/models/service.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/presentation/teacher_profile_page.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import '../helpers/backend_asset_resolver_stub.dart';

const _baseService = Service(
  id: 'svc-1',
  title: 'Tarotläsning',
  description: '30 minuter fokus på ditt nästa steg.',
  priceCents: 11900,
  currency: 'sek',
  status: 'active',
  durationMinutes: 30,
  requiresCertification: true,
  certifiedArea: 'Tarot',
);

const _teacherState = TeacherProfileState(
  teacher: {
    'profile': {'display_name': 'Testlärare'},
    'headline': 'Guidning och tarot.',
  },
  services: [_baseService],
  meditations: [],
  certificates: [],
  profileMedia: [],
);

RouteSessionSnapshot _session({required bool isAuthenticated}) =>
    RouteSessionSnapshot(
      isAuthenticated: isAuthenticated,
      isAuthLoading: false,
      hasTentativeSession: false,
      isTeacher: false,
      isAdmin: false,
    );

Future<void> _pumpPage(
  WidgetTester tester, {
  required RouteSessionSnapshot session,
  required List<Certificate> viewerCertificates,
  TeacherProfileState? overrideState,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://localhost',
            stripePublishableKey: 'pk_test',
            stripeMerchantDisplayName: 'Aveli',
            subscriptionsEnabled: false,
          ),
        ),
        backendAssetResolverProvider.overrideWith(
          (ref) => TestBackendAssetResolver(),
        ),
        routeSessionSnapshotProvider.overrideWithValue(session),
        teacherProfileProvider.overrideWith(
          (ref, uid) async => overrideState ?? _teacherState,
        ),
        myCertificatesProvider.overrideWith((ref) async => viewerCertificates),
      ],
      child: const MaterialApp(home: TeacherProfilePage(userId: 'teacher-1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'visar login-CTA för certifierad tjänst när användaren är utloggad',
    (tester) async {
      await _pumpPage(
        tester,
        session: _session(isAuthenticated: false),
        viewerCertificates: const [],
      );

      expect(find.text('Logga in för att boka'), findsOneWidget);
      expect(
        find.text(
          'Logga in för att boka eller för att kontrollera dina certifieringar.',
        ),
        findsOneWidget,
      );
      final buttonFinder = find.ancestor(
        of: find.text('Logga in för att boka'),
        matching: find.byType(ElevatedButton),
      );
      final button = tester.widget<ElevatedButton>(buttonFinder);
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets('låser köpknappen när verifierad certifiering saknas', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      session: _session(isAuthenticated: true),
      viewerCertificates: const [],
    );

    expect(find.text('Certifiering krävs'), findsOneWidget);
    expect(
      find.text(
        'Du behöver certifieringen "Tarot" för att boka den här tjänsten.',
      ),
      findsOneWidget,
    );
    final buttonFinder = find.ancestor(
      of: find.text('Certifiering krävs'),
      matching: find.byType(ElevatedButton),
    );
    final button = tester.widget<ElevatedButton>(buttonFinder);
    expect(button.onPressed, isNull);
  });

  testWidgets('tillåter köp när användaren har rätt verifierad certifiering', (
    tester,
  ) async {
    const cert = Certificate(
      id: 'cert-1',
      userId: 'user-1',
      title: 'Tarot',
      status: CertificateStatus.verified,
      statusRaw: 'verified',
      createdAt: null,
      updatedAt: null,
    );

    await _pumpPage(
      tester,
      session: _session(isAuthenticated: true),
      viewerCertificates: const [cert],
    );

    expect(find.text('Boka – 119.00 kr'), findsOneWidget);
    final buttonFinder = find.ancestor(
      of: find.text('Boka – 119.00 kr'),
      matching: find.byType(ElevatedButton),
    );
    final button = tester.widget<ElevatedButton>(buttonFinder);
    expect(button.onPressed, isNotNull);
    expect(
      find.text(
        'Du behöver certifieringen "Tarot" för att boka den här tjänsten.',
      ),
      findsNothing,
    );
  });

  testWidgets('visar utvalt innehåll med spelknapp', (tester) async {
    final mediaItem = TeacherProfileMediaItem(
      id: 'media-1',
      teacherId: 'teacher-1',
      mediaKind: TeacherProfileMediaKind.lessonMedia,
      mediaId: 'lesson-media-1',
      externalUrl: null,
      title: 'Guided Relaxation',
      description: '10 minuters andningsövning.',
      coverMediaId: null,
      coverImageUrl: '',
      position: 0,
      isPublished: true,
      metadata: const {},
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
      source: TeacherProfileMediaSource(
        lessonMedia: TeacherProfileLessonSource(
          id: 'lesson-media-1',
          lessonId: 'lesson-1',
          lessonTitle: 'Intro till avslappning',
          courseId: 'course-1',
          courseTitle: 'Avslappning 101',
          courseSlug: 'avslappning-101',
          kind: 'audio',
          storagePath: 'lesson-media/lesson-1/audio.mp3',
          storageBucket: 'lesson-media',
          contentType: 'audio/mpeg',
          durationSeconds: 600,
          position: 0,
          createdAt: DateTime(2025, 1, 1),
          downloadUrl: 'https://example.com/audio.mp3',
          signedUrl: 'https://example.com/audio.mp3',
          signedUrlExpiresAt: null,
        ),
      ),
    );

    final state = TeacherProfileState(
      teacher: const {
        'profile': {'display_name': 'Testlärare'},
        'headline': 'Guidning och tarot.',
      },
      services: const [],
      meditations: const [],
      certificates: const [],
      profileMedia: [mediaItem],
    );

    await _pumpPage(
      tester,
      session: _session(isAuthenticated: true),
      viewerCertificates: const [],
      overrideState: state,
    );

    final featuredTitle = find.byKey(const Key('featured_content_title'));
    await tester.scrollUntilVisible(featuredTitle, 200);
    expect(featuredTitle, findsOneWidget);
    expect(find.text('Guided Relaxation'), findsOneWidget);
    expect(find.text('Spela'), findsOneWidget);
  });
}
