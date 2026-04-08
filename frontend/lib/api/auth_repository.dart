import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_paths.dart';
import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/auth/auth_http_observer.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/errors/app_failure.dart';
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
        ApiPaths.authLogin,
        body: {'email': email, 'password': password},
        skipAuth: true,
      );
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      if (accessToken == null || refreshToken == null) {
        throw const FormatException('access_token saknas i svaret');
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
    String? referralCode,
    String? inviteToken,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      ApiPaths.authRegister,
      body: {
        'email': email,
        'password': password,
        'display_name': displayName,
        if (inviteToken != null && inviteToken.trim().isNotEmpty)
          'invite_token': inviteToken.trim(),
      },
      skipAuth: true,
    );
    final accessToken = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;
    if (accessToken == null || refreshToken == null) {
      throw const FormatException('access_token saknas i svaret');
    }
    await _tokens.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    try {
      final normalizedReferralCode = referralCode?.trim();
      if (normalizedReferralCode != null && normalizedReferralCode.isNotEmpty) {
        await redeemReferral(normalizedReferralCode);
      }
      return await getCurrentProfile();
    } catch (_) {
      await _tokens.clear();
      rethrow;
    }
  }

  Future<void> redeemReferral(String code) async {
    await _client.post<Map<String, dynamic>>(
      ApiPaths.referralsRedeem,
      body: {'code': code.trim()},
    );
  }

  Future<void> requestPasswordReset(String email) async {
    try {
      await _client.post<Map<String, dynamic>>(
        ApiPaths.authRequestPasswordReset,
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

  Future<void> sendVerificationEmail(String email) async {
    try {
      await _client.post<Map<String, dynamic>>(
        ApiPaths.authSendVerification,
        body: {'email': email},
        skipAuth: true,
      );
    } on DioException catch (e) {
      debugPrint(
        'Send verification email failed: ${e.response?.data ?? e.message}',
      );
      rethrow;
    }
  }

  Future<void> verifyEmail(String token) async {
    try {
      await _client.get<Map<String, dynamic>>(
        ApiPaths.authVerifyEmail,
        queryParameters: {'token': token},
        skipAuth: true,
      );
    } on DioException catch (e) {
      debugPrint('Email verification failed: ${e.response?.data ?? e.message}');
      rethrow;
    }
  }

  Future<String> validateInvite(String token) async {
    try {
      final data = await _client.get<Map<String, dynamic>>(
        ApiPaths.authValidateInvite,
        queryParameters: {'token': token},
        skipAuth: true,
      );
      final email = data['email'] as String?;
      if (email == null || email.trim().isEmpty) {
        throw const FormatException('E-post saknas i inbjudningssvaret');
      }
      return email;
    } on DioException catch (e) {
      debugPrint('Invite validation failed: ${e.response?.data ?? e.message}');
      rethrow;
    }
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    try {
      await _client.post<Map<String, dynamic>>(
        ApiPaths.authResetPassword,
        body: {'token': token, 'new_password': newPassword},
        skipAuth: true,
      );
    } on DioException catch (e) {
      debugPrint('Password reset failed: ${e.response?.data ?? e.message}');
      rethrow;
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _client.post<Map<String, dynamic>>(
        ApiPaths.authChangePassword,
        body: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
    } on DioException catch (e) {
      debugPrint('Change password failed: ${e.response?.data ?? e.message}');
      rethrow;
    }
  }

  Future<Profile> getCurrentProfile() async {
    final data = await _client.get<Map<String, dynamic>>(ApiPaths.authMe);
    return Profile.fromJson(data);
  }

  Future<void> completeWelcome() async {
    throw UnexpectedFailure(
      message:
          'Välkomststeget stöds inte längre via den borttagna legacy-/api/me-ytan.',
    );
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
