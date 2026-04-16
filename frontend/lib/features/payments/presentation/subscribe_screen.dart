import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/deeplinks/deep_link_service.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/payments/presentation/embedded_membership_checkout_surface.dart';
import 'package:aveli/features/paywall/application/checkout_flow.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/utils/app_images.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/effects_backdrop_filter.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class MembershipCheckoutScreen extends ConsumerStatefulWidget {
  const MembershipCheckoutScreen({super.key});

  @override
  ConsumerState<MembershipCheckoutScreen> createState() =>
      _MembershipCheckoutScreenState();
}

class _MembershipCheckoutScreenState
    extends ConsumerState<MembershipCheckoutScreen> {
  String? _submittingInterval;
  String? _checkoutInterval;
  MembershipCheckoutLaunch? _checkoutLaunch;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final envInfo = ref.watch(envInfoProvider);
    final authState = ref.watch(authControllerProvider);
    final entryState = authState.entryState;
    final envBlocked = envInfo.hasIssues;
    final stripeKeyMissing = config.stripePublishableKey.trim().isEmpty;
    final checkoutBlocked =
        envBlocked ||
        stripeKeyMissing ||
        !supportsEmbeddedMembershipCheckout ||
        !config.subscriptionsEnabled;

    return AppScaffold(
      title: 'Medlemskap',
      showHomeAction: false,
      useBasePage: false,
      contentPadding: EdgeInsets.zero,
      maxContentWidth: 1180,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEAF8FB), Color(0xFFF7F1FF)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _CheckoutLogo(),
                    gap20,
                    _ResponsiveCheckoutLayout(
                      promise: const _MembershipPromise(),
                      action: _CheckoutActionPanel(
                        envMessage: envInfo.hasIssues ? envInfo.message : null,
                        subscriptionsEnabled: config.subscriptionsEnabled,
                        stripeKeyMissing: stripeKeyMissing,
                        platformSupported: supportsEmbeddedMembershipCheckout,
                        entryStateAvailable: entryState != null,
                        needsPayment: entryState?.needsPayment == true,
                        checkoutBlocked: checkoutBlocked,
                        checkoutLaunch: _checkoutLaunch,
                        checkoutInterval: _checkoutInterval,
                        submittingInterval: _submittingInterval,
                        stripePublishableKey: config.stripePublishableKey,
                        onRequestLogin: _redirectToLogin,
                        onStartCheckout: _startMembershipCheckout,
                        onCheckoutRedirect: _handleCheckoutRedirect,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _startMembershipCheckout(String interval) async {
    if (_submittingInterval != null) return;
    final config = ref.read(appConfigProvider);
    if (!supportsEmbeddedMembershipCheckout) {
      _showMessage(
        'Inbyggd betalning är inte tillgänglig på den här plattformen.',
      );
      return;
    }
    if (config.stripePublishableKey.trim().isEmpty) {
      _showMessage('Stripe-konfiguration saknas. Betalningen kan inte starta.');
      return;
    }

    final returnPath = GoRouterState.of(context).uri.toString();
    setState(() => _submittingInterval = interval);
    try {
      final api = ref.read(checkoutApiProvider);
      final launch = await api.createMembershipCheckout(interval: interval);
      ref.read(checkoutContextProvider.notifier).state = CheckoutContext(
        type: CheckoutItemType.membership,
        returnPath: returnPath,
      );
      ref
          .read(checkoutRedirectStateProvider.notifier)
          .state = CheckoutRedirectState(
        status: CheckoutRedirectStatus.processing,
        sessionId: launch.sessionId,
        orderId: launch.orderId,
      );
      if (!mounted) return;
      setState(() {
        _checkoutLaunch = launch;
        _checkoutInterval = interval;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      final failure = AppFailure.from(error, stackTrace);
      _showMessage(failure.message);
    } finally {
      if (mounted) {
        setState(() => _submittingInterval = null);
      }
    }
  }

  void _handleCheckoutRedirect(Uri uri) {
    unawaited(_handleCheckoutRedirectAsync(uri));
  }

  Future<void> _handleCheckoutRedirectAsync(Uri uri) async {
    final handled = await ref.read(deepLinkServiceProvider).handleUri(uri);
    if (handled || !mounted) return;

    await ref.read(authControllerProvider.notifier).loadSession();
    if (!mounted || !context.mounted) return;
    context.go(_checkoutResultPath(uri));
  }

  String _checkoutResultPath(Uri uri) {
    final success = _isSuccessUri(uri);
    if (!success) return RoutePath.checkoutCancel;
    final query = <String, String>{...uri.queryParameters};
    final redirectState = ref.read(checkoutRedirectStateProvider);
    if (!query.containsKey('session_id') &&
        redirectState.sessionId?.isNotEmpty == true) {
      query['session_id'] = redirectState.sessionId!;
    }
    if (!query.containsKey('order_id') &&
        redirectState.orderId?.isNotEmpty == true) {
      query['order_id'] = redirectState.orderId!;
    }
    if (query.isEmpty) return RoutePath.checkoutSuccess;
    return Uri(
      path: RoutePath.checkoutSuccess,
      queryParameters: query,
    ).toString();
  }

  bool _isSuccessUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    return host == 'success' ||
        host == 'checkout_success' ||
        path.contains('checkout/return') ||
        path.endsWith('/success') ||
        (host == 'checkout' && path.contains('return'));
  }

  void _redirectToLogin() {
    if (!mounted) return;
    final redirect = GoRouter.of(
      context,
    ).namedLocation(AppRoute.checkoutMembership);
    context.goNamed(AppRoute.login, queryParameters: {'redirect': redirect});
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ResponsiveCheckoutLayout extends StatelessWidget {
  const _ResponsiveCheckoutLayout({
    required this.promise,
    required this.action,
  });

  final Widget promise;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [promise, gap16, action],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: promise),
            const SizedBox(width: 18),
            Expanded(flex: 4, child: action),
          ],
        );
      },
    );
  }
}

