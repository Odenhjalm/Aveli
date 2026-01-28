import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/api/auth_repository.dart';
import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class NewPasswordPage extends ConsumerStatefulWidget {
  const NewPasswordPage({super.key});

  @override
  ConsumerState<NewPasswordPage> createState() => _NewPasswordPageState();
}

class _NewPasswordPageState extends ConsumerState<NewPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final envInfo = ref.watch(envInfoProvider);
    final envBlocked = envInfo.hasIssues;

    return AppScaffold(
      title: 'Nytt lösenord',
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
                                '${envInfo.message} Lösenordsbyte är avstängt tills konfigurationen är klar.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          Text(
                            'Sätt nytt lösenord',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _errorMessage != null
                                ? Padding(
                                    key: const ValueKey('newpass-error'),
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(
                                      _errorMessage!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  )
                                : const SizedBox(key: ValueKey('newpass-ok')),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Ange den e-postadress som är kopplad till kontot och välj ett nytt lösenord. '
                            'För lokala konton krävs inget e-poststeg.',
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _emailCtrl,
                            enabled: !envBlocked,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'E-postadress',
                            ),
                            textInputAction: TextInputAction.next,
                            validator: _validateEmail,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordCtrl,
                            enabled: !envBlocked,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: const InputDecoration(
                              labelText: 'Nytt lösenord',
                              hintText: 'Minst 6 tecken',
                            ),
                            textInputAction: TextInputAction.next,
                            validator: _validatePassword,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmCtrl,
                            enabled: !envBlocked,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: const InputDecoration(
                              labelText: 'Bekräfta nytt lösenord',
                            ),
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: _busy || envBlocked
                                ? null
                                : (_) => _updatePassword(context),
                            validator: _validateConfirm,
                          ),
                          const SizedBox(height: 24),
                          GradientButton(
                            onPressed: _busy || envBlocked
                                ? null
                                : () => _updatePassword(context),
                            child: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Spara nytt lösenord'),
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

  Future<void> _updatePassword(BuildContext context) async {
    final envInfo = ref.read(envInfoProvider);
    if (envInfo.hasIssues) {
      showSnack(
        context,
        '${envInfo.message} Lösenordsbyte är avstängt tills konfigurationen är klar.',
      );
      return;
    }

    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.resetPassword(email: email, newPassword: password);
      if (!mounted || !context.mounted) return;
      showSnack(context, 'Lösenord uppdaterat. Du kan nu logga in.');
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
      return 'Ange din e-postadress.';
    }
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!regex.hasMatch(email)) {
      return 'Ogiltig e-postadress.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.length < 6) {
      return 'Lösenordet måste vara minst 6 tecken.';
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value == null || value.isEmpty) {
      return 'Bekräfta ditt nya lösenord.';
    }
    if (value != _passwordCtrl.text) {
      return 'Lösenorden matchar inte.';
    }
    return null;
  }
}
