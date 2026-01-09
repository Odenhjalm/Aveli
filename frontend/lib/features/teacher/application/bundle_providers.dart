import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aveli/api/auth_repository.dart';

import '../data/course_bundles_repository.dart';

final courseBundlesRepositoryProvider = Provider<CourseBundlesRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return CourseBundlesRepository(client);
});

final teacherBundlesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(courseBundlesRepositoryProvider);
  return repo.myBundles();
});
