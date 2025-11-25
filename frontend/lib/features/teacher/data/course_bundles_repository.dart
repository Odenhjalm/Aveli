import 'package:wisdom/api/api_client.dart';

class CourseBundlesRepository {
  CourseBundlesRepository(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> myBundles() async {
    final res = await _client.get<Map<String, dynamic>>(
      '/api/teachers/course-bundles',
    );
    final items = res['items'] as List? ?? const [];
    return items
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createBundle({
    required String title,
    String? description,
    required int priceAmountCents,
    String currency = 'sek',
    List<String> courseIds = const [],
    bool isActive = true,
  }) async {
    final body = {
      'title': title,
      if (description != null) 'description': description,
      'price_amount_cents': priceAmountCents,
      'currency': currency,
      'course_ids': courseIds,
      'is_active': isActive,
    };
    final res = await _client.post<Map<String, dynamic>>(
      '/api/teachers/course-bundles',
      body: body,
    );
    return Map<String, dynamic>.from(res);
  }

  Future<Map<String, dynamic>> addCourse({
    required String bundleId,
    required String courseId,
    int? position,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/teachers/course-bundles/$bundleId/courses',
      body: {
        'course_id': courseId,
        if (position != null) 'position': position,
      },
    );
    return Map<String, dynamic>.from(res);
  }

  Future<Map<String, dynamic>> getBundle(String bundleId, {bool skipAuth = false}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/api/course-bundles/$bundleId',
      skipAuth: skipAuth,
    );
    return Map<String, dynamic>.from(res);
  }
}
