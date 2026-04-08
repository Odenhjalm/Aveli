import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/errors/app_failure.dart';

class AdminRepository {
  AdminRepository(this._client);

  final ApiClient _client;

  Future<void> grantTeacherRole(String userId) async {
    try {
      await _client.post<dynamic>('/admin/users/$userId/grant-teacher-role');
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<void> revokeTeacherRole(String userId) async {
    try {
      await _client.post<dynamic>('/admin/users/$userId/revoke-teacher-role');
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
