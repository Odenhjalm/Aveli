import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class VerifyEmailPage extends ConsumerStatefulWidget {
  const VerifyEmailPage({super.key, required this.token});

  final String? token;

  @override
  ConsumerState<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends ConsumerState<VerifyEmailPage> {
  bool _isVerifying = true;
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
    return AppScaffold(
      title: 'Bekräfta e-post',
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
                  child: _isVerifying
                      ? const _VerifyEmailLoading()
                      : _VerifyEmailFailure(
                          resendMessage: _resendMessage,
                          resendError: _resendError,
                          isResending: _isResending,
                          onResend: _resendVerificationEmail,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _verifyEmail() async {
    final token = widget.token?.trim();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() => _isVerifying = false);
      return;
    }

    try {
      final result = await ref.read(authRepositoryProvider).verifyEmail(token);
      await ref.read(authControllerProvider.notifier).loadSession();
      if (!mounted || !context.mounted) return;
      if (result.onboarding != null) {
        context.go(result.onboarding!.nextStep);
        return;
      }
      final redirect = result.redirectAfterLogin;
      if (redirect != null && redirect.isNotEmpty) {
        context.goNamed(
          AppRoute.login,
          queryParameters: {'redirect': redirect},
        );
        return;
      }
      context.goNamed(AppRoute.login);
    } on DioException {
      if (!mounted) return;
      setState(() => _isVerifying = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isVerifying = false);
    }
  }

  Future<void> _resendVerificationEmail() async {
    final email = _extractEmailFromToken(widget.token);
    if (email == null) {
      if (!mounted) return;
      setState(() {
        _resendError =
            'Det gick inte att avgöra vilken e-postadress som ska få en ny länk.';
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
        _resendMessage = 'Om kontot finns har en ny verifieringslänk skickats.';
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _resendError = _resendErrorMessage(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resendError = 'Det gick inte att skicka en ny verifieringslänk.';
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

  String _resendErrorMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail;
      }
      final message = data['error'];
      if (message is String && message.trim().isNotEmpty) {
        if (message == 'rate_limited') {
          return 'Vänta en stund innan du begär en ny verifieringslänk.';
        }
        return message;
      }
    }
    return 'Det gick inte att skicka en ny verifieringslänk.';
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
        Text('Bekräftar din e-post...', textAlign: TextAlign.center),
      ],
    );
  }
}

class _VerifyEmailFailure extends StatelessWidget {
  const _VerifyEmailFailure({
    required this.resendMessage,
    required this.resendError,
    required this.isResending,
    required this.onResend,
  });

  final String? resendMessage;
  final String? resendError;
  final bool isResending;
  final Future<void> Function() onResend;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Verifieringslänken är ogiltig eller har gått ut',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        gap16,
        Text(
          'Begär en ny verifieringslänk för att fortsätta till medlemskap och onboarding.',
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
        gap24,
        GradientButton(
          onPressed: isResending ? null : () => unawaited(onResend()),
          child: isResending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Resend verification email'),
        ),
        gap12,
        TextButton(
          onPressed: isResending ? null : () => context.goNamed(AppRoute.login),
          child: const Text('Back to login'),
        ),
      ],
    );
  }
}
