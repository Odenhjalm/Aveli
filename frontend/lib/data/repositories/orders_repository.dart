import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/api/api_client.dart';
import 'package:wisdom/api/auth_repository.dart';
import 'package:wisdom/data/models/order.dart';

class OrdersRepository {
  const OrdersRepository(this._client);

  final ApiClient _client;

  Future<Order> createServiceOrder({
    required String serviceId,
    int? amountCents,
    String? currency,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/orders',
      body: {
        'service_id': serviceId,
        if (amountCents != null) 'amount_cents': amountCents,
        if (currency != null) 'currency': currency,
      },
    );
    return Order.fromJson(response['order'] as Map<String, dynamic>);
  }

  Future<Order> fetchOrder(String id) async {
    final response = await _client.get<Map<String, dynamic>>('/orders/$id');
    return Order.fromJson(response['order'] as Map<String, dynamic>);
  }

  Future<String> createStripeCheckout({
    required String orderId,
    required String successUrl,
    required String cancelUrl,
    String? email,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/payments/stripe/create-session',
      body: {
        'order_id': orderId,
        'success_url': successUrl,
        'cancel_url': cancelUrl,
        if (email != null) 'customer_email': email,
      },
    );
    return (response['url'] ?? '') as String;
  }
}

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return OrdersRepository(client);
});
