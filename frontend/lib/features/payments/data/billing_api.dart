import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/errors/app_failure.dart';

class BillingApi {
  BillingApi(ApiClient client);

  Future<void> changePlan(String plan) async {
    final normalized = plan.trim();
    if (normalized.isEmpty) {
      throw UnexpectedFailure(message: 'Plan saknas för planbyte.');
    }
    throw UnexpectedFailure(message: 'Planbyten hanteras via kundportalen.');
  }

  Future<void> cancelSubscription() async {
    throw UnexpectedFailure(
      message:
          'Avbokning via frontend är inte del av det kanoniska launch-flödet. Vänta på backenddriven hantering i ett senare steg.',
    );
  }
}
