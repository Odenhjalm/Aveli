import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/api/auth_repository.dart';
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
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_verifyEmail());
  }

  @override
  Widget build(BuildContext context) {
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
                  child: _isVerifying
                      ? const _VerifyEmailLoading()
                      : _VerifyEmailError(
                          message:
                              _errorMessage ?? 'Verifieringen misslyckades.',
                          onRetry: _verifyEmail,
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
      setState(() {
        _isVerifying = false;
        _errorMessage = 'Verifieringslanken saknar token.';
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isVerifying = true;
        _errorMessage = null;
      });
    }

    try {
      await ref
          .read(apiClientProvider)
          .get<Map<String, dynamic>>(
            '/auth/verify-email',
            queryParameters: {'token': token},
            skipAuth: true,
          );
      if (!mounted || !context.mounted) return;
      context.go('/create-profile');
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = _messageFromDio(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = 'Kunde inte verifiera e-postadressen.';
      });
    }
  }

  String _messageFromDio(DioException error) {
    final payload = error.response?.data;
    if (payload is Map<String, dynamic>) {
      final detail = payload['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail;
      }
    }
    return 'Kunde inte verifiera e-postadressen.';
  }
}

class _VerifyEmailLoading extends StatelessWidget {
  const _VerifyEmailLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        CircularProgressIndicator(),
        SizedBox(height: 24),
        Text('Verifierar din e-postadress...', textAlign: TextAlign.center),
      ],
    );
  }
}

class _VerifyEmailError extends StatelessWidget {
  const _VerifyEmailError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        gap24,
        GradientButton(
          onPressed: () => unawaited(onRetry()),
          child: const Text('Försök igen'),
        ),
        gap12,
        TextButton(
          onPressed: () => context.go('/login'),
          child: const Text('Till logga in'),
        ),
      ],
    );
  }
}
