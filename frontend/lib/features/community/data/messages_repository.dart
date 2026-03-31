import 'package:aveli/api/api_client.dart';
import 'package:aveli/data/models/message_record.dart';

class MessagesRepository {
  MessagesRepository(ApiClient _);

  Future<T> _unsupportedRuntime<T>(String surface) {
    return Future<T>.error(
      UnsupportedError('$surface is inert in mounted runtime'),
    );
  }

  Future<List<MessageRecord>> listMessages(String channel) async {
    return _unsupportedRuntime('Community messages');
  }

  Future<MessageRecord> sendMessage({
    required String channel,
    required String content,
  }) async {
    return _unsupportedRuntime('Community messages');
  }
}
