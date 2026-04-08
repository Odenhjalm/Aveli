import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/auth/presentation/login_page.dart';
import 'package:aveli/gate.dart';
import 'package:aveli/shared/utils/backend_assets.dart';
import '../helpers/backend_asset_resolver_stub.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

String _tokenForClaims(Map<String, Object?> claims) {
  final header = base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}'));
  final payload = base64Url.encode(utf8.encode(jsonEncode(claims)));
  return '$header.$payload.signature';
}

class _TestAuthController extends AuthController {
  _TestAuthController(AuthRepository repo) : super(repo, AuthHttpObserver());

  @override
  Future<void> loadSession({bool hydrateProfile = true}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const transparentPixelBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4////fwAJ+wP+yrKoNwAAAABJRU5ErkJggg==';
  final transparentPixel = Uint8List.fromList(
    base64Decode(transparentPixelBase64),
  );
  const codec = StandardMessageCodec();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(message!.buffer.asUint8List());
          if (key == 'AssetManifest.bin') {
            return codec.encodeMessage(<String, dynamic>{});
          }
          if (key == 'AssetManifest.json') {
            final jsonBytes = utf8.encode('{}');
            return Uint8List.fromList(jsonBytes).buffer.asByteData();
          }
          return transparentPixel.buffer.asByteData();
        });
    gate.reset();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    gate.reset();
  });

  testWidgets('LoginPage visar felmeddelande när inloggning misslyckas', (
    tester,
  ) async {
    final repo = _MockAuthRepository();
    final error = DioException(
      requestOptions: RequestOptions(path: '/auth/login'),
      response: Response(
        requestOptions: RequestOptions(path: '/auth/login'),
        statusCode: 401,
        data: {'detail': 'Fel e-postadress eller lösenord.'},
      ),
      type: DioExceptionType.badResponse,
    );

    when(
      () => repo.login(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenThrow(error);
    when(() => repo.currentToken()).thenAnswer((_) async => null);

    final controller = _TestAuthController(repo);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => controller),
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
        ],
        child: const MaterialApp(home: LoginPage()),
      ),
    );

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'user@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong-pass');

    await tester.tap(find.widgetWithText(FilledButton, 'Logga in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('login-error')),
        matching: find.text('Fel e-postadress eller lösenord.'),
      ),
      findsOneWidget,
    );
    expect(gate.allowed, isFalse);
  });

  testWidgets('teacher login redirects to teacher home', (tester) async {
    final repo = _MockAuthRepository();
    final teacherToken = _tokenForClaims({
      'role': 'teacher',
      'is_admin': false,
      'onboarding_state': OnboardingStateValue.completed,
    });
    final profile = Profile(
      id: 'teacher-1',
      email: 'teacher@example.com',
      createdAt: DateTime.utc(2024, 1, 1),
      updatedAt: DateTime.utc(2024, 1, 2),
    );

    when(
      () => repo.login(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => profile);
    when(() => repo.currentToken()).thenAnswer((_) async => teacherToken);

    final controller = _TestAuthController(repo);
    final router = GoRouter(
      initialLocation: RoutePath.login,
      routes: [
        GoRoute(
          path: RoutePath.login,
          name: AppRoute.login,
          builder: (context, _) => const LoginPage(),
        ),
        GoRoute(
          path: RoutePath.home,
          name: AppRoute.home,
          builder: (context, _) => const Text('home'),
        ),
        GoRoute(
          path: RoutePath.teacherHome,
          name: AppRoute.teacherHome,
          builder: (context, _) => const Text('teacher-home'),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => controller),
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
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'teacher@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'correct-pass');

    await tester.tap(find.widgetWithText(FilledButton, 'Logga in'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('teacher-home'), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.path,
      RoutePath.teacherHome,
    );
  });
}
