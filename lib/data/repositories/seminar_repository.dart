import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/api/api_client.dart';
import 'package:wisdom/api/auth_repository.dart';
import 'package:wisdom/data/models/seminar.dart';

class SeminarRepository {
  const SeminarRepository(this._client);

  final ApiClient _client;

  Future<List<Seminar>> listHostSeminars() async {
    final response = await _client.get<Map<String, dynamic>>(
      '/studio/seminars',
    );
    final items = (response['items'] as List<dynamic>? ?? [])
        .map((item) => item as Map<String, dynamic>)
        .toList();
    return items.map(Seminar.fromJson).toList();
  }

  Future<SeminarDetail> getSeminarDetail(String id) async {
    final Map<String, dynamic> response = await _client
        .get<Map<String, dynamic>>('/studio/seminars/$id');
    return SeminarDetail.fromJson(response);
  }

  Future<Seminar> createSeminar({
    required String title,
    String? description,
    DateTime? scheduledAt,
    int? durationMinutes,
  }) async {
    final response = await _client.post<Map<String, dynamic>?>(
      '/studio/seminars',
      body: {
        'title': title,
        if (description != null) 'description': description,
        if (scheduledAt != null) 'scheduled_at': scheduledAt.toIso8601String(),
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
      },
    );
    if (response == null) {
      throw StateError('Seminar creation returned empty response');
    }
    return Seminar.fromJson(response);
  }

  Future<Seminar> updateSeminar({
    required String id,
    String? title,
    String? description,
    DateTime? scheduledAt,
    int? durationMinutes,
  }) async {
    final response = await _client.patch<Map<String, dynamic>?>(
      '/studio/seminars/$id',
      body: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (scheduledAt != null) 'scheduled_at': scheduledAt.toIso8601String(),
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
      },
    );
    if (response == null) {
      throw StateError('Seminar update returned empty response');
    }
    return Seminar.fromJson(response);
  }

  Future<Seminar> publishSeminar(String id) async {
    final response = await _client.post<Map<String, dynamic>?>(
      '/studio/seminars/$id/publish',
    );
    if (response == null) {
      throw StateError('Seminar publish returned empty response');
    }
    return Seminar.fromJson(response);
  }

  Future<Seminar> cancelSeminar(String id) async {
    final response = await _client.post<Map<String, dynamic>?>(
      '/studio/seminars/$id/cancel',
    );
    if (response == null) {
      throw StateError('Seminar cancel returned empty response');
    }
    return Seminar.fromJson(response);
  }

  Future<SeminarSessionStartResult> startSession(
    String seminarId, {
    String? sessionId,
    int? maxParticipants,
  }) async {
    final response = await _client.post<Map<String, dynamic>?>(
      '/studio/seminars/$seminarId/sessions/start',
      body: {
        if (sessionId != null) 'session_id': sessionId,
        if (maxParticipants != null) 'max_participants': maxParticipants,
      },
    );
    if (response == null) {
      throw StateError('Start session returned empty response');
    }
    return SeminarSessionStartResult.fromJson(response);
  }

  Future<SeminarSession> endSession(
    String seminarId,
    String sessionId, {
    String? reason,
  }) async {
    final response = await _client.post<Map<String, dynamic>?>(
      '/studio/seminars/$seminarId/sessions/$sessionId/end',
      body: {if (reason != null) 'reason': reason},
    );
    if (response == null) {
      throw StateError('End session returned empty response');
    }
    return SeminarSession.fromJson(response);
  }

  Future<SeminarRecording> reserveRecording(
    String seminarId, {
    String? sessionId,
    String? extension,
  }) async {
    final response = await _client.post<Map<String, dynamic>?>(
      '/studio/seminars/$seminarId/recordings/reserve',
      body: {
        if (sessionId != null) 'session_id': sessionId,
        if (extension != null) 'extension': extension,
      },
    );
    if (response == null) {
      throw StateError('Reserve recording returned empty response');
    }
    return SeminarRecording.fromJson(response);
  }

  Future<SeminarRegistration> grantSeminarAccess({
    required String seminarId,
    required String userId,
    String role = 'participant',
    String inviteStatus = 'accepted',
  }) async {
    final response = await _client.post<Map<String, dynamic>?>(
      '/studio/seminars/$seminarId/attendees',
      body: {'user_id': userId, 'role': role, 'invite_status': inviteStatus},
    );
    if (response == null) {
      throw StateError('Grant seminar access returned empty response');
    }
    return SeminarRegistration.fromJson(response);
  }

  Future<void> revokeSeminarAccess({
    required String seminarId,
    required String userId,
  }) async {
    await _client.delete<void>('/studio/seminars/$seminarId/attendees/$userId');
  }

  Future<List<Seminar>> listPublicSeminars() async {
    final Map<String, dynamic> response = await _client
        .get<Map<String, dynamic>>('/seminars');
    final items = (response['items'] as List<dynamic>? ?? [])
        .map((item) => item as Map<String, dynamic>)
        .toList();
    return items.map(Seminar.fromJson).toList();
  }

  Future<SeminarDetail> getPublicSeminar(String id) async {
    final Map<String, dynamic> response = await _client
        .get<Map<String, dynamic>>('/seminars/$id');
    return SeminarDetail.fromJson(response);
  }

  Future<SeminarRegistration> registerForSeminar(String id) async {
    final response = await _client.post<Map<String, dynamic>?>(
      '/seminars/$id/register',
    );
    if (response == null) {
      throw StateError('Register seminar returned empty response');
    }
    return SeminarRegistration.fromJson(response);
  }

  Future<void> unregisterFromSeminar(String id) async {
    await _client.delete<void>('/seminars/$id/register');
  }
}

final seminarRepositoryProvider = Provider<SeminarRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return SeminarRepository(client);
});