class _CheckoutLogo extends StatelessWidget {
  const _CheckoutLogo();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Aveli',
      child: Align(
        alignment: Alignment.centerLeft,
        child: Image(
          image: AppImages.logo,
          height: 58,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Text(
              'Aveli',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            );
          },
        ),
      ),
    );
  }
}

class _MembershipPromise extends StatelessWidget {
  const _MembershipPromise();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Starta ditt medlemskap i Aveli',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          gap16,
          Text(
            'Du får 14 dagar att testa appen. Kortuppgifter krävs, men du debiteras inte under provperioden.',
            style: theme.textTheme.titleMedium?.copyWith(height: 1.45),
          ),
          gap20,
          Text(
            'I medlemskapet ingår:',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          gap12,
          const _BenefitLine('Livelektioner'),
          const _BenefitLine(
            'Tillgång till ett stort kursutbud och en plattform för likasinnade spirituellt intresserade människor i olika skeden av sin utveckling',
          ),
          const _BenefitLine('Meditationsmusik och guidade meditationer'),
          const _BenefitLine(
            'En trygg plats för lärande och spirituell utveckling',
          ),
          gap20,
          const _TrustLine(),
        ],
      ),
    );
  }
}

class _CheckoutActionPanel extends StatelessWidget {
  const _CheckoutActionPanel({
    required this.envMessage,
    required this.subscriptionsEnabled,
    required this.stripeKeyMissing,
    required this.platformSupported,
    required this.entryStateAvailable,
    required this.needsPayment,
    required this.checkoutBlocked,
    required this.checkoutLaunch,
    required this.checkoutInterval,
    required this.submittingInterval,
    required this.stripePublishableKey,
    required this.onRequestLogin,
    required this.onStartCheckout,
    required this.onCheckoutRedirect,
  });

  final String? envMessage;
  final bool subscriptionsEnabled;
  final bool stripeKeyMissing;
  final bool platformSupported;
  final bool entryStateAvailable;
  final bool needsPayment;
  final bool checkoutBlocked;
  final MembershipCheckoutLaunch? checkoutLaunch;
  final String? checkoutInterval;
  final String? submittingInterval;
  final String stripePublishableKey;
  final VoidCallback onRequestLogin;
  final ValueChanged<String> onStartCheckout;
  final ValueChanged<Uri> onCheckoutRedirect;

  @override
  Widget build(BuildContext context) {
    final launch = checkoutLaunch;
    return _Panel(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: launch == null
            ? _CheckoutStartState(
                key: const ValueKey('membership-checkout-start'),
                envMessage: envMessage,
                subscriptionsEnabled: subscriptionsEnabled,
                stripeKeyMissing: stripeKeyMissing,
                platformSupported: platformSupported,
                entryStateAvailable: entryStateAvailable,
                needsPayment: needsPayment,
                checkoutBlocked: checkoutBlocked,
                submittingInterval: submittingInterval,
                onRequestLogin: onRequestLogin,
                onStartCheckout: onStartCheckout,
              )
            : _EmbeddedCheckoutState(
                key: ValueKey(launch.sessionId),
                launch: launch,
                interval: checkoutInterval,
                stripePublishableKey: stripePublishableKey,
                onCheckoutRedirect: onCheckoutRedirect,
              ),
      ),
    );
  }
}

class _CheckoutStartState extends StatelessWidget {
  const _CheckoutStartState({
    super.key,
    required this.envMessage,
    required this.subscriptionsEnabled,
    required this.stripeKeyMissing,
    required this.platformSupported,
    required this.entryStateAvailable,
    required this.needsPayment,
    required this.checkoutBlocked,
    required this.submittingInterval,
    required this.onRequestLogin,
    required this.onStartCheckout,
  });

