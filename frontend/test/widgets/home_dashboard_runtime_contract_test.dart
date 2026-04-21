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
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/home/application/home_audio_controller.dart';
import 'package:aveli/features/home/data/home_audio_repository.dart';
import 'package:aveli/features/home/presentation/home_dashboard_page.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/shared/widgets/inline_audio_player.dart';
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

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required HomeAudioRepository homeAudioRepository,
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

  await tester.pumpWidget(
    ProviderScope(
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
        homeAudioRepositoryProvider.overrideWithValue(homeAudioRepository),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  for (var i = 0; i < 6; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('home dashboard mounts learner home audio from GET /home/audio', (
    tester,
  ) async {
    final harness = await _Harness.create();
    final repository = HomeAudioRepository(harness.client);

    await _pumpDashboard(tester, homeAudioRepository: repository);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.adapter.requestsFor('/home/audio'), hasLength(1));
    expect(find.text('Ljud i Home-spelaren'), findsOneWidget);
    expect(find.text('Kvällsmeditation'), findsOneWidget);
    expect(find.text('Andning del 1'), findsOneWidget);
    expect(find.text('Redo att spela'), findsOneWidget);
    expect(find.text('Ljudet bearbetas.'), findsOneWidget);
    expect(find.text('Utforska kurser'), findsOneWidget);
    expect(find.text('Gemensam vägg'), findsNothing);
    expect(find.text('Tjänster'), findsNothing);

    await tester.tap(find.byTooltip('Redo att spela'));
    await tester.pump();

    final player = tester.widget<InlineAudioPlayer>(
      find.byType(InlineAudioPlayer),
    );
    expect(player.url, 'https://cdn.test/audio/evening.mp3');
  });
}

class _Harness {
  _Harness({required this.client, required this.adapter});

  final ApiClient client;
  final _RecordingAdapter adapter;

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
