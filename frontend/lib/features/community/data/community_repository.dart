import 'package:aveli/api/api_client.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';

class CommunityRepository {
  CommunityRepository(ApiClient _);

  Future<T> _unsupportedRuntime<T>(String surface) {
    return Future<T>.error(
      UnsupportedError('$surface is inert in mounted runtime'),
    );
  }

  Future<List<Map<String, dynamic>>> listTeachers({int limit = 100}) async {
    return _unsupportedRuntime('Community teachers');
  }

  Future<Map<String, dynamic>?> getTeacher(String userId) async {
    return _unsupportedRuntime('Community teacher detail');
  }

  Future<Map<String, dynamic>> teacherDetail(String userId) async {
    return _unsupportedRuntime('Community teacher detail');
  }

  Future<TeacherProfileMediaPayload> teacherProfileMedia(String userId) async {
    return _unsupportedRuntime('Community teacher profile media');
  }

  Future<List<Map<String, dynamic>>> listServices(String userId) async {
    return _unsupportedRuntime('Community teacher services');
  }

  Future<Map<String, dynamic>> serviceDetail(String serviceId) async {
    return _unsupportedRuntime('Community service detail');
  }

  Future<List<Map<String, dynamic>>> listMeditations(String userId) async {
    return _unsupportedRuntime('Community meditations');
  }

  Future<Map<String, List<String>>> listVerifiedCertSpecialties(
    List<String> userIds,
  ) async {
    // Specialiteter hanteras inte i backend ännu.
    return const {};
  }

  Future<List<Map<String, dynamic>>> tarotRequests() async {
    return _unsupportedRuntime('Community tarot requests');
  }

  Future<Map<String, dynamic>> createTarotRequest(String question) async {
    return _unsupportedRuntime('Community tarot requests');
  }

  Future<Map<String, dynamic>> profileDetail(String userId) async {
    return _unsupportedRuntime('Community profile detail');
  }
}
