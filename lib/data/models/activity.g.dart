// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Activity _$ActivityFromJson(Map<String, dynamic> json) => Activity(
  id: json['id'] as String,
  type: json['activity_type'] as String,
  summary: json['summary'] as String,
  occurredAt: parseDateTime(json['occurred_at']),
  actorId: json['actor_id'] as String?,
  subjectTable: json['subject_table'] as String?,
  subjectId: json['subject_id'] as String?,
  metadata: json['metadata'] == null ? {} : mapFromJson(json['metadata']),
);

Map<String, dynamic> _$ActivityToJson(Activity instance) => <String, dynamic>{
  'id': instance.id,
  'activity_type': instance.type,
  'summary': instance.summary,
  'occurred_at': dateTimeToIsoString(instance.occurredAt),
  'actor_id': instance.actorId,
  'subject_table': instance.subjectTable,
  'subject_id': instance.subjectId,
  'metadata': instance.metadata,
};