  final String? envMessage;
  final bool subscriptionsEnabled;
  final bool stripeKeyMissing;
  final bool platformSupported;
  final bool entryStateAvailable;
  final bool needsPayment;
  final bool checkoutBlocked;
  final String? submittingInterval;
  final VoidCallback onRequestLogin;
  final ValueChanged<String> onStartCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusMessage = _statusMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Välj medlemskap',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        gap8,
        Text(
          'Betalningen öppnas här i Aveli. Servern uppdaterar åtkomst först när Stripe har bekräftat betalningen.',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
        if (statusMessage != null) ...[
          gap16,
          _StatusNotice(message: statusMessage),
        ],
        gap20,
        if (!entryStateAvailable)
          _LoginPrompt(onRequestLogin: onRequestLogin)
        else if (!needsPayment)
          const _StatusNotice(
            message:
                'Ditt konto behöver inte starta en medlemsbetalning just nu.',
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _IntervalButton(
                label: 'Månadsmedlemskap',
                busy: submittingInterval == 'month',
                enabled: !checkoutBlocked && submittingInterval == null,
                onPressed: () => onStartCheckout('month'),
              ),
              gap12,
              _IntervalButton(
                label: 'Årsmedlemskap',
                busy: submittingInterval == 'year',
                enabled: !checkoutBlocked && submittingInterval == null,
                onPressed: () => onStartCheckout('year'),
              ),
            ],
          ),
      ],
    );
  }

  String? get _statusMessage {
    if (!subscriptionsEnabled) {
      return 'Medlemskap är inte aktiverat ännu.';
    }
    if (envMessage != null) {
      return '$envMessage Medlemsköp är avstängt tills konfigurationen är klar.';
    }
    if (stripeKeyMissing) {
      return 'Stripe-konfiguration saknas. Betalningen kan inte starta ännu.';
    }
    if (!platformSupported) {
      return 'Inbyggd betalning är inte tillgänglig på den här plattformen.';
    }
    return null;
  }
}

class _EmbeddedCheckoutState extends StatelessWidget {
  const _EmbeddedCheckoutState({
    super.key,
    required this.launch,
    required this.interval,
    required this.stripePublishableKey,
    required this.onCheckoutRedirect,
  });

  final MembershipCheckoutLaunch launch;
  final String? interval;
  final String stripePublishableKey;
  final ValueChanged<Uri> onCheckoutRedirect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = interval == 'year' ? 'Årsmedlemskap' : 'Månadsmedlemskap';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Slutför medlemskapet',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        gap8,
        Text(
          '$label med 14 dagar provperiod. Kortuppgifter krävs för att starta provperioden.',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
        gap16,
        _EmbeddedCheckoutViewport(
          child: EmbeddedMembershipCheckoutSurface(
            stripePublishableKey: stripePublishableKey,
            clientSecret: launch.clientSecret,
            sessionId: launch.sessionId,
            orderId: launch.orderId,
            onCheckoutRedirect: onCheckoutRedirect,
          ),
        ),
        gap12,
        const _TrustLine(),
      ],
    );
  }
}

class _EmbeddedCheckoutViewport extends StatelessWidget {
  const _EmbeddedCheckoutViewport({required this.child});

  static const double _minHeight = 680;
  static const double _maxHeight = 920;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final visibleHeight = math.max(
      0,
      media.size.height - media.padding.vertical - media.viewInsets.bottom,
    );
    final targetHeight = (visibleHeight - 180).clamp(_minHeight, _maxHeight);

    return SizedBox(
      height: targetHeight.toDouble(),
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);
    return ClipRRect(
      borderRadius: radius,
      child: EffectsBackdropFilter(
        sigmaX: 14,
        sigmaY: 14,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.68),
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.56),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5B6F8F).withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.42),
                blurRadius: 0,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    );
  }
}

class _BenefitLine extends StatelessWidget {
  const _BenefitLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, size: 20, color: kBrandAzure),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _TrustLine extends StatelessWidget {
  const _TrustLine();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline, size: 18, color: kBrandAzure),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Betalningen hanteras säkert av Stripe. Aveli uppdaterar din åtkomst först när betalningen har bekräftats av servern.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(height: 1.45),
          ),
        ),
      ],
    );
  }
}

class _StatusNotice extends StatelessWidget {
  const _StatusNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF4FAFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE8F7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt({required this.onRequestLogin});

  final VoidCallback onRequestLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Logga in för att fortsätta',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        gap8,
        const Text('Du behöver ett konto för att starta medlemsköpet.'),
        gap12,
        GradientButton(
          borderRadius: BorderRadius.circular(8),
          onPressed: onRequestLogin,
          child: const Text('Logga in'),
        ),
      ],
    );
  }
}

class _IntervalButton extends StatelessWidget {
  const _IntervalButton({
    required this.label,
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GradientButton(
      borderRadius: BorderRadius.circular(8),
      onPressed: enabled ? onPressed : null,
      child: SizedBox(
        height: 22,
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(label),
        ),
      ),
    );
  }
}
