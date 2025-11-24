import 'package:wisdom/api/api_client.dart';
import 'package:wisdom/core/errors/app_failure.dart';

class MeditationsRepository {
  MeditationsRepository(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> publicMeditations({int limit = 50}) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/community/meditations/public',
        queryParameters: {'limit': limit},
      );
      final base = _client.raw.options.baseUrl;
      return (response['items'] as List? ?? [])
          .map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            final url = map['audio_url'] as String?;
            if (url != null && url.isNotEmpty) {
              map['audio_url'] = Uri.parse(base).resolve(url).toString();
            }
            return map;
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<List<Map<String, dynamic>>> byTeacher(String userId) async {
    try {
      final response = await _client.get<List<dynamic>>(
        '/community/teachers/$userId/meditations',
      );
      final base = _client.raw.options.baseUrl;
      return response
          .map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            final url = map['audio_url'] as String?;
            if (url != null && url.isNotEmpty) {
              map['audio_url'] = Uri.parse(base).resolve(url).toString();
            }
            return map;
          })
          .toList(growable: false);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
