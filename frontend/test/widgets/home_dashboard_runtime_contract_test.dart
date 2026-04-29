import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/data/notifications_repository.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/home/application/home_audio_controller.dart';
import 'package:aveli/features/home/application/home_audio_session_controller.dart';
import 'package:aveli/features/home/data/home_audio_repository.dart';
import 'package:aveli/features/home/presentation/home_dashboard_page.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/shared/utils/backend_assets.dart';
import 'package:aveli/shared/widgets/inline_audio_player.dart';

import '../helpers/backend_asset_resolver_stub.dart';
import '../helpers/fake_home_audio_engine.dart';

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
  Future<Profile> register({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<void> sendVerificationEmail(String email) async {}

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
  Future<Profile> createProfile({required String displayName, String? bio}) =>
      throw UnimplementedError();

  @override
  Future<void> completeWelcome() async {}

  @override
  Future<void> redeemReferral({required String code}) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<String?> currentToken() async => null;
}

final _testProfile = Profile(
  id: 'user-1',
  email: 'user@test.local',
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 1),
);

Future<ProviderContainer> _pumpDashboard(
  WidgetTester tester, {
  required HomeAudioRepository homeAudioRepository,
  required FakeHomeAudioEngineFactory engineFactory,
  NotificationsReadModel notificationsReadModel = const NotificationsReadModel(
    showNotificationsBar: false,
    notifications: [],
  ),
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
    ],
  );

  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(
        (ref) => _FakeAuthController(AuthState(profile: _testProfile)),
      ),
      appConfigProvider.overrideWithValue(
        const AppConfig(
          apiBaseUrl: 'https://api.test',
          subscriptionsEnabled: false,
        ),
      ),
      backendAssetResolverProvider.overrideWith(
        (ref) => TestBackendAssetResolver(),
      ),
      coursesProvider.overrideWith((ref) async => const []),
      landing.popularCoursesProvider.overrideWith(
        (ref) async => const landing.LandingSection<CourseSummary>(items: []),
      ),
      notificationsProvider.overrideWith((ref) async => notificationsReadModel),
      homeAudioRepositoryProvider.overrideWithValue(homeAudioRepository),
      homeAudioEngineFactoryProvider.overrideWithValue(engineFactory.create),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  for (var i = 0; i < 6; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return container;
}

