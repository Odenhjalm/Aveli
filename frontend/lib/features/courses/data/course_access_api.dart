import 'package:aveli/api/api_client.dart';

class CourseAccessApi {
  CourseAccessApi(this._client);

  final ApiClient _client;

  Future<bool> hasAccess(String courseId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/courses/$courseId/access',
    );
    return res['has_access'] == true;
  }

  Future<bool> fallbackHasAccess(String courseId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/courses/$courseId/access',
    );
    return res['has_access'] == true;
  }
}
