import 'package:wisdom/api/api_client.dart';
import 'package:wisdom/core/errors/app_failure.dart';
import 'package:wisdom/data/models/order.dart';

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

class CreateSubscriptionResult {
  CreateSubscriptionResult({
    required this.subscriptionId,
    required this.clientSecret,
    required this.status,
  });

  final String subscriptionId;
  final String? clientSecret;
  final String? status;
}

class PaymentsRepository {
  PaymentsRepository(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> plans() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/payments/plans',
      );
      final items = (response['items'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
      return items;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<bool> hasActiveSubscription() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/payments/subscription',
      );
      return response['has_active'] == true;
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
        '/api/me/membership',
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
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/payments/coupons/preview',
        body: {
          'plan_id': planId,
          if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
        },
      );
      final pay = (response['pay_amount_cents'] as num?)?.toInt() ?? 0;
      return CouponPreviewResult(
        valid: response['valid'] == true,
        payAmountCents: pay,
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<CouponRedeemResult> redeemCoupon({
    required String planId,
    required String code,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/payments/coupons/redeem',
        body: {'plan_id': planId, 'code': code.trim()},
      );
      return CouponRedeemResult(
        ok: response['ok'] == true,
        reason: response['reason'] as String?,
        subscription: (response['subscription'] as Map?)
            ?.cast<String, dynamic>(),
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> startCourseOrder({
    required String courseId,
    required int amountCents,
    String currency = 'sek',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/payments/orders/course',
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
        '/payments/orders/service',
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
        '/payments/orders/$orderId',
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
        '/orders',
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
      final response = await _client.post<Map<String, dynamic>>(
        '/payments/create-checkout-session',
        body: {
          'order_id': orderId,
          'success_url': successUrl,
          'cancel_url': cancelUrl,
          if (customerEmail != null && customerEmail.isNotEmpty)
            'customer_email': customerEmail,
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
        '/payments/purchases/claim',
        body: {'token': token},
      );
      return response['ok'] == true;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<CreateSubscriptionResult> createSubscription({
    required String userId,
    required String priceId,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/payments/create-subscription',
        body: {'user_id': userId, 'price_id': priceId},
      );
      final subscriptionId = response['subscription_id'] as String?;
      if (subscriptionId == null || subscriptionId.isEmpty) {
        throw ServerFailure(message: 'Subscription-ID saknas i svaret.');
      }
      return CreateSubscriptionResult(
        subscriptionId: subscriptionId,
        clientSecret: response['client_secret'] as String?,
        status: response['status'] as String?,
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<void> cancelSubscription(String subscriptionId) async {
    try {
      await _client.post<Map<String, dynamic>>(
        '/api/billing/cancel-subscription',
        body: {'subscription_id': subscriptionId},
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
