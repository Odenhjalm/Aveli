import 'package:url_launcher/url_launcher.dart';

import 'package:aveli/api/api_client.dart';
import 'package:aveli/core/errors/app_failure.dart';

class ConnectStatus {
  const ConnectStatus({
    required this.accountId,
    required this.status,
    required this.chargesEnabled,
    required this.payoutsEnabled,
    required this.requirements,
    required this.onboardedAt,
  });

  final String? accountId;
  final String status;
  final bool chargesEnabled;
  final bool payoutsEnabled;
  final Map<String, dynamic> requirements;
  final DateTime? onboardedAt;

  bool get isVerified => chargesEnabled && payoutsEnabled;
  bool get needsAttention =>
      status == 'restricted' || requirements['disabled_reason'] != null;

  factory ConnectStatus.fromJson(Map<String, dynamic> json) {
    final onboardedAt = json['onboarded_at'];
    return ConnectStatus(
      accountId: json['account_id'] as String?,
      status: json['status'] as String? ?? 'pending',
      chargesEnabled: json['charges_enabled'] == true,
      payoutsEnabled: json['payouts_enabled'] == true,
      requirements: Map<String, dynamic>.from(
        json['requirements_due'] as Map? ?? const {},
      ),
      onboardedAt: onboardedAt is String
          ? DateTime.tryParse(onboardedAt)?.toLocal()
          : null,
    );
  }
}

class ConnectRepository {
  ConnectRepository(this._client);

  final ApiClient _client;

  Future<ConnectStatus> fetchStatus() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/connect/status',
      );
      return ConnectStatus.fromJson(response);
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<String> createOnboardingLink() async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/connect/onboarding',
      );
      final url = response['onboarding_url'] as String?;
      if (url == null) {
        throw UnexpectedFailure(message: 'Stripe svarade utan onboarding-url.');
      }
      return url;
    } catch (error, stackTrace) {
      throw AppFailure.from(error, stackTrace);
    }
  }

  Future<void> openOnboarding() async {
    final url = await createOnboardingLink();
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw UnexpectedFailure(
        message: 'Kunde inte öppna webbläsaren för Stripe Connect.',
      );
    }
  }
}
