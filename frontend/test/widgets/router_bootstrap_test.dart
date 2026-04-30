import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/data/models/text_bundle.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/data/models/service.dart';
import 'package:aveli/domain/models/entry_state.dart';
import 'package:aveli/features/auth/presentation/login_page.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/presentation/profile_page.dart';
import 'package:aveli/features/courses/application/course_providers.dart'
    as courses_front;
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/home/presentation/home_dashboard_page.dart';
import 'package:aveli/features/landing/application/landing_providers.dart'
    as landing;
import 'package:aveli/features/onboarding/onboarding_profile_page.dart';
import 'package:aveli/features/payments/presentation/subscribe_screen.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/main.dart';
import 'package:aveli/shared/data/app_render_inputs_repository.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import '../helpers/backend_asset_resolver_stub.dart';

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

const List<TextBundle> _navigationTextBundles = <TextBundle>[
  TextBundle(
    bundleId: 'global_system.navigation.v1',
    locale: 'sv-SE',
    version: 'catalog_v1',
    hash: 'sha256:test-navigation',
    texts: {
      'global_system.navigation.home': TextNode(value: 'Hem'),
      'global_system.navigation.teacher_home': TextNode(value: 'Lärarhem'),
      'global_system.navigation.profile': TextNode(value: 'Profil'),
    },
  ),
];

const AppRenderInputs _testAppRenderInputs = AppRenderInputs(
  brand: BrandRenderInputs(
    logo: BrandLogoRenderInput(resolvedUrl: 'https://cdn.test/logo.png'),
  ),
  ui: UiRenderInputs(
    backgrounds: UiBackgroundRenderInputs(
      defaultBackground: UiBackgroundRenderInput(
        resolvedUrl: 'https://cdn.test/default.jpg',
      ),
      lesson: UiBackgroundRenderInput(
        resolvedUrl: 'https://cdn.test/lesson.jpg',
      ),
      observatory: UiBackgroundRenderInput(
        resolvedUrl: 'https://cdn.test/observatory.jpg',
      ),
    ),
  ),
  textBundles: _navigationTextBundles,
);

const AppRenderInputs _testAppRenderInputsWithoutTextBundles = AppRenderInputs(
  brand: BrandRenderInputs(
    logo: BrandLogoRenderInput(resolvedUrl: 'https://cdn.test/logo.png'),
  ),
  ui: UiRenderInputs(
    backgrounds: UiBackgroundRenderInputs(
      defaultBackground: UiBackgroundRenderInput(
        resolvedUrl: 'https://cdn.test/default.jpg',
      ),
      lesson: UiBackgroundRenderInput(
        resolvedUrl: 'https://cdn.test/lesson.jpg',
      ),
      observatory: UiBackgroundRenderInput(
        resolvedUrl: 'https://cdn.test/observatory.jpg',
      ),
    ),
  ),
  textBundles: <TextBundle>[],
);

final _pendingLogoRenderInput = Completer<BrandLogoRenderInput>().future;
final _pendingBackgroundRenderInput =
    Completer<UiBackgroundRenderInput>().future;

class _FakeAuthController extends AuthController {
  _FakeAuthController(AuthState initialState)
    : super(
        _FakeAuthRepository(
          profile: initialState.profile,
          token: initialState.profile != null || initialState.hasStoredToken
              ? 'token'
              : null,
        ),
        AuthHttpObserver(),
      ) {
    state = initialState;
  }

