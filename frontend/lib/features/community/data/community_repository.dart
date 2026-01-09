import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/data/models/teacher_profile_media.dart';

class CommunityRepository {
  CommunityRepository(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listTeachers({int limit = 100}) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/community/teachers',
      queryParameters: {'limit': limit},
    );
    final items = (response['items'] as List? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    return items;
  }

  Future<Map<String, dynamic>?> getTeacher(String userId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/community/teachers/$userId',
    );
    final teacher = response['teacher'];
    if (teacher is Map) {
      return Map<String, dynamic>.from(teacher);
    }
    return null;
  }

  Future<Map<String, dynamic>> teacherDetail(String userId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/community/teachers/$userId',
    );
    final base = _client.raw.options.baseUrl;
    final teacher = (response['teacher'] as Map?)?.cast<String, dynamic>();
    final services = (response['services'] as List? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    final meditations = (response['meditations'] as List? ?? [])
        .map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          final url = map['audio_url'] as String?;
          if (url != null && url.isNotEmpty) {
            map['audio_url'] = Uri.parse(base).resolve(url).toString();
          }
          return map;
        })
        .toList(growable: false);
    final certificates = (response['certificates'] as List? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    return {
      'teacher': teacher,
      'services': services,
      'meditations': meditations,
      'certificates': certificates,
    };
  }

  Future<TeacherProfileMediaPayload> teacherProfileMedia(String userId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/community/teachers/$userId/media',
    );
    final payload = TeacherProfileMediaPayload.fromJson(response);
    final base = _client.raw.options.baseUrl;

    String? resolve(String? url) {
      if (url == null || url.isEmpty) return url;
      final parsed = Uri.tryParse(url);
      if (parsed == null) return url;
      if (parsed.hasScheme) return url;
      return Uri.parse(base).resolve(url).toString();
    }

    final updatedItems = payload.items
        .map((item) {
          final resolvedExternal = resolve(item.externalUrl);
          final resolvedCover = resolve(item.coverImageUrl);

          var source = item.source;
          final lessonSource = source.lessonMedia;
          if (lessonSource != null) {
            final updatedLesson = lessonSource.copyWith(
              downloadUrl: resolve(lessonSource.downloadUrl),
              signedUrl: resolve(lessonSource.signedUrl),
            );
            source = source.copyWith(lessonMedia: updatedLesson);
          }

          final recordingSource = source.seminarRecording;
          if (recordingSource != null) {
            final updatedRecording = recordingSource.copyWith(
              assetUrl: resolve(recordingSource.assetUrl),
            );
            source = source.copyWith(seminarRecording: updatedRecording);
          }

          return item.copyWith(
            externalUrl: resolvedExternal,
            coverImageUrl: resolvedCover,
            source: source,
          );
        })
        .toList(growable: false);

    return TeacherProfileMediaPayload(
      items: updatedItems,
      lessonMedia: payload.lessonMedia,
      seminarRecordings: payload.seminarRecordings,
    );
  }

  Future<List<Map<String, dynamic>>> listServices(String userId) async {
    final response = await _client.get<List<dynamic>>(
      '/community/teachers/$userId/services',
    );
    return response
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> serviceDetail(String serviceId) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/community/services/$serviceId',
      );
      final service = (response['service'] as Map?)?.cast<String, dynamic>();
      final provider = (response['provider'] as Map?)?.cast<String, dynamic>();
      return {'service': service, 'provider': provider};
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<List<Map<String, dynamic>>> listMeditations(String userId) async {
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
  }

  Future<Map<String, List<String>>> listVerifiedCertSpecialties(
    List<String> userIds,
  ) async {
    // Specialiteter hanteras inte i backend ännu.
    return const {};
  }

  Future<List<Map<String, dynamic>>> tarotRequests() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/community/tarot/requests',
      );
      return (response['items'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> createTarotRequest(String question) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/community/tarot/requests',
        body: {'question': question},
      );
      return response.cast<String, dynamic>();
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> profileDetail(String userId) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/community/profiles/$userId',
      );
      final base = _client.raw.options.baseUrl;
      final services = (response['services'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
      final meditations = (response['meditations'] as List? ?? [])
          .map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            final url = map['audio_url'] as String?;
            if (url != null && url.isNotEmpty) {
              map['audio_url'] = Uri.parse(base).resolve(url).toString();
            }
            return map;
          })
          .toList(growable: false);
      return {
        'profile': (response['profile'] as Map?)?.cast<String, dynamic>(),
        'is_following': response['is_following'] == true,
        'services': services,
        'meditations': meditations,
      };
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
