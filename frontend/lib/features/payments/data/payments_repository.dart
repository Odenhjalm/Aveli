import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/data/models/order.dart';

class CouponPreviewResult {
  CouponPreviewResult({required this.valid, required this.payAmountCents});

  final bool valid;
  final int payAmountCents;
}

class CouponRedeemResult {
  CouponRedeemResult({required this.ok, this.reason, this.subscription});

  final bool ok;
  final String? reason;
  final Map<String, dynamic>? subscription;
}

class PaymentsRepository {
  PaymentsRepository(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> plans() async {
    return const [];
  }

  Future<bool> hasActiveSubscription() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        ApiPaths.meEntitlements,
      );
      final membership = response['membership'];
      if (membership is Map<String, dynamic>) {
        return membership['is_active'] == true;
      }
      if (membership is Map) {
        return membership['is_active'] == true;
      }
      return false;
    } catch (error, stackTrace) {
      final failure = AppFailure.from(error, stackTrace);
      if (failure is UnauthorizedFailure) {
        return false;
      }
      throw failure;
    }
  }

  Future<Map<String, dynamic>?> currentSubscription() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        ApiPaths.meMembership,
      );
      final membership = response['membership'];
      if (membership is Map<String, dynamic>) {
        // API returnerar stripe_subscription_id men UI:n förväntar sig subscription_id.
        return {
          ...membership,
          'subscription_id':
              membership['subscription_id'] ??
              membership['stripe_subscription_id'],
        };
      }
      if (membership is Map) {
        final casted = membership.cast<String, dynamic>();
        return {
          ...casted,
          'subscription_id':
              casted['subscription_id'] ?? casted['stripe_subscription_id'],
        };
      }
      return null;
    } catch (error, stackTrace) {
      final failure = AppFailure.from(error, stackTrace);
      if (failure is UnauthorizedFailure) {
        return null;
      }
      throw failure;
    }
  }

  Future<CouponPreviewResult> previewCoupon({
    required String planId,
    String? code,
  }) async {
    if (planId.isEmpty) {
      throw UnexpectedFailure(message: 'Plan-ID saknas.');
    }
    final normalizedCode = code?.trim();
    if (normalizedCode != null && normalizedCode.isEmpty) {
      throw UnexpectedFailure(message: 'Rabattkod saknas.');
    }
    throw UnexpectedFailure(
      message: 'Rabattkoder stöds inte av den nuvarande betalnings-API:n.',
    );
  }

  Future<CouponRedeemResult> redeemCoupon({
    required String planId,
    required String code,
  }) async {
    if (planId.isEmpty) {
      throw UnexpectedFailure(message: 'Plan-ID saknas.');
    }
    if (code.trim().isEmpty) {
      throw UnexpectedFailure(message: 'Rabattkod saknas.');
    }
    throw UnexpectedFailure(
      message: 'Rabattkoder stöds inte av den nuvarande betalnings-API:n.',
    );
  }

  Future<Map<String, dynamic>> startCourseOrder({
    required String courseId,
    required int amountCents,
    String currency = 'sek',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiPaths.orders,
        body: {
          'course_id': courseId,
          'amount_cents': amountCents,
          'currency': currency,
          if (metadata != null) 'metadata': metadata,
        },
      );
      return Map<String, dynamic>.from(response['order'] as Map);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> startServiceOrder({
    required String serviceId,
    required int amountCents,
    String currency = 'sek',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiPaths.orders,
        body: {
          'service_id': serviceId,
          'amount_cents': amountCents,
          'currency': currency,
          if (metadata != null) 'metadata': metadata,
        },
      );
      return Map<String, dynamic>.from(response['order'] as Map);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>?> getOrder(String orderId) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        ApiPaths.order(orderId),
      );
      return (response['order'] as Map?)?.cast<String, dynamic>();
    } catch (error, stackTrace) {
      final failure = AppFailure.from(error, stackTrace);
      if (failure.kind == AppFailureKind.notFound) {
        return null;
      }
      throw failure;
    }
  }

  Future<List<Order>> listOrders({String? status}) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        ApiPaths.orders,
        queryParameters: {
          if (status != null && status.trim().isNotEmpty)
            'status': status.trim().toLowerCase(),
        },
      );
      final items = (response['items'] as List? ?? [])
          .map((item) => Order.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false);
      return items;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<String> checkoutUrl({
    required String orderId,
    required String successUrl,
    required String cancelUrl,
    String? customerEmail,
  }) async {
    try {
      if (successUrl.isEmpty || cancelUrl.isEmpty) {
        throw UnexpectedFailure(message: 'Checkout-URL saknar callback-adresser.');
      }
      final normalizedEmail = customerEmail?.trim();
      if (customerEmail != null && (normalizedEmail?.isEmpty ?? true)) {
        throw UnexpectedFailure(message: 'E-postadressen är tom.');
      }
      final order = await getOrder(orderId);
      if (order == null) {
        throw NotFoundFailure(message: 'Ordern kunde inte hittas.');
      }
      final metadata = order['metadata'] as Map? ?? const {};
      String? slug;
      String? type;
      if (order['course_id'] != null) {
        type = 'course';
        slug = metadata['course_slug'] as String? ?? order['course_id'] as String?;
      } else if (order['service_id'] != null) {
        type = 'service';
        slug = metadata['service_slug'] as String? ?? order['service_id'] as String?;
      }
      if (type == null || slug == null || slug.isEmpty) {
        throw UnexpectedFailure(
          message: 'Ordern saknar checkout-detaljer.',
        );
      }
      final response = await _client.post<Map<String, dynamic>>(
        ApiPaths.checkoutCreate,
        body: {
          'type': type,
          'slug': slug,
        },
      );
      return response['url'] as String? ?? '';
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<bool> claimPurchase(String token) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiPaths.meClaimPurchase,
        body: {'token': token},
      );
      return response['ok'] == true;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<String> createSubscription({required String interval}) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiPaths.billingCreateSubscription,
        body: {'interval': interval},
      );
      final checkoutUrl =
          response['checkout_url'] as String? ?? response['url'] as String?;
      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        throw ServerFailure(message: 'Checkout-URL saknas i svaret.');
      }
      return checkoutUrl;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<void> cancelSubscription(String subscriptionId) async {
    try {
      await _client.post<Map<String, dynamic>>(
        ApiPaths.billingCancelSubscription,
        body: {'subscription_id': subscriptionId},
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
