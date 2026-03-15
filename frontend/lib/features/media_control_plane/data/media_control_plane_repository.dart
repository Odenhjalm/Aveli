import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/errors/app_failure.dart';

class MediaControlPlaneRepository {
  MediaControlPlaneRepository(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> fetchHealth() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/admin/media/health',
      );
      return Map<String, dynamic>.from(response ?? const <String, dynamic>{});
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