void main() {
  testWidgets('home dashboard renders minimalist learner home player shell', (
    tester,
  ) async {
    final harness = await _Harness.create();
    final repository = HomeAudioRepository(harness.client);
    final engineFactory = FakeHomeAudioEngineFactory();

    final container = await _pumpDashboard(
      tester,
      homeAudioRepository: repository,
      engineFactory: engineFactory,
    );
    addTearDown(container.dispose);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.adapter.requestsFor('/home/audio'), hasLength(1));
    expect(engineFactory.createCount, 1);
    expect(find.byKey(const ValueKey('home-audio-logo')), findsOneWidget);
    _expectHomeAudioLogoUrl(
      tester,
      'https://storage.test/storage/v1/object/public/public-media/home-player/logos/v1/homeplayer_logo_closed.png',
    );
    expect(
      find.byKey(const ValueKey('home-audio-track-list-toggle')),
      findsOneWidget,
    );
    expect(find.byType(InlineAudioPlayerView), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-player-play-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-player-position-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-player-volume-slider')),
      findsOneWidget,
    );
    expect(find.text('Ljud i Home-spelaren'), findsNothing);
    expect(find.text('Redo att spela'), findsNothing);
    expect(find.text('Ljudet bearbetas.'), findsNothing);
    expect(find.text('Kvällsmeditation'), findsNothing);
    expect(find.text('Morgonandning'), findsNothing);
    expect(find.text('Andning del 1'), findsNothing);
    expect(find.text('Utforska kurser'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notifications-header-strip')),
      findsNothing,
    );
    expect(find.text('Gemensam vägg'), findsNothing);
    expect(find.text('Tjänster'), findsNothing);

    expect(
      engineFactory.single.loadedUrls,
      orderedEquals(['https://cdn.test/audio/evening.mp3']),
    );
    expect(container.read(homeAudioSessionControllerProvider).currentIndex, 0);

    await tester.tap(find.byKey(const ValueKey('home-audio-logo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const ValueKey('home-audio-track-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-audio-logo')), findsOneWidget);
    _expectHomeAudioLogoUrl(
      tester,
      'https://storage.test/storage/v1/object/public/public-media/home-player/logos/v1/homeplayer_logo_open.png',
    );
    expect(find.byKey(const ValueKey('home-audio-track-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-audio-track-1')), findsOneWidget);
    expect(find.text('Kvällsmeditation'), findsOneWidget);
    expect(find.text('Morgonandning'), findsOneWidget);
    expect(find.text('Andning del 1'), findsNothing);
    final logoRect = tester.getRect(
      find.byKey(const ValueKey('home-audio-logo')),
    );
    final listRect = tester.getRect(
      find.byKey(const ValueKey('home-audio-track-list')),
    );
    expect(listRect.left, greaterThan(logoRect.right));

    final volumeSliderFinder = find.byKey(
      const ValueKey('home-player-volume-slider'),
    );
    final volumeSlider = tester.widget<Slider>(volumeSliderFinder);
    volumeSlider.onChanged!(0.35);
    await tester.pump();

    expect(
      container.read(homeAudioSessionControllerProvider).volume,
      closeTo(0.35, 0.0001),
    );
    expect(engineFactory.single.volumeHistory.last, closeTo(0.35, 0.0001));

    await tester.tap(find.byKey(const ValueKey('home-player-play-button')));
    await tester.pump();

    expect(
      container.read(homeAudioSessionControllerProvider).isPlaying,
      isTrue,
    );
    expect(engineFactory.single.playCalls, 1);

    await tester.tap(find.byKey(const ValueKey('home-audio-track-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final updatedState = container.read(homeAudioSessionControllerProvider);
    expect(updatedState.currentIndex, 1);
    expect(updatedState.isPlaying, isTrue);
    expect(engineFactory.createCount, 1);
    expect(
      engineFactory.single.loadedUrls.last,
      'https://cdn.test/audio/morning.mp3',
    );
    expect(engineFactory.single.playCalls, greaterThanOrEqualTo(2));
    expect(updatedState.volume, closeTo(0.35, 0.0001));
    final updatedVolumeSlider = tester.widget<Slider>(volumeSliderFinder);
    expect(updatedVolumeSlider.value, closeTo(0.35, 0.0001));

    await tester.tap(
      find.byKey(const ValueKey('home-audio-track-list-toggle')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.byKey(const ValueKey('home-audio-track-list-hidden')),
      findsOneWidget,
    );
    expect(find.text('Kvällsmeditation'), findsNothing);
    expect(find.text('Morgonandning'), findsNothing);
    expect(engineFactory.createCount, 1);
  });

  testWidgets('home player track list scrolls within a constrained area', (
    tester,
  ) async {
    final items = List<Map<String, Object?>>.generate(18, (index) {
      return _simpleHomeAudioItem(
        title: 'Track ${index + 1}',
        mediaId: 'media-${index + 1}',
        resolvedUrl: 'https://cdn.test/audio/track-${index + 1}.mp3',
        createdAt: '2026-04-22T10:${index.toString().padLeft(2, '0')}:00Z',
      );
    });
    final harness = await _Harness.createWithHomeAudioHandler(
      (_) => _jsonResponse(statusCode: 200, body: _simpleHomeAudioBody(items)),
    );
    final repository = HomeAudioRepository(harness.client);
    final engineFactory = FakeHomeAudioEngineFactory();

    final container = await _pumpDashboard(
      tester,
      homeAudioRepository: repository,
      engineFactory: engineFactory,
    );
    addTearDown(container.dispose);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('home-audio-logo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final listFinder = find.byKey(const ValueKey('home-audio-track-list'));
    final scrollFinder = find.byKey(
      const ValueKey('home-audio-track-list-scroll'),
    );
    expect(listFinder, findsOneWidget);
    expect(scrollFinder, findsOneWidget);
    expect(tester.getRect(listFinder).height, lessThanOrEqualTo(250));
    expect(
      find.descendant(of: listFinder, matching: find.byType(Scrollable)),
      findsOneWidget,
    );

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('home-audio-track-17')),
      scrollFinder,
      const Offset(0, -120),
      maxIteration: 12,
    );

    expect(find.byKey(const ValueKey('home-audio-track-17')), findsOneWidget);
  });

  testWidgets('home dashboard renders notifications only in the header slot', (
    tester,
  ) async {
    final harness = await _Harness.create();
    final repository = HomeAudioRepository(harness.client);
    final engineFactory = FakeHomeAudioEngineFactory();

    final container = await _pumpDashboard(
      tester,
      homeAudioRepository: repository,
      engineFactory: engineFactory,
      notificationsReadModel: const NotificationsReadModel(
        showNotificationsBar: true,
        notifications: [
          NotificationHeaderItem(
            id: 'notification-1',
            title: 'Backend title',
            subtitle: 'Backend subtitle',
            ctaLabel: 'Backend CTA',
            ctaUrl: '/lesson/backend-lesson',
          ),
        ],
      ),
    );
    addTearDown(container.dispose);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('notifications-header-strip')),
      findsOneWidget,
    );
    expect(find.text('Backend title'), findsOneWidget);
    expect(find.text('Backend subtitle'), findsOneWidget);
    expect(find.text('Backend CTA'), findsOneWidget);
  });

  testWidgets(
    'home dashboard renders no notification shell when backend hides it',
    (tester) async {
      final harness = await _Harness.create();
      final repository = HomeAudioRepository(harness.client);
      final engineFactory = FakeHomeAudioEngineFactory();

      final container = await _pumpDashboard(
        tester,
        homeAudioRepository: repository,
        engineFactory: engineFactory,
        notificationsReadModel: const NotificationsReadModel(
          showNotificationsBar: false,
          notifications: [
            NotificationHeaderItem(
              id: 'notification-1',
              title: 'Hidden backend title',
              subtitle: 'Hidden backend subtitle',
              ctaLabel: 'Hidden backend CTA',
              ctaUrl: '/lesson/hidden-backend-lesson',
            ),
          ],
        ),
      );
      addTearDown(container.dispose);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('notifications-header-strip')),
        findsNothing,
      );
      expect(find.text('Hidden backend title'), findsNothing);
      expect(find.text('Hidden backend subtitle'), findsNothing);
      expect(find.text('Hidden backend CTA'), findsNothing);
    },
  );

  testWidgets(
    'provider refresh stages a new candidate while the dashboard keeps rendering the frozen session list',
    (tester) async {
      var homeAudioStatus = 200;
      var homeAudioBody = _simpleHomeAudioBody([
        _simpleHomeAudioItem(
          title: 'Active One',
          mediaId: 'media-1',
          resolvedUrl: 'https://cdn.test/audio/active-one.mp3',
          createdAt: '2026-04-22T11:00:00Z',
        ),
        _simpleHomeAudioItem(
          title: 'Active Two',
          mediaId: 'media-2',
          resolvedUrl: 'https://cdn.test/audio/active-two.mp3',
          createdAt: '2026-04-22T10:00:00Z',
        ),
      ]);

      final harness = await _Harness.createWithHomeAudioHandler(
        (_) => _jsonResponse(statusCode: homeAudioStatus, body: homeAudioBody),
      );
      final repository = HomeAudioRepository(harness.client);
      final engineFactory = FakeHomeAudioEngineFactory();

      final container = await _pumpDashboard(
        tester,
        homeAudioRepository: repository,
        engineFactory: engineFactory,
      );
      addTearDown(container.dispose);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const ValueKey('home-player-play-button')));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('home-audio-track-list-toggle')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Active One'), findsOneWidget);
      expect(find.text('Active Two'), findsOneWidget);

      homeAudioBody = _simpleHomeAudioBody([
        _simpleHomeAudioItem(
          title: 'Refresh Lead',
          mediaId: 'media-9',
          resolvedUrl: 'https://cdn.test/audio/refresh-lead.mp3',
          createdAt: '2026-04-22T12:00:00Z',
        ),
        _simpleHomeAudioItem(
          title: 'Refresh Tail',
          mediaId: 'media-10',
          resolvedUrl: 'https://cdn.test/audio/refresh-tail.mp3',
          createdAt: '2026-04-22T11:30:00Z',
        ),
      ]);

      await tester.runAsync(
        () => container.read(homeAudioProvider.notifier).refresh(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final state = container.read(homeAudioSessionControllerProvider);
      expect(state.isPlaying, isTrue);
      expect(state.currentIndex, 0);
      expect(
        state.queue.map((entry) => entry.title),
        orderedEquals(['Active One', 'Active Two']),
      );
      expect(state.hasStagedSnapshot, isTrue);
      expect(
        state.stagedQueue.map((entry) => entry.title),
        orderedEquals(['Refresh Lead', 'Refresh Tail']),
      );
      expect(find.text('Active One'), findsOneWidget);
      expect(find.text('Active Two'), findsOneWidget);
      expect(find.text('Refresh Lead'), findsNothing);
      expect(find.text('Refresh Tail'), findsNothing);
      expect(engineFactory.createCount, 1);
      expect(
        engineFactory.single.loadedUrls,
        orderedEquals(['https://cdn.test/audio/active-one.mp3']),
      );
    },
  );

  testWidgets(
    'provider refresh failure during an active session does not interrupt the dashboard player',
    (tester) async {
      var homeAudioStatus = 200;
      var homeAudioBody = _simpleHomeAudioBody([
        _simpleHomeAudioItem(
          title: 'Stable One',
          mediaId: 'media-1',
          resolvedUrl: 'https://cdn.test/audio/stable-one.mp3',
          createdAt: '2026-04-22T11:00:00Z',
        ),
        _simpleHomeAudioItem(
          title: 'Stable Two',
          mediaId: 'media-2',
          resolvedUrl: 'https://cdn.test/audio/stable-two.mp3',
          createdAt: '2026-04-22T10:00:00Z',
        ),
      ]);

      final harness = await _Harness.createWithHomeAudioHandler(
        (_) => _jsonResponse(statusCode: homeAudioStatus, body: homeAudioBody),
      );
      final repository = HomeAudioRepository(harness.client);
      final engineFactory = FakeHomeAudioEngineFactory();

      final container = await _pumpDashboard(
        tester,
        homeAudioRepository: repository,
        engineFactory: engineFactory,
      );
      addTearDown(container.dispose);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const ValueKey('home-player-play-button')));
      await tester.pump();

      homeAudioStatus = 500;
      homeAudioBody = {'detail': 'refresh failed'};

      await tester.runAsync(
        () => container.read(homeAudioProvider.notifier).refresh(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final state = container.read(homeAudioSessionControllerProvider);
      expect(container.read(homeAudioProvider).hasError, isTrue);
      expect(state.isPlaying, isTrue);
      expect(state.currentIndex, 0);
      expect(
        state.queue.map((entry) => entry.title),
        orderedEquals(['Stable One', 'Stable Two']),
      );
      expect(find.byType(InlineAudioPlayerView), findsOneWidget);
      expect(find.byKey(const ValueKey('home-audio-error')), findsNothing);
      expect(engineFactory.createCount, 1);
      expect(
        engineFactory.single.loadedUrls,
        orderedEquals(['https://cdn.test/audio/stable-one.mp3']),
      );
    },
  );
}

class _Harness {
  _Harness({required this.client, required this.adapter});

  final ApiClient client;
  final _RecordingAdapter adapter;

  static Future<_Harness> createWithHomeAudioHandler(
    ResponseBody Function(RequestOptions options) homeAudioHandler,
  ) async {
    final storage = _MemoryFlutterSecureStorage();
    final tokens = TokenStorage(storage: storage);
    await tokens.saveTokens(
      accessToken: _jwtWithExpSeconds(4102444800),
      refreshToken: 'rt-1',
    );

    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:1',
      tokenStorage: tokens,
    );
    final adapter = _RecordingAdapter((options) {
      if (options.path == '/home/audio' &&
          options.method.toUpperCase() == 'GET') {
        return homeAudioHandler(options);
      }
      return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
    });
    client.raw.httpClientAdapter = adapter;
    return _Harness(client: client, adapter: adapter);
  }

  static Future<_Harness> create() async {
    final storage = _MemoryFlutterSecureStorage();
    final tokens = TokenStorage(storage: storage);
    await tokens.saveTokens(
      accessToken: _jwtWithExpSeconds(4102444800),
      refreshToken: 'rt-1',
    );

    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:1',
      tokenStorage: tokens,
    );
    final adapter = _RecordingAdapter((options) {
      if (options.path == '/home/audio' &&
          options.method.toUpperCase() == 'GET') {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'items': [
              {
                'source_type': 'direct_upload',
                'title': 'Kvällsmeditation',
                'lesson_title': null,
                'course_id': null,
                'course_title': null,
                'course_slug': null,
                'teacher_id': 'teacher-1',
                'teacher_name': 'Aveli Teacher',
                'created_at': '2026-04-21T10:00:00Z',
                'media': {
                  'media_id': 'media-1',
                  'state': 'ready',
                  'resolved_url': 'https://cdn.test/audio/evening.mp3',
                },
              },
              {
                'source_type': 'course_link',
                'title': 'Morgonandning',
                'lesson_title': 'Lektion 2',
                'course_id': 'course-2',
                'course_title': 'Andning',
                'course_slug': 'andning',
                'teacher_id': 'teacher-2',
                'teacher_name': 'Aveli Course Teacher',
                'created_at': '2026-04-21T09:30:00Z',
                'media': {
                  'media_id': 'media-3',
                  'state': 'ready',
                  'resolved_url': 'https://cdn.test/audio/morning.mp3',
                },
              },
              {
                'source_type': 'course_link',
                'title': 'Andning del 1',
                'lesson_title': 'Lektion 1',
                'course_id': 'course-1',
                'course_title': 'Andning',
                'course_slug': 'andning',
                'teacher_id': 'teacher-2',
                'teacher_name': 'Aveli Course Teacher',
                'created_at': '2026-04-21T09:00:00Z',
                'media': {
                  'media_id': 'media-2',
                  'state': 'processing',
                  'resolved_url': null,
                },
              },
            ],
            'homeplayer_logo': _homeplayerLogoPayload(),
            'text_bundle': {
              'home.audio.section_title': {
                'surface_id': 'TXT-SURF-076',
                'text_id': 'home.audio.section_title',
                'authority_class': 'contract_text',
                'canonical_owner': 'backend_text_catalog',
                'source_contract':
                    'actual_truth/contracts/backend_text_catalog_contract.md',
                'backend_namespace': 'backend_text_catalog.home',
                'api_surface': '/home/audio',
                'delivery_surface': '/home/audio',
                'render_surface':
                    'frontend/lib/features/home/presentation/widgets/home_audio_section.dart',
                'language': 'sv',
                'interpolation_keys': const [],
                'forbidden_render_fields': const [],
                'value': 'Ljud i Home-spelaren',
              },
              'home.audio.section_description': {
                'surface_id': 'TXT-SURF-076',
                'text_id': 'home.audio.section_description',
                'authority_class': 'contract_text',
                'canonical_owner': 'backend_text_catalog',
                'source_contract':
                    'actual_truth/contracts/backend_text_catalog_contract.md',
                'backend_namespace': 'backend_text_catalog.home',
                'api_surface': '/home/audio',
                'delivery_surface': '/home/audio',
                'render_surface':
                    'frontend/lib/features/home/presentation/widgets/home_audio_section.dart',
                'language': 'sv',
                'interpolation_keys': const [],
                'forbidden_render_fields': const [],
                'value':
                    'Dina uppladdningar och kurslänkar visas här när de är tillgängliga.',
              },
              'home.audio.direct_upload_label': {
                'surface_id': 'TXT-SURF-076',
                'text_id': 'home.audio.direct_upload_label',
                'authority_class': 'contract_text',
                'canonical_owner': 'backend_text_catalog',
                'source_contract':
                    'actual_truth/contracts/backend_text_catalog_contract.md',
                'backend_namespace': 'backend_text_catalog.home',
                'api_surface': '/home/audio',
                'delivery_surface': '/home/audio',
                'render_surface':
                    'frontend/lib/features/home/presentation/widgets/home_audio_section.dart',
                'language': 'sv',
                'interpolation_keys': const [],
                'forbidden_render_fields': const [],
                'value': 'Ditt ljud',
              },
              'home.audio.course_link_label': {
                'surface_id': 'TXT-SURF-076',
                'text_id': 'home.audio.course_link_label',
                'authority_class': 'contract_text',
                'canonical_owner': 'backend_text_catalog',
                'source_contract':
                    'actual_truth/contracts/backend_text_catalog_contract.md',
                'backend_namespace': 'backend_text_catalog.home',
                'api_surface': '/home/audio',
                'delivery_surface': '/home/audio',
                'render_surface':
                    'frontend/lib/features/home/presentation/widgets/home_audio_section.dart',
                'language': 'sv',
                'interpolation_keys': const [],
                'forbidden_render_fields': const [],
                'value': 'Från kurs',
              },
              'home.audio.processing_status': {
                'surface_id': 'TXT-SURF-076',
                'text_id': 'home.audio.processing_status',
                'authority_class': 'backend_status_text',
                'canonical_owner': 'backend_text_catalog',
                'source_contract':
                    'actual_truth/contracts/backend_text_catalog_contract.md',
                'backend_namespace': 'backend_text_catalog.home',
                'api_surface': '/home/audio',
                'delivery_surface': '/home/audio',
                'render_surface':
                    'frontend/lib/features/home/presentation/widgets/home_audio_section.dart',
                'language': 'sv',
                'interpolation_keys': const [],
                'forbidden_render_fields': const [],
                'value': 'Ljudet bearbetas.',
              },
              'home.audio.ready_status': {
                'surface_id': 'TXT-SURF-076',
                'text_id': 'home.audio.ready_status',
                'authority_class': 'backend_status_text',
                'canonical_owner': 'backend_text_catalog',
                'source_contract':
                    'actual_truth/contracts/backend_text_catalog_contract.md',
                'backend_namespace': 'backend_text_catalog.home',
                'api_surface': '/home/audio',
                'delivery_surface': '/home/audio',
                'render_surface':
                    'frontend/lib/features/home/presentation/widgets/home_audio_section.dart',
                'language': 'sv',
                'interpolation_keys': const [],
                'forbidden_render_fields': const [],
                'value': 'Redo att spela',
              },
              'home.audio.retry_action': {
                'surface_id': 'TXT-SURF-076',
                'text_id': 'home.audio.retry_action',
                'authority_class': 'contract_text',
                'canonical_owner': 'backend_text_catalog',
                'source_contract':
                    'actual_truth/contracts/backend_text_catalog_contract.md',
                'backend_namespace': 'backend_text_catalog.home',
                'api_surface': '/home/audio',
                'delivery_surface': '/home/audio',
                'render_surface':
                    'frontend/lib/features/home/presentation/widgets/home_audio_section.dart',
                'language': 'sv',
                'interpolation_keys': const [],
                'forbidden_render_fields': const [],
                'value': 'Försök igen',
              },
            },
          },
        );
      }
      return _jsonResponse(statusCode: 500, body: {'detail': 'unexpected'});
    });
    client.raw.httpClientAdapter = adapter;
    return _Harness(client: client, adapter: adapter);
  }
}

