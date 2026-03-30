import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/core/errors/app_failure.dart';

class BillingApi {
  BillingApi(this._client);

  final ApiClient _client;

  Future<void> changePlan(String plan) async {
    final normalized = plan.trim();
    if (normalized.isEmpty) {
      throw UnexpectedFailure(message: 'Plan saknas för planbyte.');
    }
    throw UnexpectedFailure(message: 'Planbyten hanteras via kundportalen.');
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
