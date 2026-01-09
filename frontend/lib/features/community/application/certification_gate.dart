import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/data/models/certificate.dart';
import 'package:aveli/data/models/service.dart';

class CertificationGateResult {
  const CertificationGateResult({
    required this.allowed,
    required this.pending,
    required this.requiresAuth,
    this.message,
  });

  final bool allowed;
  final bool pending;
  final bool requiresAuth;
  final String? message;
}

CertificationGateResult evaluateCertificationGate({
  required Service service,
  required AsyncValue<List<Certificate>> viewerCertificates,
  required bool isAuthenticated,
}) {
  if (!service.requiresCertification) {
    return const CertificationGateResult(
      allowed: true,
      pending: false,
      requiresAuth: false,
    );
  }

  if (!isAuthenticated) {
    return const CertificationGateResult(
      allowed: false,
      pending: false,
      requiresAuth: true,
      message:
          'Logga in för att boka eller för att kontrollera dina certifieringar.',
    );
  }

  return viewerCertificates.when(
    data: (certs) {
      final requiredArea = service.certifiedArea?.trim();
      final normalizedArea = requiredArea?.toLowerCase();
      final hasVerified = certs.any((cert) {
        if (!cert.isVerified) return false;
        if (normalizedArea == null || normalizedArea.isEmpty) {
          return true;
        }
        return cert.title.trim().toLowerCase() == normalizedArea;
      });

      if (hasVerified) {
        return const CertificationGateResult(
          allowed: true,
          pending: false,
          requiresAuth: false,
        );
      }

      final message = (requiredArea?.isNotEmpty ?? false)
          ? 'Du behöver certifieringen "$requiredArea" för att boka den här tjänsten.'
          : 'Du behöver en verifierad certifiering för att boka den här tjänsten.';
      return CertificationGateResult(
        allowed: false,
        pending: false,
        requiresAuth: false,
        message: message,
      );
    },
    loading: () => const CertificationGateResult(
      allowed: false,
      pending: true,
      requiresAuth: false,
    ),
    error: (error, stackTrace) => const CertificationGateResult(
      allowed: false,
      pending: false,
      requiresAuth: false,
      message:
          'Certifieringsstatus kunde inte hämtas just nu. Försök igen senare.',
    ),
  );
}
