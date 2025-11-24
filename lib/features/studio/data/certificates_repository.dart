import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisdom/api/api_client.dart';
import 'package:wisdom/api/auth_repository.dart';
import 'package:wisdom/data/models/certificate.dart';

class CertificatesRepository {
  CertificatesRepository(this._client);

  final ApiClient _client;

  static const String _applicationTitle = 'Läraransökan';

  Future<List<Certificate>> myCertificates({bool verifiedOnly = false}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/studio/certificates',
      queryParameters: {'verified_only': verifiedOnly},
    );
    final list = res['items'] as List? ?? const [];
    return list
        .map((e) => Certificate.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  }

  Future<List<Certificate>> certificatesOf(
    String userId, {
    bool verifiedOnly = true,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/profiles/$userId/certificates',
      queryParameters: {'verified_only': verifiedOnly},
    );
    final list = res['items'] as List? ?? const [];
    return list
        .map((e) => Certificate.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
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
    final res = await _client.get<Map<String, dynamic>>(
      '/studio/certificates',
      queryParameters: {'verified_only': false},
    );
    final list = res['items'] as List? ?? const [];
    for (final item in list) {
      final cert = Certificate.fromJson(Map<String, dynamic>.from(item as Map));
      if (cert.title.toLowerCase() == _applicationTitle.toLowerCase()) {
        return cert;
      }
    }
    return null;
  }

  Future<Certificate?> addCertificate({
    required String title,
    String status = 'pending',
    String? notes,
    String? evidenceUrl,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/studio/certificates',
      body: {
        'title': title,
        'status': status,
        if (notes != null) 'notes': notes,
        if (evidenceUrl != null) 'evidence_url': evidenceUrl,
      },
    );
    return Certificate.fromJson(res);
  }
}

final certificatesRepositoryProvider = Provider<CertificatesRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return CertificatesRepository(client);
});
