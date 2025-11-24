import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ProgressRepository {
  static const _storage = FlutterSecureStorage();

  String _key(String courseId) => 'course_progress:$courseId';

  Future<void> setProgress(String courseId, double value) async {
    final v = value.clamp(0.0, 1.0).toString();
    await _storage.write(key: _key(courseId), value: v);
  }

  Future<double> getProgress(String courseId) async {
    final v = await _storage.read(key: _key(courseId));
    if (v == null) return 0.0;
    return double.tryParse(v) ?? 0.0;
  }

  Future<Map<String, double>> getProgressForCourses(
    List<String> courseIds,
  ) async {
    final out = <String, double>{};
    for (final id in courseIds) {
      out[id] = await getProgress(id);
    }
    return out;
  }
}
