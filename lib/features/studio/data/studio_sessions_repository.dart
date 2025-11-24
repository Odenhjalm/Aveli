import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/errors/app_failure.dart';

enum StudioSessionVisibility { draft, published }

StudioSessionVisibility _visibilityFromString(String? value) {
  switch (value) {
    case 'published':
      return StudioSessionVisibility.published;
    default:
      return StudioSessionVisibility.draft;
  }
}

DateTime? _parseDateTime(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}

class StudioSession {
  const StudioSession({
    required this.id,
    required this.title,
    required this.description,
    required this.startAt,
    required this.endAt,
    required this.capacity,
    required this.priceCents,
    required this.currency,
    required this.visibility,
    required this.recordingUrl,
    required this.teacherId,
    required this.stripePriceId,
  });

  final String id;
  final String title;
  final String? description;
  final DateTime? startAt;
  final DateTime? endAt;
  final int? capacity;
  final int priceCents;
  final String currency;
  final StudioSessionVisibility visibility;
  final String? recordingUrl;
  final String? teacherId;
  final String? stripePriceId;

  bool get isPublished => visibility == StudioSessionVisibility.published;

  factory StudioSession.fromJson(Map<String, dynamic> json) {
    return StudioSession(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Session',
      description: json['description'] as String?,
      startAt: _parseDateTime(json['start_at']),
      endAt: _parseDateTime(json['end_at']),
      capacity: (json['capacity'] as num?)?.toInt(),
      priceCents: (json['price_cents'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] as String? ?? 'sek').toLowerCase(),
      visibility: _visibilityFromString(json['visibility'] as String?),
      recordingUrl: json['recording_url'] as String?,
      teacherId: json['teacher_id'] as String?,
      stripePriceId: json['stripe_price_id'] as String?,
    );
  }
}

class StudioSessionSlot {
  const StudioSessionSlot({
    required this.id,
    required this.sessionId,
    required this.startAt,
    required this.endAt,
    required this.seatsTotal,
    required this.seatsTaken,
  });

  final String id;
  final String sessionId;
  final DateTime startAt;
  final DateTime endAt;
  final int seatsTotal;
  final int seatsTaken;

  bool get isFull => seatsTotal > 0 && seatsTaken >= seatsTotal;

  factory StudioSessionSlot.fromJson(Map<String, dynamic> json) {
    final startAt = _parseDateTime(json['start_at']);
    final endAt = _parseDateTime(json['end_at']);
    return StudioSessionSlot(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      startAt: startAt ?? DateTime.now(),
      endAt: endAt ?? DateTime.now().add(const Duration(minutes: 45)),
      seatsTotal: (json['seats_total'] as num?)?.toInt() ?? 0,
      seatsTaken: (json['seats_taken'] as num?)?.toInt() ?? 0,
    );
  }
}

class SessionsRepository {
  SessionsRepository(this._client);

  final ApiClient _client;

  Future<List<StudioSession>> listTeacherSessions({
    StudioSessionVisibility? visibility,
  }) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/studio/sessions',
        queryParameters: {
          if (visibility != null) 'visibility': visibility.name,
        },
      );
      final items = (response['items'] as List? ?? const [])
          .map(
            (item) =>
                StudioSession.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false);
      return items;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<List<StudioSession>> listPublishedSessions({
    DateTime? from,
    int limit = 30,
  }) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/sessions',
        queryParameters: {
          if (from != null) 'from_time': from.toUtc().toIso8601String(),
          'limit': limit,
        },
      );
      final items = (response['items'] as List? ?? const [])
          .map(
            (item) =>
                StudioSession.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false);
      return items;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<StudioSession> fetchPublishedSession(String sessionId) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/sessions/$sessionId',
      );
      return StudioSession.fromJson(response);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<List<StudioSessionSlot>> listTeacherSlots(String sessionId) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/studio/sessions/$sessionId/slots',
      );
      final items = (response['items'] as List? ?? const [])
          .map(
            (item) => StudioSessionSlot.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
      return items;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<List<StudioSessionSlot>> listPublicSlots(String sessionId) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/sessions/$sessionId/slots',
      );
      final items = (response['items'] as List? ?? const [])
          .map(
            (item) => StudioSessionSlot.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
      return items;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
