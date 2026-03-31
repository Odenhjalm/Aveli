import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/data/models/certificate.dart';

class CertificatesRepository {
  CertificatesRepository(ApiClient _);

  static const String _applicationTitle = 'Läraransökan';

  Future<T> _unsupportedRuntime<T>(String surface) {
    return Future<T>.error(
      UnsupportedError('$surface is inert in mounted runtime'),
    );
  }

  Future<List<Certificate>> myCertificates({bool verifiedOnly = false}) async {
    return _unsupportedRuntime('Studio certificates');
  }

  Future<List<Certificate>> certificatesOf(
    String userId, {
    bool verifiedOnly = true,
  }) async {
    return _unsupportedRuntime('Profile certificates');
  }

  Future<Certificate?> teacherApplicationOf(String userId) async {
    final certs = await certificatesOf(userId, verifiedOnly: false);
    for (final cert in certs) {
      if (cert.title.toLowerCase() == _applicationTitle.toLowerCase()) {
        return cert;
      }
    }
    return null;
  }

  Future<Certificate?> myTeacherApplication() async {
    return _unsupportedRuntime('Studio certificates');
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
