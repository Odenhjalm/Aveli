import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/models/certificate.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/data/models/service.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/home/application/home_providers.dart';
import 'package:aveli/features/home/data/home_audio_repository.dart';
import 'package:aveli/features/home/presentation/home_dashboard_page.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/features/media/application/media_providers.dart';
import 'package:aveli/features/media/data/media_pipeline_repository.dart';
import 'package:aveli/features/seminars/application/seminar_providers.dart';
import 'package:aveli/shared/utils/backend_assets.dart';

import '../helpers/backend_asset_resolver_stub.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(AuthState initial)
    : super(_StubAuthRepository(), AuthHttpObserver()) {
    state = initial;
  }

  @override
  Future<void> loadSession({bool hydrateProfile = true}) async {}
}

class _StubAuthRepository implements AuthRepository {
  @override
  Future<Profile> login({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<Profile> register({
    required String email,
    required String password,
    required String displayName,
    String? inviteToken,
    String? referralCode,
  }) => throw UnimplementedError();

  @override
  Future<void> sendVerificationEmail(String email) async {}

  @override
  Future<String> validateInvite(String token) async => '';

  @override
  Future<void> verifyEmail(String token) async {}

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> resetPassword({
    required String newPassword,
    required String token,
  }) async {}

  @override
  Future<Profile> getCurrentProfile() => throw UnimplementedError();

  @override
  Future<void> completeWelcome() async {}

  @override
  Future<void> logout() async {}

  @override
  Future<String?> currentToken() async => null;
}

class _FakeMediaPipelineRepository implements MediaPipelineRepository {
  _FakeMediaPipelineRepository({this.runtimePlaybackFuture});

  final Future<String>? runtimePlaybackFuture;
  int legacyPlaybackCalls = 0;
  int lessonPlaybackCalls = 0;
  int runtimePlaybackCalls = 0;
  final List<String> requestedRuntimeMediaIds = <String>[];

  @override
  Future<MediaUploadTarget> requestUploadUrl({
    required String filename,
    required String mimeType,
    required int sizeBytes,
    required String mediaType,
    String? purpose,
    String? courseId,
    String? lessonId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MediaUploadTarget> refreshUploadUrl({required String mediaId}) {
    throw UnimplementedError();
  }

  @override
  Future<MediaStatus> completeUpload({required String mediaId}) {
    throw UnimplementedError();
  }

  @override
  Future<MediaStatus> attachUpload({
    required String mediaId,
    required String linkScope,
    String? lessonId,
    String? lessonMediaId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MediaUploadTarget> requestCoverUploadUrl({
    required String filename,
    required String mimeType,
    required int sizeBytes,
    required String courseId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CoverMediaResponse> requestCoverFromLessonMedia({
    required String courseId,
    required String lessonMediaId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> clearCourseCover(String courseId) {
    throw UnimplementedError();
  }

  @override
  Future<MediaStatus> fetchStatus(String mediaId) {
    throw UnimplementedError();
  }

  @override
  Future<MediaPlaybackUrl> fetchPlaybackUrl(String mediaId) {
    legacyPlaybackCalls += 1;
    throw UnimplementedError();
  }

  @override
  Future<String> fetchLessonPlaybackUrl(String lessonMediaId) {
    lessonPlaybackCalls += 1;
    throw UnimplementedError();
  }

  @override
  Future<String> fetchRuntimePlaybackUrl(String runtimeMediaId) {
    runtimePlaybackCalls += 1;
    requestedRuntimeMediaIds.add(runtimeMediaId);
    return runtimePlaybackFuture ??
        Future.value('https://cdn.test/runtime.mp3');
  }
}

final _testProfile = Profile(
  id: 'user-1',
  email: 'user@test.local',
  userRole: UserRole.user,
  isAdmin: false,
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 1),
);

HomeAudioItem _audioItem({
  required String id,
  required String title,
  required String runtimeMediaId,
  required bool isPlayable,
  required String playbackState,
  required String failureReason,
  String kind = 'audio',
  String? contentType = 'audio/mpeg',
  String sourceType = 'course_link',
  String? lessonId,
  String? courseId = 'course-1',
  String courseTitle = 'Course 1',
}) {
  return HomeAudioItem(
    id: id,
    lessonId: lessonId ?? 'lesson-$id',
    lessonTitle: title,
    courseId: courseId,
    courseTitle: courseTitle,
    sourceType: sourceType,
    kind: kind,
    contentType: contentType,
    runtimeMediaId: runtimeMediaId,
    isPlayable: isPlayable,
    playbackState: playbackState,
    failureReason: failureReason,
  );
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required List<HomeAudioItem> audioItems,
  required MediaPipelineRepository mediaPipelineRepository,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: AppRoute.home,
        builder: (context, state) => const HomeDashboardPage(),
      ),
      GoRoute(
        path: '/login',
        name: AppRoute.login,
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: '/services/:id',
        name: AppRoute.serviceDetail,
        builder: (context, state) => const SizedBox.shrink(),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(AuthState(profile: _testProfile)),
        ),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'https://api.test',
            stripePublishableKey: '',
            stripeMerchantDisplayName: 'Test',
            subscriptionsEnabled: false,
          ),
        ),
        backendAssetResolverProvider.overrideWith(
          (ref) => TestBackendAssetResolver(),
        ),
        mediaPipelineRepositoryProvider.overrideWithValue(
          mediaPipelineRepository,
        ),
        homeFeedProvider.overrideWith((ref) async => const []),
        homeServicesProvider.overrideWith((ref) async => const <Service>[]),
        homeAudioProvider.overrideWith((ref) async => audioItems),
        landing.popularCoursesProvider.overrideWith(
          (ref) async => const landing.LandingSectionState(items: []),
        ),
        publicSeminarsProvider.overrideWith((ref) async => const []),
        myCertificatesProvider.overrideWith(
          (ref) async => const <Certificate>[],
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  for (var i = 0; i < 5; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets(
    'home dashboard keeps all runtime rows visible and shows processing state',
    (tester) async {
      final repo = _FakeMediaPipelineRepository();
      final items = <HomeAudioItem>[
        _audioItem(
          id: 'runtime-row-1',
          title: 'Bearbetas nu',
          runtimeMediaId: 'runtime-media-1',
          isPlayable: false,
          playbackState: 'processing',
          failureReason: 'asset_not_ready',
        ),
        _audioItem(
          id: 'runtime-row-2',
          title: 'Klar att spela',
          runtimeMediaId: 'runtime-media-2',
          isPlayable: true,
          playbackState: 'ready',
          failureReason: 'ok_ready_asset',
        ),
        _audioItem(
          id: 'runtime-row-3',
          title: 'Videospår',
          runtimeMediaId: 'runtime-media-3',
          isPlayable: true,
          playbackState: 'ready',
          failureReason: 'ok_ready_asset',
          sourceType: 'direct_upload',
          lessonId: null,
          courseId: null,
          courseTitle: '',
          kind: 'video',
          contentType: 'video/mp4',
        ),
      ];

      await _pumpDashboard(
        tester,
        audioItems: items,
        mediaPipelineRepository: repo,
      );

      await tester.tap(find.byTooltip('Bibliotek').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('3 spår'), findsOneWidget);
      expect(find.text('Bearbetas nu'), findsWidgets);
      expect(find.text('Klar att spela'), findsWidgets);
      expect(find.text('Videospår'), findsWidgets);

      await tester.tap(find.text('Bearbetas nu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Ljudet bearbetas…'), findsOneWidget);
      expect(find.byTooltip('Spela'), findsOneWidget);
    },
  );

  testWidgets('home dashboard resolves playback through runtime media only', (
    tester,
  ) async {
    final pendingPlayback = Completer<String>();
    final repo = _FakeMediaPipelineRepository(
      runtimePlaybackFuture: pendingPlayback.future,
    );

    await _pumpDashboard(
      tester,
      audioItems: <HomeAudioItem>[
        _audioItem(
          id: 'runtime-row-1',
          title: 'Spelbart spår',
          runtimeMediaId: 'runtime-media-1',
          isPlayable: true,
          playbackState: 'ready',
          failureReason: 'ok_ready_asset',
        ),
      ],
      mediaPipelineRepository: repo,
    );

    await tester.tap(find.byTooltip('Spela'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.runtimePlaybackCalls, 1);
    expect(repo.requestedRuntimeMediaIds, <String>['runtime-media-1']);
    expect(repo.legacyPlaybackCalls, 0);
    expect(repo.lessonPlaybackCalls, 0);
  });
}
