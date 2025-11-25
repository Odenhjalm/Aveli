import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/errors/app_failure.dart';

class SessionCheckoutResult {
  SessionCheckoutResult({
    required this.orderId,
    required this.clientSecret,
    this.paymentIntentId,
  });

  final String orderId;
  final String clientSecret;
  final String? paymentIntentId;
}

class StripeCheckoutService {
  StripeCheckoutService(this._client);

  final ApiClient _client;

  Future<SessionCheckoutResult> createSessionPaymentIntent({
    required String sessionId,
    String? sessionSlotId,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/checkout/session',
        body: {
          'session_id': sessionId,
          if (sessionSlotId != null) 'session_slot_id': sessionSlotId,
        },
      );
      return SessionCheckoutResult(
        orderId: response['order_id'] as String,
        clientSecret: response['client_secret'] as String,
        paymentIntentId: response['payment_intent_id'] as String?,
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
