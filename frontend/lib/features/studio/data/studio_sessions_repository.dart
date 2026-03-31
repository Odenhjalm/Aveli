import 'package:aveli/api/api_client.dart';

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
        _requiredField(payload, 'description'),
        'description',
      ),
      startAt: _parseOptionalDateTime(
        _requiredField(payload, 'start_at'),
        'start_at',
      ),
      endAt: _parseOptionalDateTime(
        _requiredField(payload, 'end_at'),
        'end_at',
      ),
      capacity: _parseOptionalInt(
        _requiredField(payload, 'capacity'),
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
        _requiredField(payload, 'recording_url'),
        'recording_url',
      ),
      teacherId: _parseRequiredString(
        _requiredField(payload, 'teacher_id'),
        'teacher_id',
      ),
      stripePriceId: _parseOptionalString(
        _requiredField(payload, 'stripe_price_id'),
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
  SessionsRepository(ApiClient _);

  Future<T> _unsupportedRuntime<T>(String surface) {
    return Future<T>.error(
      UnsupportedError('$surface is inert in mounted runtime'),
    );
  }

  Future<List<StudioSession>> listTeacherSessions({
    StudioSessionVisibility? visibility,
  }) async {
    return _unsupportedRuntime('Studio sessions');
  }

  Future<List<StudioSession>> listPublishedSessions({
    DateTime? from,
    int limit = 30,
  }) async {
    return _unsupportedRuntime('Published sessions');
  }

  Future<StudioSession> fetchPublishedSession(String sessionId) async {
    return _unsupportedRuntime('Published session detail');
  }

  Future<List<StudioSessionSlot>> listTeacherSlots(String sessionId) async {
    return _unsupportedRuntime('Studio session slots');
  }

  Future<List<StudioSessionSlot>> listPublicSlots(String sessionId) async {
    return _unsupportedRuntime('Published session slots');
  }
}
