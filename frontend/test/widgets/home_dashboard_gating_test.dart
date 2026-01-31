import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/bootstrap/auth_boot_page.dart';
import 'package:aveli/data/models/certificate.dart';
import 'package:aveli/data/models/service.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/home/application/home_providers.dart';
import 'package:aveli/features/home/presentation/home_dashboard_page.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
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
  }) => throw UnimplementedError();

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> resetPassword({
    required String email,
    required String newPassword,
  }) async {}

  @override
  Future<Profile> getCurrentProfile() => throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<String?> currentToken() async => null;
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required List<Service> services,
  required List<Certificate> certificates,
  required AuthState authState,
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
          (ref) => _FakeAuthController(authState),
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
        homeFeedProvider.overrideWith((ref) async => const []),
        homeServicesProvider.overrideWith((ref) async => services),
        homeAudioProvider.overrideWith((ref) async => const []),
        landing.popularCoursesProvider.overrideWith(
          (ref) async => const landing.LandingSectionState(items: []),
        ),
        publicSeminarsProvider.overrideWith((ref) async => const []),
        myCertificatesProvider.overrideWith((ref) async => certificates),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Service _gatedService() => const Service(
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

final _testProfile = Profile(
  id: 'user-1',
  email: 'user@test.local',
  userRole: UserRole.user,
  isAdmin: false,
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 1),
);

void main() {
  testWidgets('dashboard väntar på verifierad auth innan den renderar', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      services: [_gatedService()],
      certificates: const [],
      authState: const AuthState(),
    );

    expect(find.byType(AuthBootPage), findsOneWidget);
  });

  testWidgets(
    'dashboard låser bokningsknappen när användaren saknar verifierad certifiering',
    (tester) async {
      await _pumpDashboard(
        tester,
        services: [_gatedService()],
        certificates: const [],
        authState: AuthState(profile: _testProfile),
      );

      expect(
        find.widgetWithText(FilledButton, 'Certifiering krävs'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Certifiering krävs'),
      );
      expect(button.onPressed, isNull);
      expect(
        find.textContaining('Du behöver certifieringen "Tarot"'),
        findsOneWidget,
      );
    },
  );

  testWidgets('dashboard tillåter bokning när certifiering matchar', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      services: [_gatedService()],
      certificates: const [
        Certificate(
          id: 'cert-1',
          userId: 'user-1',
          title: 'Tarot',
          status: CertificateStatus.verified,
          statusRaw: 'verified',
          createdAt: null,
          updatedAt: null,
        ),
      ],
      authState: AuthState(profile: _testProfile),
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Boka'),
    );
    expect(button.onPressed, isNotNull);
    expect(find.text('Kräver certifiering: Tarot'), findsOneWidget);
  });
}
