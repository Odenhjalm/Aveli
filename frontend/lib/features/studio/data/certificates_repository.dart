import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/data/models/certificate.dart';

class CertificatesRepository {
  CertificatesRepository(ApiClient _);

  Future<T> _unsupportedRuntime<T>(String surface) {
    return Future<T>.error(
      UnsupportedError('$surface is inert in mounted runtime'),
    );
  }

  Future<List<Certificate>> myCertificates({bool verifiedOnly = false}) async {
    return const <Certificate>[];
  }

  Future<List<Certificate>> certificatesOf(
    String userId, {
    bool verifiedOnly = true,
  }) async {
    return const <Certificate>[];
  }

  Future<Certificate?> teacherApplicationOf(String userId) async {
    return null;
  }

  Future<Certificate?> myTeacherApplication() async {
    return null;
  }

  Future<Certificate?> addCertificate({
    required String title,
    String status = 'pending',
    String? notes,
    String? evidenceUrl,
  }) async {
    return _unsupportedRuntime('Studio certificates');
  }
}

final certificatesRepositoryProvider = Provider<CertificatesRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return CertificatesRepository(client);
});
