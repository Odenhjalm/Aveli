// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'certificate.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Certificate _$CertificateFromJson(Map<String, dynamic> json) => Certificate(
  id: json['id'] as String,
  userId: json['user_id'] as String,
  title: json['title'] as String,
  status: _certificateStatusFromJson(json['status'] as String?),
  statusRaw: json['status_raw'] as String,
  notes: json['notes'] as String?,
  evidenceUrl: json['evidence_url'] as String?,
  createdAt: parseNullableDateTime(json['created_at']),
  updatedAt: parseNullableDateTime(json['updated_at']),
);

Map<String, dynamic> _$CertificateToJson(Certificate instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'title': instance.title,
      'status': _certificateStatusToJson(instance.status),
      'status_raw': instance.statusRaw,
      'notes': instance.notes,
      'evidence_url': instance.evidenceUrl,
      'created_at': dateTimeToIsoStringNullable(instance.createdAt),
      'updated_at': dateTimeToIsoStringNullable(instance.updatedAt),
    };
