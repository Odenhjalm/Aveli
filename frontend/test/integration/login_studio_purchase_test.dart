import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockTokenStorage extends Mock implements TokenStorage {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('Login → Purchase flow', () {
    test('completes happy path via backend checkout API', () async {
      final apiClient = _MockApiClient();
      final tokenStorage = _MockTokenStorage();
      final authRepository = AuthRepository(apiClient, tokenStorage);
      final checkoutApi = CheckoutApi(apiClient);

      when(
        () => tokenStorage.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => apiClient.post<Map<String, dynamic>>(
          '/auth/login',
          body: any(named: 'body'),
          skipAuth: any(named: 'skipAuth'),
          extra: any(named: 'extra'),
        ),
      ).thenAnswer(
        (_) async => {
          'access_token': 'access_123',
          'refresh_token': 'refresh_123',
        },
      );

      await authRepository.login(
        email: 'teacher@example.com',
        password: 'secret123',
      );

      verify(
        () => tokenStorage.saveTokens(
          accessToken: 'access_123',
          refreshToken: 'refresh_123',
        ),
      ).called(1);

      when(
        () => apiClient.post<Map<String, dynamic>>(
          '/api/checkout/create',
          body: any(named: 'body'),
          skipAuth: any(named: 'skipAuth'),
          extra: any(named: 'extra'),
        ),
      ).thenAnswer(
        (_) async => {
          'url': 'https://checkout.test/session/abc',
          'session_id': 'cs_test_123',
          'order_id': 'order_123',
        },
      );

      final checkout = await checkoutApi.createCourseCheckout(
        slug: 'test-kurs',
      );

      expect(checkout.url, 'https://checkout.test/session/abc');
      expect(checkout.sessionId, 'cs_test_123');
      expect(checkout.orderId, 'order_123');
      final checkoutBody = verify(
        () => apiClient.post<Map<String, dynamic>>(
          '/api/checkout/create',
          body: captureAny(named: 'body'),
          skipAuth: any(named: 'skipAuth'),
          extra: any(named: 'extra'),
        ),
      ).captured.single;
      expect(checkoutBody, {'slug': 'test-kurs'});
      verifyNoMoreInteractions(tokenStorage);
    });
  });
}
