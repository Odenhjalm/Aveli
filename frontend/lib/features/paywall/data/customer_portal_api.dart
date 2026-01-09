import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/env/env_resolver.dart';

class CustomerPortalApi {
  CustomerPortalApi({
    http.Client? client,
    TokenStorage? tokenStorage,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _tokenStorage = tokenStorage ?? const TokenStorage(),
       _baseUrl = baseUrl ?? EnvResolver.apiBaseUrl;

  final http.Client _client;
  final TokenStorage _tokenStorage;
  final String _baseUrl;

  Future<String> createPortalUrl() async {
    final token = await _accessToken();
    final response = await _client.post(
      Uri.parse('$_baseUrl/api/billing/customer-portal'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw Exception('Kundportal-URL saknas');
      }
      final url = body['url'] as String?;
      if (url == null || url.isEmpty) {
        throw Exception('Kundportal-URL saknas');
      }
      return url;
    }
    var message = 'Kunde inte öppna kundportal (${response.statusCode})';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] is String) {
        final detail = body['detail'] as String;
        if (detail.isNotEmpty) {
          message = detail;
        }
      }
    } catch (_) {}
    throw Exception(message);
  }

  Future<String?> _accessToken() async {
    final supabaseToken = _trySupabaseToken();
    if (supabaseToken != null && supabaseToken.isNotEmpty) {
      return supabaseToken;
    }
    return _tokenStorage.readAccessToken();
  }

  String? _trySupabaseToken() {
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }
}

final customerPortalApiProvider = Provider<CustomerPortalApi>((ref) {
  final config = ref.watch(appConfigProvider);
  final tokens = ref.watch(tokenStorageProvider);
  return CustomerPortalApi(tokenStorage: tokens, baseUrl: config.apiBaseUrl);
});
