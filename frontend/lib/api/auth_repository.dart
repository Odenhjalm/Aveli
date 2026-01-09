import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/data/models/profile.dart';

class AuthRepository {
  AuthRepository(this._client, this._tokens);

  final ApiClient _client;
  final TokenStorage _tokens;

  Future<Profile> login({
    required String email,
    required String password,
  }) async {
    try {
      final data = await _client.post<Map<String, dynamic>>(
        '/auth/login',
        body: {'email': email, 'password': password},
        skipAuth: true,
      );
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      if (accessToken == null || refreshToken == null) {
        throw const FormatException('Missing access_token in response');
      }
      await _tokens.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      return await getCurrentProfile();
    } on DioException catch (e) {
      debugPrint('Auth login failed: ${e.response?.data ?? e.message}');
      rethrow;
    }
  }

  Future<Profile> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/auth/register',
      body: {'email': email, 'password': password, 'display_name': displayName},
      skipAuth: true,
    );
    final accessToken = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;
    if (accessToken == null || refreshToken == null) {
      throw const FormatException('Missing access_token in response');
    }
    await _tokens.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    return await getCurrentProfile();
  }

  Future<void> requestPasswordReset(String email) async {
    try {
      await _client.post<Map<String, dynamic>>(
        '/auth/forgot-password',
        body: {'email': email},
        skipAuth: true,
      );
    } on DioException catch (e) {
      debugPrint(
        'Password reset request failed: ${e.response?.data ?? e.message}',
      );
      rethrow;
    }
  }

  Future<void> resetPassword({
    required String email,
    required String newPassword,
  }) async {
    try {
      await _client.post<Map<String, dynamic>>(
        '/auth/reset-password',
        body: {'email': email, 'new_password': newPassword},
        skipAuth: true,
      );
    } on DioException catch (e) {
      debugPrint('Password reset failed: ${e.response?.data ?? e.message}');
      rethrow;
    }
  }

  Future<Profile> getCurrentProfile() async {
    final data = await _client.get<Map<String, dynamic>>('/auth/me');
    return Profile.fromJson(data);
  }

  Future<void> logout() => _tokens.clear();

  Future<String?> currentToken() => _tokens.readAccessToken();
}

final tokenStorageProvider = Provider<TokenStorage>(
  (_) => const TokenStorage(),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final tokens = ref.watch(tokenStorageProvider);
  final observer = ref.watch(authHttpObserverProvider);
  return ApiClient(
    baseUrl: config.apiBaseUrl,
    tokenStorage: tokens,
    authObserver: observer,
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  final tokens = ref.watch(tokenStorageProvider);
  return AuthRepository(client, tokens);
});

final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  final token = await repo.currentToken();
  if (token == null) {
    return null;
  }
  try {
    return await repo.getCurrentProfile();
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) {
      await repo.logout();
      return null;
    }
    rethrow;
  }
});
