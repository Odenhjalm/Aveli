import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/core/errors/app_failure.dart';

String _mapPlanToInterval(String plan) {
  switch (plan.toLowerCase()) {
    case 'monthly':
    case 'month':
      return 'month';
    case 'yearly':
    case 'annual':
    case 'year':
      return 'year';
    default:
      return 'month';
  }
}

class BillingApi {
  BillingApi(this._client);

  final ApiClient _client;

  Future<String> startSubscription({required String plan}) async {
    try {
      final interval = _mapPlanToInterval(plan);
      final response = await _client.post<Map<String, dynamic>>(
        ApiPaths.billingCreateSubscription,
        body: {'interval': interval},
      );
      final checkoutUrl =
          response['checkout_url'] as String? ?? response['url'] as String?;
      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        throw const FormatException('Checkout-URL saknas');
      }
      return checkoutUrl;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<void> changePlan(String plan) async {
    final normalized = plan.trim();
    if (normalized.isEmpty) {
      throw UnexpectedFailure(message: 'Plan saknas för planbyte.');
    }
    throw UnexpectedFailure(
      message: 'Planbyten hanteras via kundportalen.',
    );
  }

  Future<void> cancelSubscription() async {
    try {
      await _client.post<Map<String, dynamic>>(
        ApiPaths.billingCancelSubscription,
        body: const {},
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
