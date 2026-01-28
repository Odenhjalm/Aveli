import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/shared/widgets/gradient_text.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailCtrl = TextEditingController();
  bool _busy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final envInfo = ref.watch(envInfoProvider);
    final envBlocked = envInfo.hasIssues;
    final textTheme = Theme.of(context).textTheme;
    return AppScaffold(
      title: 'Glömt lösenord',
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
                  child: Form(
                    key: _formKey,
                    child: AutofillGroup(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (envBlocked)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                '${envInfo.message} Återställning av lösenord är avstängd tills konfigurationen är klar.',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          Text(
                            'Glömt lösenord?',
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _errorMessage != null
                                ? Padding(
                                    key: const ValueKey('forgot-error'),
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(
                                      _errorMessage!,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : const SizedBox(key: ValueKey('forgot-ok')),
                          ),
                          gap16,
                          const Text(
                            'Ange din e-postadress så skickar vi instruktioner för hur du återställer ditt lösenord.',
                          ),
                          gap24,
                          TextFormField(
                            controller: _emailCtrl,
                            enabled: !envBlocked,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: _busy || envBlocked
                                ? null
                                : (_) => _sendLink(context),
                            decoration: const InputDecoration(
                              labelText: 'E-postadress',
                              hintText: 'namn@example.com',
                            ),
                            validator: _validateEmail,
                          ),
                          gap24,
                          GradientButton(
                            onPressed: _busy || envBlocked
                                ? null
                                : () => _sendLink(context),
                            child: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Skicka återställningsinstruktioner',
                                  ),
                          ),
                          gap12,
                          TextButton(
                            onPressed: _busy || envBlocked
                                ? null
                                : () => context.goNamed(AppRoute.login),
                            child: GradientText(
                              'Tillbaka till logga in',
                              style: textTheme.bodyMedium ?? const TextStyle(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendLink(BuildContext context) async {
    final envInfo = ref.read(envInfoProvider);
    if (envInfo.hasIssues) {
      showSnack(
        context,
        '${envInfo.message} Återställning av lösenord är avstängd tills konfigurationen är klar.',
      );
      return;
    }

    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final email = _emailCtrl.text.trim();

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.requestPasswordReset(email);
      if (!mounted || !context.mounted) return;
      showSnack(
        context,
        'Om adressen finns skickar vi nu instruktioner till $email.',
      );
      context.goNamed(AppRoute.login);
    } catch (error, stackTrace) {
      if (!mounted || !context.mounted) return;
      final failure = AppFailure.from(error, stackTrace);
      setState(() {
        _errorMessage = failure.message;
      });
      showSnack(context, failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Ange en e-postadress.';
    }
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!regex.hasMatch(email)) {
      return 'Ogiltig e-postadress.';
    }
    return null;
  }
}
