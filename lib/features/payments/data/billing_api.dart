import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:wisdom/api/api_client.dart';
import 'package:wisdom/core/errors/app_failure.dart';

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

  Future<void> startSubscription({required String plan}) async {
    try {
      final interval = _mapPlanToInterval(plan);
      final response = await _client.post<Map<String, dynamic>>(
        '/api/billing/create-subscription-sheet',
        body: {'interval': interval},
      );
      final sheet = (response['payment_sheet'] as Map?)?.cast<String, dynamic>() ??
          response.cast<String, dynamic>();
      final clientSecret = sheet['client_secret'] as String? ??
          sheet['payment_intent'] as String?;
      final customerId = sheet['customer'] as String? ??
          sheet['customer_id'] as String?;
      final ephemeralKey = sheet['ephemeral_key'] as String? ??
          sheet['ephemeralKey'] as String?;
      if (clientSecret == null ||
          customerId == null ||
          ephemeralKey == null) {
        throw const FormatException('PaymentSheet saknar fält');
      }
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Aveli',
          customerId: customerId,
          customerEphemeralKeySecret: ephemeralKey,
        ),
      );
      await Stripe.instance.presentPaymentSheet();
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<void> changePlan(String plan) async {
    try {
      final interval = _mapPlanToInterval(plan);
      await _client.post<Map<String, dynamic>>(
        '/api/billing/change-plan',
        body: {'interval': interval},
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<void> cancelSubscription() async {
    try {
      await _client.post<Map<String, dynamic>>(
        '/api/billing/cancel-subscription',
        body: const {},
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
