import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class InvitePage extends ConsumerStatefulWidget {
  const InvitePage({super.key, required this.token});

  final String? token;

  @override
  ConsumerState<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends ConsumerState<InvitePage> {
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveInvite());
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Inbjudan',
      showHomeAction: false,
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _isLoading
                      ? const _InviteLoading()
                      : _InviteFailure(
                          errorMessage:
                              _errorMessage ??
                              'Inbjudningslanken ar ogiltig eller har gatt ut.',
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _resolveInvite() async {
    final token = widget.token?.trim();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Inbjudningslanken saknar giltig kod.';
      });
      return;
    }

    try {
      final email = await ref.read(authRepositoryProvider).validateInvite(token);
      if (!mounted || !context.mounted) return;
      context.goNamed(
        AppRoute.signup,
        queryParameters: {'email': email, 'invite_token': token},
      );
    } on DioException catch (error) {
      if (!mounted) return;
      final failure = AppFailure.from(error);
      setState(() {
        _isLoading = false;
        _errorMessage = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Inbjudningslanken ar ogiltig eller har gatt ut.';
      });
    }
  }
}

class _InviteLoading extends StatelessWidget {
  const _InviteLoading();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: CircularProgressIndicator()),
        SizedBox(height: 24),
        Text('Kontrollerar din inbjudan...', textAlign: TextAlign.center),
      ],
    );
  }
}

class _InviteFailure extends StatelessWidget {
  const _InviteFailure({required this.errorMessage});

  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Inbjudan kunde inte anvandas',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Text(errorMessage, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        GradientButton(
          onPressed: () => context.goNamed(AppRoute.signup),
          child: const Text('Ga till registrering'),
        ),
      ],
    );
  }
}
