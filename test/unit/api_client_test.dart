import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:wisdom/api/api_client.dart';
import 'package:wisdom/core/auth/auth_http_observer.dart';
import 'package:wisdom/core/auth/token_storage.dart';

class _MockTokenStorage extends Mock implements TokenStorage {}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future? cancelFuture,
  ) {
    return _handler(options);
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('ApiClient auth handling', () {
    late _MockTokenStorage tokenStorage;
    late ApiClient client;
    late String currentAccessToken;
    late String currentRefreshToken;
    late AuthHttpObserver observer;
    int refreshCalls = 0;

    setUp(() {
      tokenStorage = _MockTokenStorage();
      currentAccessToken = 'old_access';
      currentRefreshToken = 'refresh_token';
      refreshCalls = 0;
      observer = AuthHttpObserver();

      when(tokenStorage.clear).thenAnswer((_) async {});
      when(
        () => tokenStorage.readAccessToken(),
      ).thenAnswer((_) async => currentAccessToken);
      when(
        () => tokenStorage.readRefreshToken(),
      ).thenAnswer((_) async => currentRefreshToken);
      when(
        () => tokenStorage.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
        ),
      ).thenAnswer((invocation) async {
        currentAccessToken =
            invocation.namedArguments[#accessToken] as String? ?? '';
        currentRefreshToken =
            invocation.namedArguments[#refreshToken] as String? ?? '';
      });

      client = ApiClient(
        baseUrl: 'http://localhost',
        tokenStorage: tokenStorage,
        authObserver: observer,
      );
    });

    tearDown(() {
      observer.dispose();
    });

    test('retries request after successful token refresh', () async {
      var firstProtectedCall = true;
      client.raw.httpClientAdapter = _StubAdapter((options) async {
        if (options.path == '/auth/refresh') {
          refreshCalls += 1;
          final payload = jsonEncode({
            'access_token': 'new_access',
            'refresh_token': 'new_refresh',
          });
          return ResponseBody.fromString(
            payload,
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }

        if (options.path == '/protected') {
          if (firstProtectedCall) {
            firstProtectedCall = false;
            return ResponseBody.fromString(
              'Unauthorized',
              401,
              headers: {
                Headers.contentTypeHeader: ['text/plain'],
              },
            );
          }
          return ResponseBody.fromString(
            jsonEncode({'ok': true}),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }

        return ResponseBody.fromString(
          'Not Found',
          404,
          headers: {
            Headers.contentTypeHeader: ['text/plain'],
          },
        );
      });

      final response = await client.get<Map<String, dynamic>>('/protected');

      expect(response['ok'], true);
      expect(refreshCalls, 1);
      verify(
        () => tokenStorage.saveTokens(
          accessToken: 'new_access',
          refreshToken: 'new_refresh',
        ),
      ).called(1);
    });

    test('emits forbidden event for 403 responses', () async {
      final events = <AuthHttpEvent>[];
      final sub = observer.events.listen(events.add);
      client.raw.httpClientAdapter = _StubAdapter((options) async {
        return ResponseBody.fromString(
          'Forbidden',
          403,
          headers: {
            Headers.contentTypeHeader: ['text/plain'],
          },
        );
      });

      await expectLater(
        () => client.get<Map<String, dynamic>>('/protected'),
        throwsA(isA<DioException>()),
      );
      expect(refreshCalls, 0);
      await Future<void>.delayed(Duration.zero);
      expect(events, [AuthHttpEvent.forbidden]);
      await sub.cancel();
    });

    test('emits sessionExpired when refresh token missing', () async {
      currentRefreshToken = '';
      final events = <AuthHttpEvent>[];
      final sub = observer.events.listen(events.add);
      client.raw.httpClientAdapter = _StubAdapter((options) async {
        return ResponseBody.fromString(
          'Unauthorized',
          401,
          headers: {
            Headers.contentTypeHeader: ['text/plain'],
          },
        );
      });

      await expectLater(
        () => client.get<Map<String, dynamic>>('/protected'),
        throwsA(isA<DioException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        events.where((event) => event == AuthHttpEvent.sessionExpired).length,
        greaterThanOrEqualTo(1),
      );
      verify(() => tokenStorage.clear()).called(2);
      await sub.cancel();
    });
    test('skipAuth omits Authorization header', () async {
      client.raw.httpClientAdapter = _StubAdapter((options) async {
        if (options.path == '/public') {
          expect(options.headers.containsKey('Authorization'), isFalse);
          return ResponseBody.fromString(
            jsonEncode({'ok': true}),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }
        return ResponseBody.fromString('Not Found', 404, headers: {});
      });

      final response = await client.get<Map<String, dynamic>>(
        '/public',
        skipAuth: true,
      );
      expect(response['ok'], true);
    });
    test('performs single refresh for concurrent 401 responses', () async {
      var protectedCalls = 0;
      client.raw.httpClientAdapter = _StubAdapter((options) async {
        if (options.path == '/auth/refresh') {
          refreshCalls += 1;
          final payload = jsonEncode({
            'access_token': 'new_access',
            'refresh_token': 'new_refresh',
          });
          return ResponseBody.fromString(
            payload,
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }

        if (options.path == '/protected') {
          final authHeader = options.headers['Authorization'] as String?;
          if (authHeader == 'Bearer new_access') {
            return ResponseBody.fromString(
              jsonEncode({'ok': true}),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }
          expect(authHeader, 'Bearer old_access');
          protectedCalls += 1;
          return ResponseBody.fromString(
            'Unauthorized',
            401,
            headers: {
              Headers.contentTypeHeader: ['text/plain'],
            },
          );
        }

        return ResponseBody.fromString('Not Found', 404, headers: {});
      });

      final results = await Future.wait([
        client.get<Map<String, dynamic>>('/protected'),
        client.get<Map<String, dynamic>>('/protected'),
      ]);

      expect(results, everyElement(containsPair('ok', true)));
      expect(refreshCalls, 1);
      expect(protectedCalls, 2);
      verify(
        () => tokenStorage.saveTokens(
          accessToken: 'new_access',
          refreshToken: 'new_refresh',
        ),
      ).called(1);
    });
  });
}
