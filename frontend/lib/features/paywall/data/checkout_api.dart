import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/errors/app_failure.dart';

class CheckoutLaunch {
  CheckoutLaunch({
    required this.url,
    required this.sessionId,
    required this.orderId,
  });

  final String url;
  final String sessionId;
  final String orderId;

  factory CheckoutLaunch.fromJson(Map<String, dynamic> payload) {
    final url = payload['url'];
    final sessionId = payload['session_id'];
    final orderId = payload['order_id'];
    if (url is! String || url.isEmpty) {
      throw UnexpectedFailure(
        message: 'Betalningssvaret saknar betalningsadress.',
      );
    }
    if (sessionId is! String || sessionId.isEmpty) {
      throw UnexpectedFailure(message: 'Betalningssvaret saknar sessions-id.');
    }
    if (orderId is! String || orderId.isEmpty) {
      throw UnexpectedFailure(message: 'Betalningssvaret saknar order-id.');
    }
    return CheckoutLaunch(url: url, sessionId: sessionId, orderId: orderId);
  }
}

class MembershipCheckoutLaunch {
  MembershipCheckoutLaunch({
    required this.clientSecret,
    required this.sessionId,
    required this.orderId,
  });

  final String clientSecret;
  final String sessionId;
  final String orderId;

  factory MembershipCheckoutLaunch.fromJson(Map<String, dynamic> payload) {
    final clientSecret = payload['client_secret'];
    final sessionId = payload['session_id'];
    final orderId = payload['order_id'];
    if (clientSecret is! String || clientSecret.isEmpty) {
      throw UnexpectedFailure(
        message: 'Betalningssvaret saknar klienthemlighet.',
      );
    }
    if (sessionId is! String || sessionId.isEmpty) {
      throw UnexpectedFailure(message: 'Betalningssvaret saknar sessions-id.');
    }
    if (orderId is! String || orderId.isEmpty) {
      throw UnexpectedFailure(message: 'Betalningssvaret saknar order-id.');
    }
    return MembershipCheckoutLaunch(
      clientSecret: clientSecret,
      sessionId: sessionId,
      orderId: orderId,
    );
  }
}

class CheckoutApi {
  CheckoutApi(this._client);

  final ApiClient _client;

  Future<MembershipCheckoutLaunch> createMembershipCheckout({
    required String interval,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiPaths.billingCreateSubscription,
        body: {'interval': interval},
      );
      return MembershipCheckoutLaunch.fromJson(response);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<CheckoutLaunch> createCourseCheckout({required String slug}) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiPaths.checkoutCreate,
        body: {'slug': slug},
      );
      return CheckoutLaunch.fromJson(response);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}

final checkoutApiProvider = Provider<CheckoutApi>((ref) {
  final client = ref.watch(apiClientProvider);
  return CheckoutApi(client);
});
