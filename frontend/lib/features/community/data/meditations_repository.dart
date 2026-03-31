import 'package:aveli/api/api_client.dart';
class MeditationsRepository {
  MeditationsRepository(ApiClient _);

  Future<T> _unsupportedRuntime<T>(String surface) {
    return Future<T>.error(
      UnsupportedError('$surface is inert in mounted runtime'),
    );
  }

  Future<List<Map<String, dynamic>>> publicMeditations({int limit = 50}) async {
    return _unsupportedRuntime('Community meditations');
  }

  Future<List<Map<String, dynamic>>> byTeacher(String userId) async {
    return _unsupportedRuntime('Community meditations');
  }
}
