import 'package:aveli/api/api_client.dart';

class CourseAccessApi {
  CourseAccessApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> fetchCourseState(String courseId) async {
    return _client.get<Map<String, dynamic>>('/courses/$courseId/access');
  }
}
