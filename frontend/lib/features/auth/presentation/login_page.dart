import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/shared/widgets/gradient_text.dart';
import 'package:aveli/widgets/base_page.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.redirectPath});

  final String? redirectPath;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final envInfo = ref.watch(envInfoProvider);
    final auth = ref.watch(authControllerProvider);
    final envBlocked = envInfo.hasIssues;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: BasePage(
        child: SafeArea(
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
                                  '${envInfo.message} Inloggning är avstängd tills nycklarna är på plats.',
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
                              'Logga in',
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => context.goNamed(AppRoute.landing),
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('Tillbaka'),
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: auth.error != null
                                  ? Padding(
                                      key: const ValueKey('login-error'),
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Text(
                                        auth.error!,
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    )
                                  : const SizedBox(key: ValueKey('login-ok')),
                            ),
                            gap24,
                            TextFormField(
                              controller: _emailCtrl,
                              enabled: !envBlocked,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.username],
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'E-postadress',
                                hintText: 'namn@example.com',
                              ),
                              validator: _validateEmail,
                            ),
                            gap16,
                            TextFormField(
                              controller: _passwordCtrl,
                              enabled: !envBlocked,
                              obscureText: true,
                              autofillHints: const [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: auth.isLoading || envBlocked
                                  ? null
                                  : (_) => _submit(context),
                              decoration: const InputDecoration(
                                labelText: 'Lösenord',
                                hintText: 'Minst 6 tecken',
                              ),
                              validator: _validatePassword,
                            ),
                            gap24,
                            GradientButton(
                              onPressed: auth.isLoading || envBlocked
                                  ? null
                                  : () => _submit(context),
                              child: auth.isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Logga in'),
                            ),
                            gap12,
                            TextButton(
                              onPressed: auth.isLoading || envBlocked
                                  ? null
                                  : () => context.goNamed(AppRoute.signup),
                              child: GradientText(
                                'Skapa konto',
                                style:
                                    textTheme.bodyMedium ?? const TextStyle(),
                              ),
                            ),
                            TextButton(
                              onPressed: auth.isLoading || envBlocked
                                  ? null
                                  : () => context.goNamed(
                                      AppRoute.forgotPassword,
                                    ),
                              child: GradientText(
                                'Glömt lösenord?',
                                style:
                                    textTheme.bodyMedium ?? const TextStyle(),
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
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final envInfo = ref.read(envInfoProvider);
    if (envInfo.hasIssues) {
      showSnack(
        context,
        '${envInfo.message} Logga in är avstängt tills konfigurationen är klar.',
      );
      return;
    }

    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    final controller = ref.read(authControllerProvider.notifier);
    try {
      await controller.login(email, password);
      if (!mounted || !context.mounted) return;
      showSnack(context, 'Inloggad som $email');
      final redirect = widget.redirectPath;
      if (redirect != null && redirect.startsWith('/')) {
        context.go(redirect);
      } else {
        context.goNamed(AppRoute.home);
      }
    } catch (error) {
      if (!mounted || !context.mounted) return;
      final message = error is AppFailure
          ? error.message
          : ref.read(authControllerProvider).error ??
                'Inloggning misslyckades.';
      showSnack(context, message);
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

  String? _validatePassword(String? value) {
    if (value == null || value.length < 6) {
      return 'Lösenordet måste vara minst 6 tecken.';
    }
    return null;
  }
}
