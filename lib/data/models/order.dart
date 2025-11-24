import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'order.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class Order extends Equatable {
  const Order({
    required this.id,
    required this.userId,
    this.serviceId,
    this.courseId,
    required this.amountCents,
    required this.currency,
    required this.status,
    this.stripeCheckoutId,
    this.stripePaymentIntent,
    this.metadata = const {},
    this.createdAt,
    this.updatedAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);

  Map<String, dynamic> toJson() => _$OrderToJson(this);

  final String id;
  final String userId;
  final String? serviceId;
  final String? courseId;

  @JsonKey(defaultValue: 0)
  final int amountCents;

  final String currency;
  final String status;
  final String? stripeCheckoutId;
  final String? stripePaymentIntent;

  @JsonKey(defaultValue: <String, dynamic>{}, fromJson: mapFromJson)
  final Map<String, dynamic> metadata;

  @JsonKey(fromJson: parseNullableDateTime, toJson: dateTimeToIsoStringNullable)
  final DateTime? createdAt;

  @JsonKey(fromJson: parseNullableDateTime, toJson: dateTimeToIsoStringNullable)
  final DateTime? updatedAt;

  double get amount => amountCents / 100;

  @override
  List<Object?> get props => [
    id,
    userId,
    serviceId,
    courseId,
    amountCents,
    currency,
    status,
    stripeCheckoutId,
    stripePaymentIntent,
    metadata,
    createdAt,
    updatedAt,
  ];
}
