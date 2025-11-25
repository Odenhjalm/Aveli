import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'message_record.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class MessageRecord extends Equatable {
  const MessageRecord({
    required this.id,
    required this.channel,
    required this.senderId,
    required this.content,
    required this.createdAt,
  });

  factory MessageRecord.fromJson(Map<String, dynamic> json) =>
      _$MessageRecordFromJson(json);

  Map<String, dynamic> toJson() => _$MessageRecordToJson(this);

  final String id;
  final String channel;
  final String senderId;
  final String content;

  @JsonKey(fromJson: parseDateTime, toJson: dateTimeToIsoString)
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, channel, senderId, content, createdAt];
}
