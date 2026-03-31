import 'package:aveli/api/api_client.dart';
import 'package:aveli/data/models/community_post.dart';

class PostsRepository {
  PostsRepository({required ApiClient client});

  Future<T> _unsupportedRuntime<T>(String surface) {
    return Future<T>.error(
      UnsupportedError('$surface is inert in mounted runtime'),
    );
  }

  Future<List<CommunityPost>> feed({int limit = 50}) async {
    return _unsupportedRuntime('Community posts');
  }

  Future<CommunityPost> create({
    required String content,
    List<String>? mediaPaths,
  }) async {
    return _unsupportedRuntime('Community posts');
  }
}
