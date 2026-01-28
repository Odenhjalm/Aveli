import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/auth/application/user_access_provider.dart';
import 'package:aveli/features/payments/application/payments_providers.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class ClaimPurchasePage extends ConsumerStatefulWidget {
  const ClaimPurchasePage({super.key, required this.token});

  final String? token;

  @override
  ConsumerState<ClaimPurchasePage> createState() => _ClaimPurchasePageState();
}

enum _ClaimStatus { loading, missingToken, requireLogin, success, failed }

class _ClaimPurchasePageState extends ConsumerState<ClaimPurchasePage> {
  _ClaimStatus _status = _ClaimStatus.loading;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attemptClaim());
  }

  Future<void> _attemptClaim() async {
    final token = widget.token;
    setState(() {
      _status = _ClaimStatus.loading;
      _error = null;
    });

    if (token == null || token.isEmpty) {
      setState(() => _status = _ClaimStatus.missingToken);
      return;
    }

    final authState = ref.read(authControllerProvider);
    if (authState.profile == null) {
      setState(() => _status = _ClaimStatus.requireLogin);
      return;
    }

    try {
      final repo = ref.read(paymentsRepositoryProvider);
      final success = await repo.claimPurchase(token);
      if (!mounted) return;
      if (success) {
        ref.invalidate(userAccessProvider);
        setState(() => _status = _ClaimStatus.success);
      } else {
        setState(() => _status = _ClaimStatus.failed);
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to claim purchase: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _status = _ClaimStatus.failed;
        _error = _mapError(error, stackTrace);
      });
    }
  }

  void _goHome() {
    if (!mounted) return;
    context.goNamed(AppRoute.landingRoot);
  }

  void _goToLogin() {
    if (!mounted) return;
    final token = widget.token;
    if (token != null && token.isNotEmpty) {
      final router = GoRouter.of(context);
      final redirect = router.namedLocation(
        AppRoute.claim,
        queryParameters: {'token': token},
      );
      context.goNamed(AppRoute.login, queryParameters: {'redirect': redirect});
    } else {
      context.goNamed(AppRoute.login);
    }
  }

  Widget _buildContent() {
    switch (_status) {
      case _ClaimStatus.loading:
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        );
      case _ClaimStatus.missingToken:
        return _MessageCard(
          title: 'Ogiltig länk',
          description:
              'Vi kunde inte läsa något token från länken. Kontrollera att du klickade på hela URL:en i mejlet.',
          primaryLabel: 'Till startsidan',
          onPrimary: _goHome,
        );
      case _ClaimStatus.requireLogin:
        return _MessageCard(
          title: 'Logga in för att fortsätta',
          description:
              'Logga in med det konto som ska kopplas till köpet. Därefter kan du öppna länken igen.',
          primaryLabel: 'Logga in',
          onPrimary: _goToLogin,
          secondaryLabel: 'Försök igen',
          onSecondary: _attemptClaim,
        );
      case _ClaimStatus.success:
        return _MessageCard(
          title: 'Klart! Köpet är kopplat',
          description:
              'Din kursåtkomst är uppdaterad. Du hittar nu innehållet i kurslistan.',
          primaryLabel: 'Till Mina kurser',
          onPrimary: _goHome,
        );
      case _ClaimStatus.failed:
        final technicalInfo = _error != null ? '\n\nTeknisk info: $_error' : '';
        return _MessageCard(
          title: 'Kunde inte koppla köpet',
          description:
              'Länken kan redan vara använd eller ha gått ut. Kontakta supporten om du behöver hjälp.$technicalInfo',
          primaryLabel: 'Försök igen',
          onPrimary: _attemptClaim,
          secondaryLabel: 'Till startsidan',
          onSecondary: _goHome,
        );
    }
  }

  String _mapError(Object error, StackTrace? stackTrace) {
    final failure = AppFailure.from(error, stackTrace);
    return failure.message;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Hämta kursköp',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String description;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(description, style: textTheme.bodyMedium),
            const SizedBox(height: 24),
            GradientButton(onPressed: onPrimary, child: Text(primaryLabel)),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
