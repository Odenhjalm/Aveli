import 'package:wisdom/core/auth/auth_claims.dart';
import 'package:wisdom/data/models/certificate.dart';
import 'package:wisdom/data/models/profile.dart';

class TeacherApprovalInfo {
  const TeacherApprovalInfo({this.approvedBy, this.approvedAt});

  final String? approvedBy;
  final DateTime? approvedAt;

  bool get isApproved => approvedAt != null;

  factory TeacherApprovalInfo.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? input) {
      if (input is DateTime) return input;
      if (input is String) return DateTime.tryParse(input);
      return null;
    }

    return TeacherApprovalInfo(
      approvedBy: json['approved_by'] as String?,
      approvedAt: parseDate(json['approved_at']),
    );
  }

  static const TeacherApprovalInfo empty = TeacherApprovalInfo();
}

class TeacherApplication {
  const TeacherApplication({required this.certificate});

  final Certificate certificate;

  CertificateStatus get status => certificate.status;
  String get statusRaw => certificate.statusRaw;

  bool get isPending => certificate.isPending;
  bool get isRejected => certificate.isRejected;
  bool get isApproved => certificate.isVerified;
}

class UserAccessState {
  const UserAccessState({
    required this.profile,
    required this.effectiveProfile,
    required this.approval,
    required this.application,
    required this.claims,
  });

  final Profile? profile;
  final Profile? effectiveProfile;
  final TeacherApprovalInfo approval;
  final TeacherApplication? application;
  final AuthClaims? claims;

  bool get isAuthenticated => effectiveProfile != null || claims != null;
  bool get isAdmin => effectiveProfile?.isAdmin ?? claims?.isAdmin ?? false;
  UserRole get role =>
      effectiveProfile?.userRole ?? claims?.userRole ?? UserRole.user;
  bool get isTeacher =>
      effectiveProfile?.isTeacher ?? claims?.isTeacher ?? false;
  bool get isProfessional => isTeacher || role == UserRole.professional;

  CertificateStatus get applicationStatus =>
      application?.status ?? CertificateStatus.unknown;
  Certificate? get teacherApplicationCertificate => application?.certificate;

  UserAccessState copyWith({
    Profile? profile,
    Profile? effectiveProfile,
    TeacherApprovalInfo? approval,
    TeacherApplication? application,
    AuthClaims? claims,
    bool clearClaims = false,
  }) {
    return UserAccessState(
      profile: profile ?? this.profile,
      effectiveProfile: effectiveProfile ?? this.effectiveProfile,
      approval: approval ?? this.approval,
      application: application ?? this.application,
      claims: clearClaims ? null : (claims ?? this.claims),
    );
  }

  static const UserAccessState unauthenticated = UserAccessState(
    profile: null,
    effectiveProfile: null,
    approval: TeacherApprovalInfo.empty,
    application: null,
    claims: null,
  );
}
