import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/data/models/seminar.dart';

class SeminarRepository {
  const SeminarRepository(ApiClient _);

  Future<T> _unsupportedRuntime<T>(String surface) {
    return Future<T>.error(
      UnsupportedError('$surface is inert in mounted runtime'),
    );
  }

  Future<List<Seminar>> listHostSeminars() async {
    return const <Seminar>[];
  }

  Future<SeminarDetail> getSeminarDetail(String id) async {
    return _unsupportedRuntime('Studio seminars');
  }

  Future<Seminar> createSeminar({
    required String title,
    String? description,
    DateTime? scheduledAt,
    int? durationMinutes,
  }) async {
    return _unsupportedRuntime('Studio seminars');
  }

  Future<Seminar> updateSeminar({
    required String id,
    String? title,
    String? description,
    DateTime? scheduledAt,
    int? durationMinutes,
  }) async {
    return _unsupportedRuntime('Studio seminars');
  }

  Future<Seminar> publishSeminar(String id) async {
    return _unsupportedRuntime('Studio seminars');
  }

  Future<Seminar> cancelSeminar(String id) async {
    return _unsupportedRuntime('Studio seminars');
  }

  Future<SeminarSessionStartResult> startSession(
    String seminarId, {
    String? sessionId,
    int? maxParticipants,
  }) async {
    return _unsupportedRuntime('Studio seminar sessions');
  }

  Future<SeminarSession> endSession(
    String seminarId,
    String sessionId, {
    String? reason,
  }) async {
    return _unsupportedRuntime('Studio seminar sessions');
  }

  Future<SeminarRecording> reserveRecording(
    String seminarId, {
    String? sessionId,
    String? extension,
  }) async {
    return _unsupportedRuntime('Studio seminar recordings');
  }

  Future<SeminarRegistration> grantSeminarAccess({
    required String seminarId,
    required String userId,
    String role = 'participant',
    String inviteStatus = 'accepted',
  }) async {
    return _unsupportedRuntime('Studio seminar attendees');
  }

  Future<void> revokeSeminarAccess({
    required String seminarId,
    required String userId,
  }) async {
    return _unsupportedRuntime('Studio seminar attendees');
  }

  Future<List<Seminar>> listPublicSeminars() async {
    return const <Seminar>[];
  }

  Future<SeminarDetail> getPublicSeminar(String id) async {
    return _unsupportedRuntime('Public seminars');
  }

  Future<SeminarRegistration> registerForSeminar(String id) async {
    return _unsupportedRuntime('Public seminars');
  }

  Future<void> unregisterFromSeminar(String id) async {
    return _unsupportedRuntime('Public seminars');
  }
}

final seminarRepositoryProvider = Provider<SeminarRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return SeminarRepository(client);
});
