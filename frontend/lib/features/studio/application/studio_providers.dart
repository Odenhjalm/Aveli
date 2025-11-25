import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/api/auth_repository.dart';
import 'package:wisdom/core/auth/auth_controller.dart';

import '../data/certificates_repository.dart';
import '../data/studio_repository.dart';
import 'studio_upload_queue.dart';

final studioRepositoryProvider = Provider<StudioRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return StudioRepository(client: client);
});

final certificatesRepositoryProvider = Provider<CertificatesRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return CertificatesRepository(client);
});

final myCoursesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final repo = ref.watch(studioRepositoryProvider);
  return repo.myCourses();
});

final studioStatusProvider = FutureProvider<StudioStatus>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.profile == null) {
    return const StudioStatus(
      isTeacher: false,
      verifiedCertificates: 0,
      hasApplication: false,
    );
  }
  final repo = ref.watch(studioRepositoryProvider);
  return repo.fetchStatus();
});

final studioUploadQueueProvider =
    StateNotifierProvider<UploadQueueNotifier, List<UploadJob>>((ref) {
      final repo = ref.watch(studioRepositoryProvider);
      final notifier = UploadQueueNotifier(repo);
      ref.onDispose(notifier.dispose);
      return notifier;
    });