  @override
  Future<void> loadSession({bool hydrateProfile = true}) async {}
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.profile, this.token});

  final Profile? profile;
  final String? token;

  @override
  Future<Profile> login({required String email, required String password}) {
    throw UnsupportedError('Not implemented in tests');
  }

  @override
  Future<Profile> register({required String email, required String password}) {
    throw UnsupportedError('Not implemented in tests');
  }

  @override
  Future<void> sendVerificationEmail(String email) {
    throw UnsupportedError('Not implemented in tests');
  }

  @override
  Future<void> verifyEmail(String token) {
    throw UnsupportedError('Not implemented in tests');
  }

  @override
  Future<void> requestPasswordReset(String email) {
    throw UnsupportedError('Not implemented in tests');
  }

  @override
  Future<void> resetPassword({
    required String newPassword,
    required String token,
  }) {
    throw UnsupportedError('Not implemented in tests');
  }

  @override
  Future<Profile> getCurrentProfile() async {
    if (profile == null) {
      throw UnsupportedError('No profile available for test');
    }
    return profile!;
  }

  @override
  Future<Profile> createProfile({required String displayName, String? bio}) =>
      throw UnsupportedError('Not implemented in tests');

  @override
  Future<Profile> completeWelcome() =>
      throw UnsupportedError('Not implemented in tests');

  @override
  Future<void> redeemReferral({required String code}) =>
      throw UnsupportedError('Not implemented in tests');

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
        subscriptionsEnabled: false,
      ),
    ),
    backendAssetResolverProvider.overrideWith(
      (ref) => TestBackendAssetResolver(),
    ),
    ..._renderInputOverrides(_testAppRenderInputs),
    landing.popularCoursesProvider.overrideWith(
      (ref) =>
          Future.value(const landing.LandingSection<CourseSummary>(items: [])),
    ),
    communityServicesProvider.overrideWith(
      (ref) => Future.value(const <Service>[]),
    ),
  ];
}

List<Override> _renderInputOverrides(AppRenderInputs inputs) {
  return [
    appRenderInputsProvider.overrideWith((ref) async => inputs),
    brandLogoRenderInputProvider.overrideWith((ref) => _pendingLogoRenderInput),
    uiBackgroundRenderInputProvider.overrideWith(
      (ref, key) => _pendingBackgroundRenderInput,
    ),
  ];
}

