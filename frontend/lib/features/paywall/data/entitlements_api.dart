import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wisdom/core/auth/token_storage.dart';
import 'package:wisdom/core/env/env_resolver.dart';

import '../domain/entitlements.dart';

class EntitlementsApi {
  EntitlementsApi({
    http.Client? client,
    TokenStorage? tokenStorage,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _tokenStorage = tokenStorage ?? const TokenStorage(),
       _baseUrl = baseUrl ?? EnvResolver.apiBaseUrl;

  final http.Client _client;
  final TokenStorage _tokenStorage;
  final String _baseUrl;

  Future<Entitlements> fetchEntitlements() async {
    final token = await _tokenStorage.readAccessToken();
    final uri = Uri.parse('$_baseUrl/api/me/entitlements');
    final res = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) {
        return Entitlements.fromJson(body);
      }
      throw Exception('Unexpected entitlements payload: ${res.body}');
    }
    throw Exception(
      'Failed to fetch entitlements: ${res.statusCode} ${res.body}',
    );
  }
}
