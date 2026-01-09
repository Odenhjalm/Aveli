import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/core/errors/app_failure.dart';

class SessionCheckoutResult {
  SessionCheckoutResult({
    required this.checkoutUrl,
    this.orderId,
  });

  final String checkoutUrl;
  final String? orderId;
}

class StripeCheckoutService {
  StripeCheckoutService(this._client);

  final ApiClient _client;

  Future<SessionCheckoutResult> createSessionCheckout({
    required String sessionId,
    String? sessionSlotId,
  }) async {
    try {
      if (sessionSlotId != null && sessionSlotId.isEmpty) {
        throw UnexpectedFailure(message: 'Session-slot saknar giltigt id.');
      }
      final response = await _client.post<Map<String, dynamic>>(
        ApiPaths.checkoutCreate,
        body: {
          'type': 'service',
          'slug': sessionId,
        },
      );
      final checkoutUrl = response['url'] as String? ?? '';
      if (checkoutUrl.isEmpty) {
        throw UnexpectedFailure(message: 'Checkout-URL saknas i svaret.');
      }
      return SessionCheckoutResult(
        checkoutUrl: checkoutUrl,
        orderId: response['order_id'] as String?,
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