void main() {
  final transparentData = ByteData.view(
    Uint8List.fromList(_transparentPng).buffer,
  );

  setUpAll(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = _TestImageHttpOverrides();
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
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  testWidgets('unauthenticated users land on login first', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(const AuthState()),
        child: const AveliApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(HomeDashboardPage), findsNothing);
  });

  testWidgets('profile-only users land on login without backend entry truth', (
    tester,
  ) async {
    final profile = Profile(
      id: 'user-1',
      email: 'user@example.com',
      createdAt: DateTime.utc(2024, 1, 1),
      updatedAt: DateTime.utc(2024, 1, 1),
      displayName: 'Test User',
    );

    final authedState = AuthState(profile: profile, isLoading: false);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(authedState),
        child: const AveliApp(),
      ),
    );

    await tester.pump();
    expect(find.byType(LoginPage), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(HomeDashboardPage), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('backend entry truth routes completed users to home', (
    tester,
  ) async {
    const entryState = EntryState(
      canEnterApp: true,
      onboardingState: 'completed',
      onboardingCompleted: true,
      membershipActive: true,
      needsOnboarding: false,
      needsPayment: false,
      role: 'learner',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(const AuthState(entryState: entryState)),
        child: const AveliApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(HomeDashboardPage), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
    'profile projection refresh stays on profile route without bootstrap redirect',
    (tester) async {
      const entryState = EntryState(
        canEnterApp: true,
        onboardingState: 'completed',
        onboardingCompleted: true,
        membershipActive: true,
        needsOnboarding: false,
        needsPayment: false,
        role: 'learner',
      );
      final profile = Profile(
        id: 'user-1',
        email: 'user@example.com',
        createdAt: DateTime.utc(2024, 1, 1),
        updatedAt: DateTime.utc(2024, 1, 1),
        displayName: 'Original User',
      );
      final authController = _FakeAuthController(
        AuthState(
          entryState: entryState,
          profile: profile,
          hasStoredToken: true,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            envInfoProvider.overrideWith((ref) => envInfoOk),
            authControllerProvider.overrideWith((ref) => authController),
            appConfigProvider.overrideWithValue(
              const AppConfig(
                apiBaseUrl: 'http://localhost',
                subscriptionsEnabled: false,
              ),
            ),
            backendAssetResolverProvider.overrideWith(
              (ref) => TestBackendAssetResolver(),
            ),
            ..._renderInputOverrides(_testAppRenderInputs),
            landing.popularCoursesProvider.overrideWith(
              (ref) => Future.value(
                const landing.LandingSection<CourseSummary>(items: []),
              ),
            ),
            communityServicesProvider.overrideWith(
              (ref) => Future.value(const <Service>[]),
            ),
            courses_front.myCoursesProvider.overrideWith(
              (ref) async => const [],
            ),
          ],
          child: const AveliApp(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(HomeDashboardPage), findsOneWidget);

      await tester.tap(find.byTooltip('Profil'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);

      authController.refreshProfileProjection(
        profile.copyWith(displayName: 'Updated User'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.byType(HomeDashboardPage), findsNothing);
      expect(find.text('Updated User'), findsOneWidget);
    },
  );

  testWidgets('backend entry truth routes payment-needed users to payment', (
    tester,
  ) async {
    const entryState = EntryState(
      canEnterApp: false,
      onboardingState: 'completed',
      onboardingCompleted: true,
      membershipActive: false,
      needsOnboarding: false,
      needsPayment: true,
      role: 'learner',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(const AuthState(entryState: entryState)),
        child: const AveliApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(MembershipCheckoutScreen), findsOneWidget);
    expect(find.byType(HomeDashboardPage), findsNothing);
  });

  testWidgets(
    'backend entry truth routes onboarding-needed users to create profile',
    (tester) async {
      const entryState = EntryState(
        canEnterApp: false,
        onboardingState: 'incomplete',
        onboardingCompleted: false,
        membershipActive: true,
        needsOnboarding: true,
        needsPayment: false,
        role: 'learner',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _commonOverrides(const AuthState(entryState: entryState)),
          child: const AveliApp(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(OnboardingProfilePage), findsOneWidget);
      expect(find.byType(HomeDashboardPage), findsNothing);
    },
  );

  testWidgets(
    'backend entry truth routes onboarding-needed users with profile to create profile',
    (tester) async {
      const entryState = EntryState(
        canEnterApp: false,
        onboardingState: 'incomplete',
        onboardingCompleted: false,
        membershipActive: true,
        needsOnboarding: true,
        needsPayment: false,
        role: 'learner',
      );
      final profile = Profile(
        id: 'user-1',
        email: 'user@example.com',
        createdAt: DateTime.utc(2024, 1, 1),
        updatedAt: DateTime.utc(2024, 1, 1),
        displayName: 'Test User',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _commonOverrides(
            AuthState(entryState: entryState, profile: profile),
          ),
          child: const AveliApp(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(OnboardingProfilePage), findsOneWidget);
      expect(find.byType(HomeDashboardPage), findsNothing);
    },
  );

  testWidgets('AppScaffold shows a home action by default', (tester) async {
    final view = tester.view;
    view.physicalSize = const Size(1200, 800);
    view.devicePixelRatio = 1.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://localhost',
              subscriptionsEnabled: false,
            ),
          ),
          backendAssetResolverProvider.overrideWith(
            (ref) => TestBackendAssetResolver(),
          ),
          ..._renderInputOverrides(_testAppRenderInputs),
        ],
        child: const MaterialApp(
          home: AppScaffold(
            title: 'Test',
            body: SizedBox.shrink(),
            neutralBackground: true,
            logoSize: 48,
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.byTooltip('Hem'), findsOneWidget);
  });

  testWidgets(
    'AppScaffold disables home action when navigation bundle is missing',
    (tester) async {
      final view = tester.view;
      view.physicalSize = const Size(1200, 800);
      view.devicePixelRatio = 1.0;
      addTearDown(() {
        view.resetPhysicalSize();
        view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(
                apiBaseUrl: 'http://localhost',
                subscriptionsEnabled: false,
              ),
            ),
            backendAssetResolverProvider.overrideWith(
              (ref) => TestBackendAssetResolver(),
            ),
            ..._renderInputOverrides(_testAppRenderInputsWithoutTextBundles),
          ],
          child: const MaterialApp(
            home: AppScaffold(
              title: 'Test',
              body: SizedBox.shrink(),
              neutralBackground: true,
              logoSize: 48,
            ),
          ),
        ),
      );

      await tester.pump();
      final homeAction = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.home_outlined),
      );
      expect(homeAction.onPressed, isNull);
      expect(find.byTooltip('Hem'), findsNothing);
    },
  );
}

class _TestImageHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _TestImageHttpClient();
}

class _TestImageHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _TestImageHttpRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestImageHttpRequest implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => _TestImageHttpResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestImageHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _transparentPng.length;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(Uint8List.fromList(_transparentPng)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
