import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/errors/app_failure.dart';

enum StudioSessionVisibility { draft, published }

Object? _requiredField(Object? payload, String fieldName) {
  switch (payload) {
    case final Map<Object?, Object?> data when data.containsKey(fieldName):
      return data[fieldName];
    case final Map<Object?, Object?> _:
      throw StateError('Missing required field: $fieldName');
    default:
      throw StateError('Invalid payload for $fieldName');
  }
}

Object? _optionalField(Object? payload, String fieldName) {
  switch (payload) {
    case final Map<Object?, Object?> data when data.containsKey(fieldName):
      return data[fieldName];
    case final Map<Object?, Object?> _:
      return null;
    default:
      throw StateError('Invalid payload for $fieldName');
  }
}

List<Object?> _requireList(Object? value, String fieldName) {
  switch (value) {
    case final List items:
      return List<Object?>.unmodifiable(items);
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

StudioSessionVisibility _visibilityFromString(String value) {
  switch (value) {
    case 'draft':
      return StudioSessionVisibility.draft;
    case 'published':
      return StudioSessionVisibility.published;
    default:
      throw StateError('Invalid field value for visibility');
  }
}

DateTime? _parseOptionalDateTime(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    case final String text when text.trim().isNotEmpty:
      return DateTime.parse(text);
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

DateTime _parseRequiredDateTime(Object? value, String fieldName) {
  final parsed = _parseOptionalDateTime(value, fieldName);
  if (parsed == null) {
    throw StateError('Missing required field: $fieldName');
  }
  return parsed;
}

int _parseRequiredInt(Object? value, String fieldName) {
  switch (value) {
    case final int number:
      return number;
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

int? _parseOptionalInt(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    case final int number:
      return number;
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

String _parseRequiredString(Object? value, String fieldName) {
  switch (value) {
    case final String text when text.trim().isNotEmpty:
      return text;
    default:
      throw StateError('Invalid field type for $fieldName');
  }
}

String? _parseOptionalString(Object? value, String fieldName) {
  switch (value) {
    case null:
      return null;
    case final String text:
      return text;
    default:
      throw StateError('Invalid field type for $fieldName');
  }
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
  final String teacherId;
  final String? stripePriceId;

  bool get isPublished => visibility == StudioSessionVisibility.published;

  factory StudioSession.fromResponse(Object? payload) {
    return StudioSession(
      id: _parseRequiredString(_requiredField(payload, 'id'), 'id'),
      title: _parseRequiredString(_requiredField(payload, 'title'), 'title'),
      description: _parseOptionalString(
        _optionalField(payload, 'description'),
        'description',
      ),
      startAt: _parseOptionalDateTime(
        _optionalField(payload, 'start_at'),
        'start_at',
      ),
      endAt: _parseOptionalDateTime(
        _optionalField(payload, 'end_at'),
        'end_at',
      ),
      capacity: _parseOptionalInt(
        _optionalField(payload, 'capacity'),
        'capacity',
      ),
      priceCents: _parseRequiredInt(
        _requiredField(payload, 'price_cents'),
        'price_cents',
      ),
      currency: _parseRequiredString(
        _requiredField(payload, 'currency'),
        'currency',
      ),
      visibility: _visibilityFromString(
        _parseRequiredString(
          _requiredField(payload, 'visibility'),
          'visibility',
        ),
      ),
      recordingUrl: _parseOptionalString(
        _optionalField(payload, 'recording_url'),
        'recording_url',
      ),
      teacherId: _parseRequiredString(
        _requiredField(payload, 'teacher_id'),
        'teacher_id',
      ),
      stripePriceId: _parseOptionalString(
        _optionalField(payload, 'stripe_price_id'),
        'stripe_price_id',
      ),
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

  factory StudioSessionSlot.fromResponse(Object? payload) {
    return StudioSessionSlot(
      id: _parseRequiredString(_requiredField(payload, 'id'), 'id'),
      sessionId: _parseRequiredString(
        _requiredField(payload, 'session_id'),
        'session_id',
      ),
      startAt: _parseRequiredDateTime(
        _requiredField(payload, 'start_at'),
        'start_at',
      ),
      endAt: _parseRequiredDateTime(
        _requiredField(payload, 'end_at'),
        'end_at',
      ),
      seatsTotal: _parseRequiredInt(
        _requiredField(payload, 'seats_total'),
        'seats_total',
      ),
      seatsTaken: _parseRequiredInt(
        _requiredField(payload, 'seats_taken'),
        'seats_taken',
      ),
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
      final response = await _client.raw.get<Object?>(
        '/studio/sessions',
        queryParameters: {
          if (visibility != null) 'visibility': visibility.name,
        },
      );
      return _requireList(
        _requiredField(response.data, 'items'),
        'items',
      ).map(StudioSession.fromResponse).toList(growable: false);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<List<StudioSession>> listPublishedSessions({
    DateTime? from,
    int limit = 30,
  }) async {
    try {
      final response = await _client.raw.get<Object?>(
        '/sessions',
        queryParameters: {
          if (from != null) 'from_time': from.toUtc().toIso8601String(),
          'limit': limit,
        },
      );
      return _requireList(
        _requiredField(response.data, 'items'),
        'items',
      ).map(StudioSession.fromResponse).toList(growable: false);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<StudioSession> fetchPublishedSession(String sessionId) async {
    try {
      final response = await _client.raw.get<Object?>('/sessions/$sessionId');
      return StudioSession.fromResponse(response.data);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<List<StudioSessionSlot>> listTeacherSlots(String sessionId) async {
    try {
      final response = await _client.raw.get<Object?>(
        '/studio/sessions/$sessionId/slots',
      );
      return _requireList(
        _requiredField(response.data, 'items'),
        'items',
      ).map(StudioSessionSlot.fromResponse).toList(growable: false);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<List<StudioSessionSlot>> listPublicSlots(String sessionId) async {
    try {
      final response = await _client.raw.get<Object?>(
        '/sessions/$sessionId/slots',
      );
      return _requireList(
        _requiredField(response.data, 'items'),
        'items',
      ).map(StudioSessionSlot.fromResponse).toList(growable: false);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
