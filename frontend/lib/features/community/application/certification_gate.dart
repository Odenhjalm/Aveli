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
      message: 'Logga in for att visa tjansten.',
    );
  }

  return const CertificationGateResult(
    allowed: false,
    pending: false,
    requiresAuth: false,
    message: 'Certifieringsbaserade bokningar ar pausade i Baseline V2.',
  );
}
