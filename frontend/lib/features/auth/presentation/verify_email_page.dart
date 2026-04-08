import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

enum _VerifyPageState { checking, needsAction, verified, failed }

class VerifyEmailPage extends ConsumerStatefulWidget {
  const VerifyEmailPage({super.key, required this.token});

  final String? token;

  @override
  ConsumerState<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends ConsumerState<VerifyEmailPage> {
  _VerifyPageState _pageState = _VerifyPageState.checking;
  bool _isResending = false;
  String? _resendMessage;
  String? _resendError;

  @override
  void initState() {
    super.initState();
    unawaited(_verifyEmail());
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).profile;
    final email = _resendTargetEmail;

    return AppScaffold(
      title: 'Verifiera e-post',
      showHomeAction: false,
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: p16,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: switch (_pageState) {
                    _VerifyPageState.checking => const _VerifyEmailLoading(),
                    _VerifyPageState.verified => _VerifyEmailSuccess(
                      showLoginButton: profile == null,
                    ),
                    _VerifyPageState.needsAction => _VerifyEmailPanel(
                      title: 'Kontrollera din e-post',
                      description: email != null
                          ? 'Vi har skickat en verifieringslank till $email. Verifiera kontot for att fortsatta.'
                          : 'Verifiera ditt konto via lank i e-postmeddelandet for att fortsatta.',
                      resendMessage: _resendMessage,
                      resendError: _resendError,
                      isResending: _isResending,
                      onResend: email == null ? null : _resendVerificationEmail,
                      actionLabel: 'Till inloggning',
                      onAction: () => context.goNamed(AppRoute.login),
                    ),
                    _VerifyPageState.failed => _VerifyEmailPanel(
                      title: 'Verifieringslanken gick inte att anvanda',
                      description:
                          'Begara ett nytt verifieringsmail och forsok igen.',
                      resendMessage: _resendMessage,
                      resendError: _resendError,
                      isResending: _isResending,
                      onResend: email == null ? null : _resendVerificationEmail,
                      actionLabel: 'Till inloggning',
                      onAction: () => context.goNamed(AppRoute.login),
                    ),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? get _resendTargetEmail {
    final tokenEmail = _extractEmailFromToken(widget.token);
    if (tokenEmail != null) {
      return tokenEmail;
    }
    final profileEmail = ref.read(authControllerProvider).profile?.email.trim();
    if (profileEmail == null || profileEmail.isEmpty) {
      return null;
    }
    return profileEmail;
  }

  Future<void> _verifyEmail() async {
    final token = widget.token?.trim();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() => _pageState = _VerifyPageState.needsAction);
      return;
    }

    try {
      await ref.read(authRepositoryProvider).verifyEmail(token);
      await ref.read(authControllerProvider.notifier).loadSession();
      if (!mounted) return;
      setState(() => _pageState = _VerifyPageState.verified);
    } on DioException catch (error) {
      if (!mounted) return;
      final failure = AppFailure.from(error);
      setState(() {
        _pageState = _VerifyPageState.failed;
        _resendError = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pageState = _VerifyPageState.failed;
        _resendError = 'Kunde inte verifiera e-postadressen.';
      });
    }
  }

  Future<void> _resendVerificationEmail() async {
    final email = _resendTargetEmail;
    if (email == null) {
      if (!mounted) return;
      setState(() {
        _resendError = 'Kunde inte avgora vilken e-postadress som ska anvandas.';
        _resendMessage = null;
      });
      return;
    }

    setState(() {
      _isResending = true;
      _resendError = null;
      _resendMessage = null;
    });

    try {
      await ref.read(authRepositoryProvider).sendVerificationEmail(email);
      if (!mounted) return;
      setState(() {
        _resendMessage = 'En ny verifieringslank har skickats.';
      });
    } on DioException catch (error) {
      if (!mounted) return;
      final failure = AppFailure.from(error);
      setState(() {
        _resendError = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resendError = 'Kunde inte skicka verifieringsmail.';
      });
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  String? _extractEmailFromToken(String? token) {
    if (token == null || token.isEmpty) {
      return null;
    }

    final segments = token.split('.');
    if (segments.length < 2) {
      return null;
    }

    try {
      final payload = base64Url.decode(base64Url.normalize(segments[1]));
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final sub = decoded['sub'];
      if (sub is! String || sub.trim().isEmpty) {
        return null;
      }
      return sub.trim().toLowerCase();
    } catch (_) {
      return null;
    }
  }
}

class _VerifyEmailLoading extends StatelessWidget {
  const _VerifyEmailLoading();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: CircularProgressIndicator()),
        SizedBox(height: 24),
        Text('Verifierar din e-post...', textAlign: TextAlign.center),
      ],
    );
  }
}

class _VerifyEmailSuccess extends StatelessWidget {
  const _VerifyEmailSuccess({required this.showLoginButton});

  final bool showLoginButton;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'E-postadressen ar verifierad',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        gap16,
        Text(
          showLoginButton
              ? 'Logga in for att fortsatta onboardingflodet.'
              : 'Vi uppdaterar ditt konto och skickar dig vidare automatiskt.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium,
        ),
        if (showLoginButton) ...[
          gap24,
          GradientButton(
            onPressed: () => context.goNamed(AppRoute.login),
            child: const Text('Till inloggning'),
          ),
        ],
      ],
    );
  }
}

class _VerifyEmailPanel extends StatelessWidget {
  const _VerifyEmailPanel({
    required this.title,
    required this.description,
    required this.resendMessage,
    required this.resendError,
    required this.isResending,
    required this.onResend,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String description;
  final String? resendMessage;
  final String? resendError;
  final bool isResending;
  final Future<void> Function()? onResend;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        gap16,
        Text(
          description,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium,
        ),
        if (resendMessage != null) ...[
          gap16,
          Text(
            resendMessage!,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (resendError != null) ...[
          gap16,
          Text(
            resendError!,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (onResend != null) ...[
          gap24,
          GradientButton(
            onPressed: isResending ? null : () => unawaited(onResend!()),
            child: isResending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Skicka ny verifieringslank'),
          ),
        ],
        gap12,
        TextButton(
          onPressed: isResending ? null : onAction,
          child: Text(actionLabel),
        ),
      ],
    );
  }
}
