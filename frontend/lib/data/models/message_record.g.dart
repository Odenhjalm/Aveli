// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MessageRecord _$MessageRecordFromJson(Map<String, dynamic> json) =>
    MessageRecord(
      id: json['id'] as String,
      channel: json['channel'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String,
      createdAt: parseDateTime(json['created_at']),
    );

Map<String, dynamic> _$MessageRecordToJson(MessageRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'channel': instance.channel,
      'sender_id': instance.senderId,
      'content': instance.content,
      'created_at': dateTimeToIsoString(instance.createdAt),
    };
