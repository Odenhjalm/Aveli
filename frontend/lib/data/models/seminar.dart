import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'seminar.g.dart';

enum SeminarStatus { draft, scheduled, live, ended, canceled }

enum SeminarSessionStatus { scheduled, live, ended, canceled }

@JsonSerializable(fieldRename: FieldRename.snake)
class Seminar extends Equatable {
  const Seminar({
    required this.id,
    required this.hostId,
    this.hostDisplayName,
    required this.title,
    this.description,
    required this.status,
    this.scheduledAt,
    this.durationMinutes,
    this.livekitRoom,
    this.livekitMetadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory Seminar.fromJson(Map<String, dynamic> json) =>
      _$SeminarFromJson(json);

  Map<String, dynamic> toJson() => _$SeminarToJson(this);

  final String id;
  final String hostId;
  final String? hostDisplayName;
  final String title;
  final String? description;
  final SeminarStatus status;
  final DateTime? scheduledAt;
  final int? durationMinutes;
  final String? livekitRoom;
  @JsonKey(defaultValue: <String, dynamic>{})
  final Map<String, dynamic> livekitMetadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  List<Object?> get props => [
    id,
    hostId,
    hostDisplayName,
    title,
    description,
    status,
    scheduledAt,
    durationMinutes,
    livekitRoom,
    livekitMetadata,
    createdAt,
    updatedAt,
  ];
}

@JsonSerializable(fieldRename: FieldRename.snake)
class SeminarSession extends Equatable {
  const SeminarSession({
    required this.id,
    required this.seminarId,
    required this.status,
    this.scheduledAt,
    this.startedAt,
    this.endedAt,
    this.livekitRoom,
    this.livekitSid,
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory SeminarSession.fromJson(Map<String, dynamic> json) =>
      _$SeminarSessionFromJson(json);

  Map<String, dynamic> toJson() => _$SeminarSessionToJson(this);

  final String id;
  final String seminarId;
  final SeminarSessionStatus status;
  final DateTime? scheduledAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? livekitRoom;
  final String? livekitSid;
  @JsonKey(defaultValue: <String, dynamic>{})
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  List<Object?> get props => [
    id,
    seminarId,
    status,
    scheduledAt,
    startedAt,
    endedAt,
    livekitRoom,
    livekitSid,
    metadata,
    createdAt,
    updatedAt,
  ];
}

@JsonSerializable(fieldRename: FieldRename.snake)
class SeminarRegistration extends Equatable {
  const SeminarRegistration({
    required this.seminarId,
    required this.userId,
    required this.role,
    required this.inviteStatus,
    this.joinedAt,
    this.leftAt,
    this.livekitIdentity,
    this.livekitParticipantSid,
    required this.createdAt,
    this.displayName,
    this.email,
    this.hostCourseTitles = const <String>[],
  });

  factory SeminarRegistration.fromJson(Map<String, dynamic> json) =>
      _$SeminarRegistrationFromJson(json);

  Map<String, dynamic> toJson() => _$SeminarRegistrationToJson(this);

  final String seminarId;
  final String userId;
  final String role;
  final String inviteStatus;
  final DateTime? joinedAt;
  final DateTime? leftAt;
  final String? livekitIdentity;
  final String? livekitParticipantSid;
  final DateTime createdAt;
  final String? displayName;
  final String? email;
  @JsonKey(defaultValue: <String>[])
  final List<String> hostCourseTitles;

  @override
  List<Object?> get props => [
    seminarId,
    userId,
    role,
    inviteStatus,
    joinedAt,
    leftAt,
    livekitIdentity,
    livekitParticipantSid,
    createdAt,
    displayName,
    email,
    hostCourseTitles,
  ];
}

@JsonSerializable(fieldRename: FieldRename.snake)
class SeminarRecording extends Equatable {
  const SeminarRecording({
    required this.id,
    required this.seminarId,
    this.sessionId,
    required this.assetUrl,
    required this.status,
    this.durationSeconds,
    this.byteSize,
    required this.published,
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory SeminarRecording.fromJson(Map<String, dynamic> json) =>
      _$SeminarRecordingFromJson(json);

  Map<String, dynamic> toJson() => _$SeminarRecordingToJson(this);

  final String id;
  final String seminarId;
  final String? sessionId;
  final String assetUrl;
  final String status;
  final int? durationSeconds;
  final int? byteSize;
  final bool published;
  @JsonKey(defaultValue: <String, dynamic>{})
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  List<Object?> get props => [
    id,
    seminarId,
    sessionId,
    assetUrl,
    status,
    durationSeconds,
    byteSize,
    published,
    metadata,
    createdAt,
    updatedAt,
  ];
}

@JsonSerializable(fieldRename: FieldRename.snake)
class SeminarDetail extends Equatable {
  const SeminarDetail({
    required this.seminar,
    required this.sessions,
    required this.attendees,
    required this.recordings,
  });

  factory SeminarDetail.fromJson(Map<String, dynamic> json) =>
      _$SeminarDetailFromJson(json);

  Map<String, dynamic> toJson() => _$SeminarDetailToJson(this);

  final Seminar seminar;
  final List<SeminarSession> sessions;
  final List<SeminarRegistration> attendees;
  final List<SeminarRecording> recordings;

  @override
  List<Object?> get props => [seminar, sessions, attendees, recordings];
}

@JsonSerializable(fieldRename: FieldRename.snake)
class SeminarSessionStartResult extends Equatable {
  const SeminarSessionStartResult({
    required this.session,
    required this.wsUrl,
    required this.token,
  });

  factory SeminarSessionStartResult.fromJson(Map<String, dynamic> json) =>
      _$SeminarSessionStartResultFromJson(json);

  Map<String, dynamic> toJson() => _$SeminarSessionStartResultToJson(this);

  final SeminarSession session;
  final String wsUrl;
  final String token;

  @override
  List<Object?> get props => [session, wsUrl, token];
}
