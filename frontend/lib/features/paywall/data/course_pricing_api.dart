import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:aveli/core/auth/token_storage.dart';
import 'package:aveli/core/env/env_resolver.dart';

Object? _requiredPricingField(Object? payload, String fieldName) {
  switch (payload) {
    case final Map data when data.containsKey(fieldName):
      return data[fieldName];
    case final Map _:
      throw StateError('Kurssvaret saknar prisfältet $fieldName.');
    default:
      throw StateError('Kurssvaret innehåller ogiltig prisinformation.');
  }
}

class CoursePricing {
  CoursePricing({required this.amountCents, required this.currency});

  final int amountCents;
  final String currency;

  factory CoursePricing.fromResponse(Object? payload) {
    final rawAmount = _requiredPricingField(payload, 'amount_cents');
    final rawCurrency = _requiredPricingField(payload, 'currency');
    if (rawAmount is! int) {
      throw StateError('Prisfältet amount_cents måste vara ett heltal.');
    }
    if (rawCurrency is! String || rawCurrency.isEmpty) {
      throw StateError('Prisfältet currency måste vara text.');
    }
    return CoursePricing(amountCents: rawAmount, currency: rawCurrency);
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
      final Object? body = jsonDecode(response.body);
      return CoursePricing.fromResponse(body);
    }
    throw Exception('Kunde inte hämta pris (${response.statusCode}).');
  }

  Future<String?> _accessToken() async {
    return _tokenStorage.readAccessToken();
  }
}
