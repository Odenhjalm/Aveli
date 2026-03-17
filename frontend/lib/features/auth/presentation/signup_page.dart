import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/env/env_state.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({
    super.key,
    this.initialEmail,
    this.inviteToken,
    this.referralCode,
  });

  final String? initialEmail;
  final String? inviteToken;
  final String? referralCode;

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _displayNameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _referralCodeCtrl = TextEditingController();
  String? _inviteToken;

  @override
  void initState() {
    super.initState();
    final email = widget.initialEmail?.trim();
    if (email != null && email.isNotEmpty) {
      _emailCtrl.text = email;
    }
    final referralCode = widget.referralCode?.trim();
    if (referralCode != null && referralCode.isNotEmpty) {
      _referralCodeCtrl.text = referralCode;
    }
    final inviteToken = widget.inviteToken?.trim();
    if (inviteToken != null && inviteToken.isNotEmpty) {
      _inviteToken = inviteToken;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _displayNameCtrl.dispose();
    _passwordCtrl.dispose();
    _referralCodeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final envInfo = ref.watch(envInfoProvider);
    final authState = ref.watch(authControllerProvider);
    final envBlocked = envInfo.hasIssues;
    final busy = authState.isLoading;
    final textTheme = Theme.of(context).textTheme;
    final hasInviteToken = _inviteToken != null;

    return AppScaffold(
      title: 'Skapa konto',
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
                                '${envInfo.message} Nyregistrering är avstängd tills konfigurationen är klar.',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          Text(
                            'Skapa konto',
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: authState.error != null
                                ? Padding(
                                    key: const ValueKey('signup-error'),
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(
                                      authState.error!,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : const SizedBox(key: ValueKey('signup-ok')),
                          ),
                          gap24,
                          if (hasInviteToken)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                'Du registrerar dig via en personlig inbjudan. E-postadressen är förifylld från länken.',
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          TextFormField(
                            controller: _emailCtrl,
                            enabled: !envBlocked && !hasInviteToken,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'E-postadress',
                              hintText: 'namn@example.com',
                            ),
                            validator: _validateEmail,
                          ),
                          gap16,
                          TextFormField(
                            controller: _displayNameCtrl,
                            enabled: !envBlocked,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Namn',
                              hintText: 'Vad vill du kallas?',
                            ),
                            validator: _validateDisplayName,
                          ),
                          gap16,
                          TextFormField(
                            controller: _passwordCtrl,
                            enabled: !envBlocked,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Lösenord',
                              hintText: 'Minst 6 tecken',
                            ),
                            validator: _validatePassword,
                          ),
                          gap16,
                          TextFormField(
                            controller: _referralCodeCtrl,
                            enabled: !envBlocked,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: busy || envBlocked
                                ? null
                                : (_) => _signUp(context),
                            decoration: const InputDecoration(
                              labelText: 'Inbjudningskod (valfritt)',
                              hintText: 'Ange din referral-kod',
                            ),
                          ),
                          gap24,
                          GradientButton(
                            onPressed: busy || envBlocked
                                ? null
                                : () => _signUp(context),
                            child: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Skapa konto'),
                          ),
                          gap12,
                          TextButton(
                            onPressed: busy || envBlocked
                                ? null
                                : () => context.goNamed(AppRoute.login),
                            child: const Text('Har du konto? Logga in'),
                          ),
                          gap24,
                          Text(
                            'Alternativ',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          gap12,
                          OutlinedButton(
                            onPressed: () => showSnack(
                              context,
                              'Magiska länkar kommer tillbaka när e-postflödet är klart.',
                            ),
                            child: const Text(
                              'Skicka magisk länk (ej tillgängligt)',
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

  Future<void> _signUp(BuildContext context) async {
    final envInfo = ref.read(envInfoProvider);
    if (envInfo.hasIssues) {
      showSnack(
        context,
        '${envInfo.message} Nyregistrering är avstängd tills konfigurationen är klar.',
      );
      return;
    }

    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final email = _emailCtrl.text.trim();
    final displayName = _displayNameCtrl.text.trim();
    final password = _passwordCtrl.text;
    final referralCode = _referralCodeCtrl.text.trim();

    try {
      final controller = ref.read(authControllerProvider.notifier);
      await controller.register(
        email,
        password,
        displayName: displayName,
        referralCode: referralCode.isEmpty ? null : referralCode,
        inviteToken: _inviteToken,
      );
      if (!mounted || !context.mounted) return;
      final verificationStatus = ref
          .read(authControllerProvider)
          .verificationEmailStatus;
      showSnack(context, switch (verificationStatus) {
        'sent' =>
          'Konto skapat. Kontrollera din e-post för att verifiera kontot.',
        'log_only' =>
          'Konto skapat, men e-postleverans är inte konfigurerad i miljön ännu.',
        'failed' =>
          'Konto skapat, men verifieringsmejlet kunde inte skickas. Försök igen från inloggningen.',
        _ => 'Konto skapat. Fortsätt med onboarding.',
      });
      context.goNamed(AppRoute.resumeOnboarding);
    } catch (error) {
      if (!mounted || !context.mounted) return;
      final message = error is AppFailure
          ? error.message
          : ref.read(authControllerProvider).error ??
                'Något gick fel. Försök igen.';
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

  String? _validateDisplayName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) {
      return 'Ange ett namn eller alias.';
    }
    if (name.length < 2) {
      return 'Namnet måste vara minst 2 tecken.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.length < 6) {
      return 'Lösenordet måste vara minst 6 tecken.';
    }
    return null;
  }
}
