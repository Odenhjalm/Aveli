import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'activity.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class Activity extends Equatable {
  const Activity({
    required this.id,
    required this.type,
    required this.summary,
    required this.occurredAt,
    this.actorId,
    this.subjectTable,
    this.subjectId,
    this.metadata = const {},
  });

  factory Activity.fromJson(Map<String, dynamic> json) =>
      _$ActivityFromJson(json);

  Map<String, dynamic> toJson() => _$ActivityToJson(this);

  final String id;

  @JsonKey(name: 'activity_type')
  final String type;

  final String summary;

  @JsonKey(fromJson: parseDateTime, toJson: dateTimeToIsoString)
  final DateTime occurredAt;

  @JsonKey(name: 'actor_id')
  final String? actorId;

  @JsonKey(name: 'subject_table')
  final String? subjectTable;

  @JsonKey(name: 'subject_id')
  final String? subjectId;

  @JsonKey(defaultValue: <String, dynamic>{}, fromJson: mapFromJson)
  final Map<String, dynamic> metadata;

  @override
  List<Object?> get props => [
    id,
    type,
    summary,
    occurredAt,
    actorId,
    subjectTable,
    subjectId,
    metadata,
  ];
}
