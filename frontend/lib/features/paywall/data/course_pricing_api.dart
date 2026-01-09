import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/env/env_resolver.dart';

class CoursePricing {
  CoursePricing({required this.amountCents, required this.currency});

  final int amountCents;
  final String currency;

  factory CoursePricing.fromJson(Map<String, dynamic> json) {
    return CoursePricing(
      amountCents: json['amount_cents'] as int,
      currency: json['currency'] as String,
    );
  }
}

class CoursePricingApi {
  CoursePricingApi({
    http.Client? client,
    TokenStorage? tokenStorage,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _tokenStorage = tokenStorage ?? const TokenStorage(),
       _base = baseUrl ?? EnvResolver.apiBaseUrl;

  final http.Client _client;
  final TokenStorage _tokenStorage;
  final String _base;

  Future<CoursePricing> fetch(String slug) async {
    final token = await _accessToken();
    final response = await _client.get(
      Uri.parse('$_base/api/courses/$slug/pricing'),
      headers: {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return CoursePricing.fromJson(body);
    }
    throw Exception('Failed to load pricing (${response.statusCode})');
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
