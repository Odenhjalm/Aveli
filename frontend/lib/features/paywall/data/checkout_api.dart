import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/env/env_resolver.dart';

class CheckoutApi {
  CheckoutApi({
    http.Client? client,
    TokenStorage? tokenStorage,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _tokenStorage = tokenStorage ?? const TokenStorage(),
       _baseUrl = baseUrl ?? EnvResolver.apiBaseUrl;

  final http.Client _client;
  final TokenStorage _tokenStorage;
  final String _baseUrl;

  Future<String> startCourseCheckout({required String slug}) {
    return _startCheckout({'type': 'course', 'slug': slug});
  }

  Future<String> startMembershipCheckout({String interval = 'month'}) {
    return _startCheckout({'type': 'subscription', 'interval': interval});
  }

  Future<String> startServiceCheckout({required String serviceId}) {
    return _startCheckout({'type': 'service', 'slug': serviceId});
  }

  Future<String> startBundleCheckout({required String bundleId}) async {
    final token = await _accessToken();
    final response = await _client.post(
      Uri.parse('$_baseUrl/api/course-bundles/$bundleId/checkout-session'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Kunde inte starta paketbetalning (${response.statusCode}): ${response.body}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('Betalningslänk saknas');
    }
    return url;
  }

  Future<String> _startCheckout(Map<String, dynamic> payload) async {
    final token = await _accessToken();
    final response = await _client.post(
      Uri.parse('$_baseUrl/api/checkout/create'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to create checkout (${response.statusCode}): ${response.body}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('Checkout-URL saknas');
    }
    return url;
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

final checkoutApiProvider = Provider<CheckoutApi>((ref) {
  final config = ref.watch(appConfigProvider);
  final tokens = ref.watch(tokenStorageProvider);
  return CheckoutApi(tokenStorage: tokens, baseUrl: config.apiBaseUrl);
});
