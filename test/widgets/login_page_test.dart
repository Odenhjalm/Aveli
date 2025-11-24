import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:wisdom/api/auth_repository.dart';
import 'package:wisdom/core/auth/auth_controller.dart';
import 'package:wisdom/core/auth/auth_http_observer.dart';
import 'package:wisdom/core/env/app_config.dart';
import 'package:wisdom/features/auth/presentation/login_page.dart';
import 'package:wisdom/gate.dart';
import 'package:wisdom/shared/utils/backend_assets.dart';
import '../helpers/backend_asset_resolver_stub.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _TestAuthController extends AuthController {
  _TestAuthController(AuthRepository repo) : super(repo, AuthHttpObserver());

  @override
  Future<void> loadSession() async {}
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
        data: {'detail': 'Invalid credentials'},
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
}
