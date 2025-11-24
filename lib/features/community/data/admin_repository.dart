import 'package:wisdom/api/api_client.dart';
import 'package:wisdom/core/errors/app_failure.dart';

class AdminRepository {
  AdminRepository(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> fetchDashboard() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/admin/dashboard',
      );
      return response;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<void> approveTeacher(String userId) async {
    try {
      await _client.post('/admin/teachers/$userId/approve');
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<void> rejectTeacher(String userId) async {
    try {
      await _client.post('/admin/teachers/$userId/reject');
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<void> updateCertificateStatus({
    required String certificateId,
    required String status,
  }) async {
    try {
      await _client.patch(
        '/admin/certificates/$certificateId',
        body: {'status': status},
      );
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> fetchSettings() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/admin/settings',
      );
      return response;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> updateTeacherPriority({
    required String teacherId,
    required int priority,
    String? notes,
  }) async {
    try {
      final response = await _client.patch<Map<String, dynamic>>(
        '/admin/teachers/$teacherId/priority',
        body: {
          'priority': priority,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );
      return Map<String, dynamic>.from(response ?? const <String, dynamic>{});
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> clearTeacherPriority(String teacherId) async {
    try {
      final response = await _client.delete<Map<String, dynamic>>(
        '/admin/teachers/$teacherId/priority',
      );
      return Map<String, dynamic>.from(response ?? const <String, dynamic>{});
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
