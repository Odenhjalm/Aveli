// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Order _$OrderFromJson(Map<String, dynamic> json) => Order(
  id: json['id'] as String,
  userId: json['user_id'] as String,
  serviceId: json['service_id'] as String?,
  courseId: json['course_id'] as String?,
  amountCents: (json['amount_cents'] as num?)?.toInt() ?? 0,
  currency: json['currency'] as String,
  status: json['status'] as String,
  stripeCheckoutId: json['stripe_checkout_id'] as String?,
  stripePaymentIntent: json['stripe_payment_intent'] as String?,
  metadata: json['metadata'] == null ? {} : mapFromJson(json['metadata']),
  createdAt: parseNullableDateTime(json['created_at']),
  updatedAt: parseNullableDateTime(json['updated_at']),
);

Map<String, dynamic> _$OrderToJson(Order instance) => <String, dynamic>{
  'id': instance.id,
  'user_id': instance.userId,
  'service_id': instance.serviceId,
  'course_id': instance.courseId,
  'amount_cents': instance.amountCents,
  'currency': instance.currency,
  'status': instance.status,
  'stripe_checkout_id': instance.stripeCheckoutId,
  'stripe_payment_intent': instance.stripePaymentIntent,
  'metadata': instance.metadata,
  'created_at': dateTimeToIsoStringNullable(instance.createdAt),
  'updated_at': dateTimeToIsoStringNullable(instance.updatedAt),
};
