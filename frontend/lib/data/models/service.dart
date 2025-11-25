import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'service.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class Service extends Equatable {
  const Service({
    required this.id,
    required this.title,
    required this.description,
    required this.priceCents,
    required this.currency,
    required this.status,
    this.durationMinutes,
    this.requiresCertification = false,
    this.certifiedArea,
    this.thumbnailUrl,
  });

  factory Service.fromJson(Map<String, dynamic> json) =>
      _$ServiceFromJson(json);

  Map<String, dynamic> toJson() => _$ServiceToJson(this);

  final String id;
  final String title;
  final String description;

  @JsonKey(defaultValue: 0)
  final int priceCents;

  final String currency;
  final String status;
  final int? durationMinutes;

  @JsonKey(defaultValue: false)
  final bool requiresCertification;

  final String? certifiedArea;
  final String? thumbnailUrl;

  double get price => priceCents / 100;

  @override
  List<Object?> get props => [
    id,
    title,
    description,
    priceCents,
    currency,
    status,
    durationMinutes,
    requiresCertification,
    certifiedArea,
    thumbnailUrl,
  ];
}
