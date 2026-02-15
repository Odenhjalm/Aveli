import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/env/env_resolver.dart';

class CheckoutVerificationResult {
  const CheckoutVerificationResult({
    required this.ok,
    required this.sessionId,
    required this.success,
    required this.status,
    this.mode,
    this.sessionStatus,
    this.paymentStatus,
    this.checkoutType,
    this.orderId,
    this.courseSlug,
    this.serviceSlug,
    this.customerId,
  });

  final bool ok;
  final String sessionId;
  final bool success;
  final String status;
  final String? mode;
  final String? sessionStatus;
  final String? paymentStatus;
  final String? checkoutType;
  final String? orderId;
  final String? courseSlug;
  final String? serviceSlug;
  final String? customerId;

  factory CheckoutVerificationResult.fromJson(Map<String, dynamic> json) {
    return CheckoutVerificationResult(
      ok: (json['ok'] as bool?) ?? true,
      sessionId: json['session_id'] as String? ?? '',
      success: (json['success'] as bool?) ?? false,
      status: (json['status'] as String?) ?? 'failed',
      mode: json['mode'] as String?,
      sessionStatus: json['session_status'] as String?,
      paymentStatus: json['payment_status'] as String?,
      checkoutType: json['checkout_type'] as String?,
      orderId: json['order_id'] as String?,
      courseSlug: json['course_slug'] as String?,
      serviceSlug: json['service_slug'] as String?,
      customerId: json['customer_id'] as String?,
    );
  }
}

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
    return _startSubscriptionCheckout(interval: interval);
  }

  Future<String> startServiceCheckout({required String serviceId}) {
    return _startCheckout({'type': 'service', 'slug': serviceId});
  }

  Future<String> startBundleCheckout({required String bundleId}) async {
    final token = await _accessToken();
    final response = await _client.post(
      Uri.parse('$_baseUrl${ApiPaths.courseBundleCheckout(bundleId)}'),
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

  Future<String> _startSubscriptionCheckout({required String interval}) async {
    final token = await _accessToken();
    final response = await _client.post(
      Uri.parse('$_baseUrl${ApiPaths.billingCreateSubscription}'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'interval': interval}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to create subscription (${response.statusCode}): ${response.body}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final url = body['checkout_url'] as String? ?? body['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('Checkout-URL saknas');
    }
    return url;
  }

  Future<String> _startCheckout(Map<String, dynamic> payload) async {
    final token = await _accessToken();
    final response = await _client.post(
      Uri.parse('$_baseUrl${ApiPaths.checkoutCreate}'),
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

  Future<CheckoutVerificationResult> verifyCheckoutSession({
    required String sessionId,
  }) async {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      throw Exception('session_id saknas');
    }

    final token = await _accessToken();
    final query = Uri.encodeQueryComponent(normalized);
    final response = await _client.get(
      Uri.parse('$_baseUrl${ApiPaths.checkoutVerify}?session_id=$query'),
      headers: {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to verify checkout (${response.statusCode}): ${response.body}',
      );
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('Ogiltigt verifieringssvar från backend');
    }
    final result = CheckoutVerificationResult.fromJson(body);
    if (result.sessionId.isEmpty) {
      throw Exception('Verifieringssvar saknar session_id');
    }
    return result;
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
