import 'package:wisdom/api/api_client.dart';
import 'package:wisdom/core/errors/app_failure.dart';
import 'package:wisdom/data/models/message_record.dart';

class MessagesRepository {
  MessagesRepository(this._client);

  final ApiClient _client;

  Future<List<MessageRecord>> listMessages(String channel) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/community/messages',
        queryParameters: {'channel': channel},
      );
      final items = (response['items'] as List? ?? [])
          .map(
            (item) =>
                MessageRecord.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false);
      return items;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<MessageRecord> sendMessage({
    required String channel,
    required String content,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/community/messages',
        body: {'channel': channel, 'content': content},
      );
      return MessageRecord.fromJson(response);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }
}
