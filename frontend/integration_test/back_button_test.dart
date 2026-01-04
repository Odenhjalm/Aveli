import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:wisdom/api/auth_repository.dart';
import 'package:wisdom/core/auth/auth_controller.dart';
import 'package:wisdom/core/auth/auth_http_observer.dart';
import 'package:wisdom/core/env/app_config.dart';
import 'package:wisdom/core/env/env_state.dart';
import 'package:wisdom/core/routing/app_routes.dart';
import 'package:wisdom/core/routing/app_router.dart';
import 'package:wisdom/data/models/activity.dart';
import 'package:wisdom/data/models/profile.dart';
import 'package:wisdom/data/models/service.dart';
import 'package:wisdom/features/community/application/community_providers.dart';
import 'package:wisdom/features/community/presentation/community_page.dart';
import 'package:wisdom/features/home/application/home_providers.dart';
import 'package:wisdom/features/home/presentation/home_dashboard_page.dart';
import 'package:wisdom/features/landing/application/landing_providers.dart'
    as landing;
import 'package:wisdom/main.dart';

const _transparentPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

class _FakeAuthController extends AuthController {
  _FakeAuthController(AuthState initialState)
    : super(
        _FakeAuthRepository(
          profile: initialState.profile,
          token: initialState.profile != null || initialState.claims != null
              ? 'token'
              : null,
        ),
        AuthHttpObserver(),
      ) {
    state = initialState;
  }

  @override
  Future<void> loadSession() async {}
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.profile, this.token});

  final Profile? profile;
  final String? token;

  @override
  Future<Profile> login({required String email, required String password}) {
    throw UnsupportedError('Not implemented for tests');
  }

  @override
  Future<Profile> register({
    required String email,
    required String password,
    required String displayName,
  }) {
    throw UnsupportedError('Not implemented for tests');
  }

  @override
  Future<void> requestPasswordReset(String email) {
    throw UnsupportedError('Not implemented for tests');
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String newPassword,
  }) {
    throw UnsupportedError('Not implemented for tests');
  }

  @override
  Future<Profile> getCurrentProfile() async {
    if (profile == null) {
      throw UnsupportedError('No profile available for test');
    }
    return profile!;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<String?> currentToken() async => token;
}

List<Override> _commonOverrides(AuthState authState) {
  return [
    envInfoProvider.overrideWith((ref) => envInfoOk),
    authControllerProvider.overrideWith(
      (ref) => _FakeAuthController(authState),
    ),
    appConfigProvider.overrideWithValue(
      const AppConfig(
        apiBaseUrl: 'http://localhost',
        stripePublishableKey: 'pk_test',
        stripeMerchantDisplayName: 'Aveli',
        subscriptionsEnabled: false,
      ),
    ),
    homeFeedProvider.overrideWith((ref) => Future.value(const <Activity>[])),
    homeServicesProvider.overrideWith((ref) => Future.value(const <Service>[])),
    landing.popularCoursesProvider.overrideWith(
      (ref) => Future.value(const landing.LandingSectionState(items: [])),
    ),
    communityServicesProvider.overrideWith(
      (ref) => Future.value(const <Service>[]),
    ),
  ];
}

Future<void> _pumpNavigation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  final transparentData = ByteData.view(
    Uint8List.fromList(_transparentPng).buffer,
  );

  binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
    message,
  ) async {
    final key = const StringCodec().decodeMessage(message) ?? '';
    if (key == 'AssetManifest.json') {
      return ByteData.view(Uint8List.fromList(utf8.encode('{}')).buffer);
    }
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, dynamic>{});
    }
    if (key == 'FontManifest.json') {
      return ByteData.view(Uint8List.fromList(utf8.encode('[]')).buffer);
    }
    if (key == 'NOTICES' || key == 'LICENSES') {
      return ByteData.view(Uint8List.fromList(utf8.encode('')).buffer);
    }
    return transparentData;
  });

  testWidgets('Android back pops to previous route instead of exiting', (
    tester,
  ) async {
    final profile = Profile(
      id: 'user-1',
      email: 'user@example.com',
      userRole: UserRole.teacher,
      isAdmin: false,
      createdAt: DateTime.utc(2024, 1, 1),
      updatedAt: DateTime.utc(2024, 1, 1),
      displayName: 'Test User',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(AuthState(profile: profile)),
        child: const WisdomApp(),
      ),
    );

    await _pumpNavigation(tester);
    expect(find.byType(HomeDashboardPage), findsOneWidget);

    // Navigate to Community via router (avoids layout-specific buttons).
    final appContext = tester.element(find.byType(MaterialApp));
    final container = ProviderScope.containerOf(appContext);
    final router = container.read(appRouterProvider);
    router.pushNamed(AppRoute.community);
    await _pumpNavigation(tester);
    expect(find.byType(CommunityPage), findsOneWidget);

    // Simulate a back action by popping the current route.
    router.pop();
    await _pumpNavigation(tester);

    expect(find.byType(HomeDashboardPage), findsOneWidget);
    expect(find.byType(CommunityPage), findsNothing);
  });
}
