import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/data/models/order.dart';

class OrdersRepository {
  const OrdersRepository(this._client);

  final ApiClient _client;

  Future<Order> createServiceOrder({
    required String serviceId,
    int? amountCents,
    String? currency,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiPaths.orders,
      body: {
        'service_id': serviceId,
        if (amountCents != null) 'amount_cents': amountCents,
        if (currency != null) 'currency': currency,
      },
    );
    return Order.fromJson(response['order'] as Map<String, dynamic>);
  }

  Future<Order> fetchOrder(String id) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiPaths.order(id),
    );
    return Order.fromJson(response['order'] as Map<String, dynamic>);
  }
}

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return OrdersRepository(client);
});
