import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/api/auth_repository.dart';
import 'package:wisdom/data/models/order.dart';
import 'package:wisdom/features/payments/data/payments_repository.dart';

final paymentsRepositoryProvider = Provider<PaymentsRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return PaymentsRepository(client);
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
