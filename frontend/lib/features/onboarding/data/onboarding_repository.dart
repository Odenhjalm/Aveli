import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/api_paths.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/onboarding/domain/onboarding_status.dart';

class OnboardingRepository {
  OnboardingRepository(this._client);

  final ApiClient _client;

  Future<OnboardingStatus> getMe() async {
    final data = await _client.get<Map<String, dynamic>>(ApiPaths.onboardingMe);
    return OnboardingStatus.fromJson(data);
  }

  Future<List<CourseSummary>> listIntroCourses() async {
    final data = await _client.get<Map<String, dynamic>>(
      ApiPaths.onboardingIntroCourses,
    );
    final items = (data['items'] as List? ?? const [])
        .map(
          (item) =>
              CourseSummary.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
    return items;
  }

  Future<OnboardingStatus> selectIntroCourse(String courseId) async {
    final data = await _client.post<Map<String, dynamic>>(
      ApiPaths.onboardingSelectIntroCourse,
      body: {'course_id': courseId},
    );
    return OnboardingStatus.fromJson(data);
  }

  Future<OnboardingStatus> complete() async {
    final data = await _client.post<Map<String, dynamic>>(
      ApiPaths.onboardingComplete,
    );
    return OnboardingStatus.fromJson(data);
  }
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return OnboardingRepository(client);
});

final onboardingIntroCoursesProvider =
    FutureProvider.autoDispose<List<CourseSummary>>((ref) async {
      final repo = ref.watch(onboardingRepositoryProvider);
      return repo.listIntroCourses();
    });
