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
}
