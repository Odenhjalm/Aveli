import 'package:meta/meta.dart';

@immutable
class MembershipStatus {
  const MembershipStatus({
    required this.isActive,
    required this.status,
    this.nextBillingAt,
  });

  factory MembershipStatus.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const MembershipStatus(
        isActive: false,
        status: 'unknown',
        nextBillingAt: null,
      );
    }
    DateTime? nextBilling;
    final rawNext = json['next_billing'] ?? json['next_billing_at'];
    if (rawNext is String && rawNext.isNotEmpty) {
      nextBilling = DateTime.tryParse(rawNext);
    }
    return MembershipStatus(
      isActive: json['is_active'] == true,
      status: (json['status'] ?? 'unknown').toString(),
      nextBillingAt: nextBilling,
    );
  }

  final bool isActive;
  final String status;
  final DateTime? nextBillingAt;
}

@immutable
class Entitlements {
  const Entitlements({required this.membership, required this.courses});

  factory Entitlements.fromJson(Map<String, dynamic> json) {
    final membershipJson = json['membership'];
    final coursesJson = json['courses'];
    return Entitlements(
      membership: MembershipStatus.fromJson(
        membershipJson is Map<String, dynamic> ? membershipJson : null,
      ),
      courses: coursesJson is List
          ? coursesJson.map((e) => e.toString()).toList()
          : <String>[],
    );
  }

  final MembershipStatus membership;
  final List<String> courses;
}
