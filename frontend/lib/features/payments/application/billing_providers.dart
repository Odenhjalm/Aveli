import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisdom/api/auth_repository.dart';
import 'package:wisdom/features/payments/data/billing_api.dart';

final billingApiProvider = Provider<BillingApi>((ref) {
  final client = ref.watch(apiClientProvider);
  return BillingApi(client);
});
