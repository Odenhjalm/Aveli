import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/data/models/order.dart';
import 'package:aveli/features/payments/data/payments_repository.dart';
import 'package:aveli/features/payments/services/stripe_service.dart';

final paymentsRepositoryProvider = Provider<PaymentsRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return PaymentsRepository(client);
});

final stripeCheckoutServiceProvider = Provider<StripeCheckoutService>((ref) {
  final client = ref.watch(apiClientProvider);
  return StripeCheckoutService(client);
});

final plansProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(paymentsRepositoryProvider);
  return repo.plans();
});

final activeSubscriptionProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  final repo = ref.watch(paymentsRepositoryProvider);
  return repo.currentSubscription();
});

final orderHistoryProvider = FutureProvider.autoDispose<List<Order>>((
  ref,
) async {
  final repo = ref.watch(paymentsRepositoryProvider);
  return repo.listOrders();
});
