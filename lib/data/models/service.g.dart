// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Service _$ServiceFromJson(Map<String, dynamic> json) => Service(
  id: json['id'] as String,
  title: json['title'] as String,
  description: json['description'] as String,
  priceCents: (json['price_cents'] as num?)?.toInt() ?? 0,
  currency: json['currency'] as String,
  status: json['status'] as String,
  durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
  requiresCertification: json['requires_certification'] as bool? ?? false,
  certifiedArea: json['certified_area'] as String?,
  thumbnailUrl: json['thumbnail_url'] as String?,
);

Map<String, dynamic> _$ServiceToJson(Service instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'description': instance.description,
  'price_cents': instance.priceCents,
  'currency': instance.currency,
  'status': instance.status,
  'duration_minutes': instance.durationMinutes,
  'requires_certification': instance.requiresCertification,
  'certified_area': instance.certifiedArea,
  'thumbnail_url': instance.thumbnailUrl,
};