Map<String, Object?> _simpleHomeAudioBody(List<Map<String, Object?>> items) {
  return {
    'items': items,
    'homeplayer_logo': _homeplayerLogoPayload(),
    'text_bundle': const <String, Object?>{},
  };
}

Map<String, Object?> _homeplayerLogoPayload() {
  return const {
    'closed': {
      'asset_key': 'homeplayer_logo_closed',
      'resolved_url':
          'https://storage.test/storage/v1/object/public/public-media/home-player/logos/v1/homeplayer_logo_closed.png',
    },
    'open': {
      'asset_key': 'homeplayer_logo_open',
      'resolved_url':
          'https://storage.test/storage/v1/object/public/public-media/home-player/logos/v1/homeplayer_logo_open.png',
    },
  };
}

void _expectHomeAudioLogoUrl(WidgetTester tester, String expectedUrl) {
  final image = tester.widget<Image>(
    find.descendant(
      of: find.byKey(const ValueKey('home-audio-logo')),
      matching: find.byType(Image),
    ),
  );
  expect(image.image, isA<NetworkImage>());
  expect((image.image as NetworkImage).url, expectedUrl);
}

Map<String, Object?> _simpleHomeAudioItem({
  required String title,
  required String mediaId,
  required String resolvedUrl,
  required String createdAt,
}) {
  return {
    'source_type': 'direct_upload',
    'title': title,
    'lesson_title': null,
    'course_id': null,
    'course_title': null,
    'course_slug': null,
    'teacher_id': 'teacher-1',
    'teacher_name': 'Aveli Teacher',
    'created_at': createdAt,
    'media': {
      'media_id': mediaId,
      'state': 'ready',
      'resolved_url': resolvedUrl,
    },
  };
}

ResponseBody _jsonResponse({
  required int statusCode,
  required Map<String, Object?> body,
}) {
  return ResponseBody.fromString(
    json.encode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

String _jwtWithExpSeconds(int expSeconds) {
  final header = base64Url.encode(utf8.encode(json.encode({'alg': 'HS256'})));
  final payload = base64Url.encode(
    utf8.encode(json.encode({'exp': expSeconds})),
  );
  return '$header.$payload.signature';
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._handler);

  final ResponseBody Function(RequestOptions options) _handler;
  final List<_RecordedRequest> _requests = <_RecordedRequest>[];

  List<_RecordedRequest> requestsFor(String path) => _requests
      .where((request) => request.path == path)
      .toList(growable: false);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _requests.add(
      _RecordedRequest(
        path: options.path,
        method: options.method.toUpperCase(),
        data: options.data,
      ),
    );
    return _handler(options);
  }
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.path,
    required this.method,
    required this.data,
  });

  final String path;
  final String method;
  final Object? data;
}

class _MemoryFlutterSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    _values.clear();
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    return Map<String, String>.from(_values);
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    return _values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }
}
