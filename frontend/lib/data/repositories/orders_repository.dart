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
    final response = await _client.get<Map<String, dynamic>>(ApiPaths.order(id));
    return Order.fromJson(response['order'] as Map<String, dynamic>);
  }

  Future<String> createStripeCheckout({
    required String orderId,
    required String successUrl,
    required String cancelUrl,
    String? email,
  }) async {
    if (successUrl.isEmpty || cancelUrl.isEmpty) {
      throw Exception('Checkout-URL saknar callback-adresser.');
    }
    if (email != null && email.trim().isEmpty) {
      throw Exception('E-postadressen är tom.');
    }
    final order = await fetchOrder(orderId);
    String? type;
    String? slug;
    if (order.serviceId != null) {
      type = 'service';
      slug = order.metadata['service_slug'] as String? ?? order.serviceId;
    } else if (order.courseId != null) {
      type = 'course';
      slug = order.metadata['course_slug'] as String? ?? order.courseId;
    }
    if (type == null || slug == null || slug.isEmpty) {
      throw Exception('Ordern saknar checkout-detaljer.');
    }
    final response = await _client.post<Map<String, dynamic>>(
      ApiPaths.checkoutCreate,
      body: {
        'type': type,
        'slug': slug,
      },
    );
    return (response['url'] ?? '') as String;
  }
}

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return OrdersRepository(client);
});
