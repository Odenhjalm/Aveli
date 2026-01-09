import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:aveli/api/api_paths.dart';
import 'app_config.dart';

class MvpApiClient {
  MvpApiClient({MvpAppConfig? config})
      : _config = config ?? MvpAppConfig.auto(),
        _dio = Dio(
          BaseOptions(
            baseUrl: (config ?? MvpAppConfig.auto()).baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            headers: const {'accept': 'application/json'},
          ),
        ) {
    _storage = const FlutterSecureStorage();
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = accessToken.value;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  final Dio _dio;
  late final FlutterSecureStorage _storage;
  final MvpAppConfig _config;

  static const _tokenKey = 'mvp_auth_token';
  final ValueNotifier<String?> accessToken = ValueNotifier<String?>(null);

  Future<void> restoreSession() async {
    final stored = await _storage.read(key: _tokenKey);
    accessToken.value = stored;
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _dio.post(ApiPaths.authRegister, data: {
      'email': email,
      'password': password,
      'display_name': displayName,
    });
  }

  Future<void> login({required String email, required String password}) async {
    final response = await _dio.post(ApiPaths.authLogin, data: {
      'email': email,
      'password': password,
    });
    final token = response.data['access_token'] as String?;
    if (token == null) {
      throw StateError('access_token saknas i svaret');
    }
    await _storage.write(key: _tokenKey, value: token);
    accessToken.value = token;
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    accessToken.value = null;
  }

  Future<ProfileSummary> fetchProfile() async {
    final response = await _dio.get(ApiPaths.authMe);
    return ProfileSummary.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<CourseSummary>> listMyCourses() async {
    final response = await _dio.get('/courses/me');
    final items = response.data['items'] as List<dynamic>?;
    if (items == null) {
      return const [];
    }
    return items
        .map((json) => CourseSummary.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<ServiceSummary>> listActiveServices() async {
    final response = await _dio.get('/services', queryParameters: {'status': 'active'});
    final items = response.data['items'] as List<dynamic>?;
    if (items == null) {
      return const [];
    }
    return items
        .map((json) => ServiceSummary.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<FeedActivity>> fetchFeed({int limit = 10}) async {
    final response = await _dio.get('/feed', queryParameters: {'limit': limit});
    final items = response.data['items'] as List<dynamic>?;
    if (items == null) {
      return const [];
    }
    return items
        .map((json) => FeedActivity.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<OrderReceipt> createOrderForService(String serviceId) async {
    final response = await _dio.post(ApiPaths.orders, data: {'service_id': serviceId});
    return OrderReceipt.fromJson(response.data['order'] as Map<String, dynamic>);
  }

  Future<String> createStripeCheckout({
    required String orderId,
    required String successUrl,
    required String cancelUrl,
  }) async {
    if (successUrl.isEmpty || cancelUrl.isEmpty) {
      throw StateError('Checkout-URL saknar callback-adresser.');
    }
    final orderResponse = await _dio.get(ApiPaths.order(orderId));
    final order = orderResponse.data['order'] as Map<String, dynamic>;
    final serviceId = order['service_id'] as String?;
    final courseId = order['course_id'] as String?;
    final slug = serviceId ?? courseId;
    final type = serviceId != null ? 'service' : 'course';
    if (slug == null || slug.isEmpty) {
      throw StateError('Ordern saknar checkout-detaljer.');
    }
    final response = await _dio.post(ApiPaths.checkoutCreate, data: {
      'type': type,
      'slug': slug,
    });
    return response.data['url'] as String;
  }

  Future<LiveKitTokenPayload> requestLiveKitToken(String seminarId) async {
    final response = await _dio.post('/sfu/token', data: {
      'seminar_id': seminarId,
    });
    return LiveKitTokenPayload.fromJson(response.data as Map<String, dynamic>);
  }

  String get baseUrl => _config.baseUrl;
}

class ProfileSummary {
  const ProfileSummary({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.role,
  });

  factory ProfileSummary.fromJson(Map<String, dynamic> json) {
    return ProfileSummary(
      userId: json['user_id'] as String,
      email: json['email'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      role: json['role_v2'] as String? ?? json['role'] as String? ?? 'student',
    );
  }

  final String userId;
  final String email;
  final String displayName;
  final String role;
}

class CourseSummary {
  const CourseSummary({
    required this.id,
    required this.title,
    required this.progressPercent,
  });

  factory CourseSummary.fromJson(Map<String, dynamic> json) {
    return CourseSummary(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled course',
      progressPercent: (json['progress_percent'] as num?)?.toDouble() ?? 0,
    );
  }

  final String id;
  final String title;
  final double progressPercent;
}

class ServiceSummary {
  const ServiceSummary({
    required this.id,
    required this.title,
    required this.priceCents,
    required this.currency,
    required this.description,
  });

  factory ServiceSummary.fromJson(Map<String, dynamic> json) {
    return ServiceSummary(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Service',
      priceCents: (json['price_cents'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'sek',
      description: json['description'] as String? ?? '',
    );
  }

  final String id;
  final String title;
  final int priceCents;
  final String currency;
  final String description;
}

class FeedActivity {
  const FeedActivity({
    required this.id,
    required this.summary,
    required this.occurredAt,
  });

  factory FeedActivity.fromJson(Map<String, dynamic> json) {
    return FeedActivity(
      id: '${json['id']}',
      summary: json['summary'] as String? ?? 'Aktivitet',
      occurredAt: DateTime.tryParse(json['occurred_at']?.toString() ?? ''),
    );
  }

  final String id;
  final String summary;
  final DateTime? occurredAt;
}

class OrderReceipt {
  const OrderReceipt({required this.id, required this.status, required this.amount});

  factory OrderReceipt.fromJson(Map<String, dynamic> json) {
    return OrderReceipt(
      id: json['id'] as String,
      status: json['status'] as String? ?? 'pending',
      amount: (json['amount_cents'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String status;
  final int amount;
}

class LiveKitTokenPayload {
  const LiveKitTokenPayload({required this.wsUrl, required this.token});

  factory LiveKitTokenPayload.fromJson(Map<String, dynamic> json) {
    return LiveKitTokenPayload(
      wsUrl: json['ws_url'] as String,
      token: json['token'] as String,
    );
  }

  final String wsUrl;
  final String token;
}
