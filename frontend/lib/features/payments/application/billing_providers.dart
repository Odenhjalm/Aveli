import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/features/payments/data/billing_api.dart';

final billingApiProvider = Provider<BillingApi>((ref) {
  final client = ref.watch(apiClientProvider);
  return BillingApi(client);
});
