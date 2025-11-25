// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seminar.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Seminar _$SeminarFromJson(Map<String, dynamic> json) => Seminar(
  id: json['id'] as String,
  hostId: json['host_id'] as String,
  hostDisplayName: json['host_display_name'] as String?,
  title: json['title'] as String,
  description: json['description'] as String?,
  status: $enumDecode(_$SeminarStatusEnumMap, json['status']),
  scheduledAt: json['scheduled_at'] == null
      ? null
      : DateTime.parse(json['scheduled_at'] as String),
  durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
  livekitRoom: json['livekit_room'] as String?,
  livekitMetadata: json['livekit_metadata'] as Map<String, dynamic>? ?? {},
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
);

Map<String, dynamic> _$SeminarToJson(Seminar instance) => <String, dynamic>{
  'id': instance.id,
  'host_id': instance.hostId,
  'host_display_name': instance.hostDisplayName,
  'title': instance.title,
  'description': instance.description,
  'status': _$SeminarStatusEnumMap[instance.status]!,
  'scheduled_at': instance.scheduledAt?.toIso8601String(),
  'duration_minutes': instance.durationMinutes,
  'livekit_room': instance.livekitRoom,
  'livekit_metadata': instance.livekitMetadata,
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt.toIso8601String(),
};

const _$SeminarStatusEnumMap = {
  SeminarStatus.draft: 'draft',
  SeminarStatus.scheduled: 'scheduled',
  SeminarStatus.live: 'live',
  SeminarStatus.ended: 'ended',
  SeminarStatus.canceled: 'canceled',
};

SeminarSession _$SeminarSessionFromJson(Map<String, dynamic> json) =>
    SeminarSession(
      id: json['id'] as String,
      seminarId: json['seminar_id'] as String,
      status: $enumDecode(_$SeminarSessionStatusEnumMap, json['status']),
      scheduledAt: json['scheduled_at'] == null
          ? null
          : DateTime.parse(json['scheduled_at'] as String),
      startedAt: json['started_at'] == null
          ? null
          : DateTime.parse(json['started_at'] as String),
      endedAt: json['ended_at'] == null
          ? null
          : DateTime.parse(json['ended_at'] as String),
      livekitRoom: json['livekit_room'] as String?,
      livekitSid: json['livekit_sid'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$SeminarSessionToJson(SeminarSession instance) =>
    <String, dynamic>{
      'id': instance.id,
      'seminar_id': instance.seminarId,
      'status': _$SeminarSessionStatusEnumMap[instance.status]!,
      'scheduled_at': instance.scheduledAt?.toIso8601String(),
      'started_at': instance.startedAt?.toIso8601String(),
      'ended_at': instance.endedAt?.toIso8601String(),
      'livekit_room': instance.livekitRoom,
      'livekit_sid': instance.livekitSid,
      'metadata': instance.metadata,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

const _$SeminarSessionStatusEnumMap = {
  SeminarSessionStatus.scheduled: 'scheduled',
  SeminarSessionStatus.live: 'live',
  SeminarSessionStatus.ended: 'ended',
  SeminarSessionStatus.canceled: 'canceled',
};

SeminarRegistration _$SeminarRegistrationFromJson(Map<String, dynamic> json) =>
    SeminarRegistration(
      seminarId: json['seminar_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      inviteStatus: json['invite_status'] as String,
      joinedAt: json['joined_at'] == null
          ? null
          : DateTime.parse(json['joined_at'] as String),
      leftAt: json['left_at'] == null
          ? null
          : DateTime.parse(json['left_at'] as String),
      livekitIdentity: json['livekit_identity'] as String?,
      livekitParticipantSid: json['livekit_participant_sid'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      displayName: json['profile_display_name'] as String?,
      email: json['profile_email'] as String?,
      hostCourseTitles: (json['host_course_titles'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$SeminarRegistrationToJson(
  SeminarRegistration instance,
) => <String, dynamic>{
  'seminar_id': instance.seminarId,
  'user_id': instance.userId,
  'role': instance.role,
  'invite_status': instance.inviteStatus,
  'joined_at': instance.joinedAt?.toIso8601String(),
  'left_at': instance.leftAt?.toIso8601String(),
  'livekit_identity': instance.livekitIdentity,
  'livekit_participant_sid': instance.livekitParticipantSid,
  'created_at': instance.createdAt.toIso8601String(),
  'profile_display_name': instance.displayName,
  'profile_email': instance.email,
  'host_course_titles': instance.hostCourseTitles,
};

SeminarRecording _$SeminarRecordingFromJson(Map<String, dynamic> json) =>
    SeminarRecording(
      id: json['id'] as String,
      seminarId: json['seminar_id'] as String,
      sessionId: json['session_id'] as String?,
      assetUrl: json['asset_url'] as String,
      status: json['status'] as String,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      byteSize: (json['byte_size'] as num?)?.toInt(),
      published: json['published'] as bool,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$SeminarRecordingToJson(SeminarRecording instance) =>
    <String, dynamic>{
      'id': instance.id,
      'seminar_id': instance.seminarId,
      'session_id': instance.sessionId,
      'asset_url': instance.assetUrl,
      'status': instance.status,
      'duration_seconds': instance.durationSeconds,
      'byte_size': instance.byteSize,
      'published': instance.published,
      'metadata': instance.metadata,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

SeminarDetail _$SeminarDetailFromJson(Map<String, dynamic> json) =>
    SeminarDetail(
      seminar: Seminar.fromJson(json['seminar'] as Map<String, dynamic>),
      sessions: (json['sessions'] as List<dynamic>)
          .map((e) => SeminarSession.fromJson(e as Map<String, dynamic>))
          .toList(),
      attendees: (json['attendees'] as List<dynamic>)
          .map((e) => SeminarRegistration.fromJson(e as Map<String, dynamic>))
          .toList(),
      recordings: (json['recordings'] as List<dynamic>)
          .map((e) => SeminarRecording.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$SeminarDetailToJson(SeminarDetail instance) =>
    <String, dynamic>{
      'seminar': instance.seminar,
      'sessions': instance.sessions,
      'attendees': instance.attendees,
      'recordings': instance.recordings,
    };

SeminarSessionStartResult _$SeminarSessionStartResultFromJson(
  Map<String, dynamic> json,
) => SeminarSessionStartResult(
  session: SeminarSession.fromJson(json['session'] as Map<String, dynamic>),
  wsUrl: json['ws_url'] as String,
  token: json['token'] as String,
);

Map<String, dynamic> _$SeminarSessionStartResultToJson(
  SeminarSessionStartResult instance,
) => <String, dynamic>{
  'session': instance.session,
  'ws_url': instance.wsUrl,
  'token': instance.token,
};
