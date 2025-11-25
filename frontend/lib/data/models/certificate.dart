import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'certificate.g.dart';

enum CertificateStatus { pending, verified, rejected, unknown }

CertificateStatus _certificateStatusFromJson(String? value) {
  switch (value) {
    case 'pending':
      return CertificateStatus.pending;
    case 'verified':
      return CertificateStatus.verified;
    case 'rejected':
      return CertificateStatus.rejected;
    default:
      return CertificateStatus.unknown;
  }
}

String _certificateStatusToJson(CertificateStatus status) {
  switch (status) {
    case CertificateStatus.pending:
      return 'pending';
    case CertificateStatus.verified:
      return 'verified';
    case CertificateStatus.rejected:
      return 'rejected';
    case CertificateStatus.unknown:
      return 'unknown';
  }
}

@JsonSerializable(fieldRename: FieldRename.snake)
class Certificate {
  const Certificate({
    required this.id,
    required this.userId,
    required this.title,
    required this.status,
    required this.statusRaw,
    this.notes,
    this.evidenceUrl,
    this.createdAt,
    this.updatedAt,
  });

  factory Certificate.fromJson(Map<String, dynamic> json) =>
      _$CertificateFromJson(json);

  Map<String, dynamic> toJson() => _$CertificateToJson(this);

  static const String teacherApplicationTitle = 'Läraransökan';

  final String id;

  @JsonKey(name: 'user_id')
  final String userId;

  final String title;

  @JsonKey(
    fromJson: _certificateStatusFromJson,
    toJson: _certificateStatusToJson,
  )
  final CertificateStatus status;

  final String statusRaw;
  final String? notes;
  final String? evidenceUrl;

  @JsonKey(fromJson: parseNullableDateTime, toJson: dateTimeToIsoStringNullable)
  final DateTime? createdAt;

  @JsonKey(fromJson: parseNullableDateTime, toJson: dateTimeToIsoStringNullable)
  final DateTime? updatedAt;

  bool get isPending => status == CertificateStatus.pending;
  bool get isVerified => status == CertificateStatus.verified;
  bool get isRejected => status == CertificateStatus.rejected;

  Certificate copyWith({
    String? id,
    String? userId,
    String? title,
    CertificateStatus? status,
    String? statusRaw,
    String? notes,
    String? evidenceUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Certificate(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      status: status ?? this.status,
      statusRaw: statusRaw ?? this.statusRaw,
      notes: notes ?? this.notes,
      evidenceUrl: evidenceUrl ?? this.evidenceUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'title': title,
    'status': statusRaw,
    if (notes != null) 'notes': notes,
    if (evidenceUrl != null) 'evidence_url': evidenceUrl,
  };
}
