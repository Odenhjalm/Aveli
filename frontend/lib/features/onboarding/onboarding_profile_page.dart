import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';

class OnboardingProfilePage extends ConsumerStatefulWidget {
  const OnboardingProfilePage({super.key, this.referralCode});

  final String? referralCode;

  @override
  ConsumerState<OnboardingProfilePage> createState() =>
      _OnboardingProfilePageState();
}

class _OnboardingProfilePageState extends ConsumerState<OnboardingProfilePage> {
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _bioCtrl;
  bool _isSubmitting = false;
  String? _hydratedProfileId;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _displayNameCtrl = TextEditingController();
    _bioCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _hydrateControllers(Profile? profile) {
    if (profile == null || _hydratedProfileId == profile.id) return;
    _hydratedProfileId = profile.id;
    _displayNameCtrl.text = profile.displayName ?? '';
    _bioCtrl.text = profile.bio ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).profile;
    _hydrateControllers(profile);

    return AppScaffold(
      title: 'Skapa profil',
      showHomeAction: false,
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: p16,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Vad ska vi kalla dig?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  gap12,
                  Text(
                    'Skriv ditt namn så kan vi välkomna dig rätt. Bio är valfritt och profilbild kan läggas till senare.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (widget.referralCode?.trim().isNotEmpty == true) ...[
                    gap12,
                    Text(
                      'Din referenskod kopplas nÃ¤r profilen sparas.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  gap24,
                  TextField(
                    controller: _displayNameCtrl,
                    enabled: !_isSubmitting,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Namn',
                      hintText: 'Ditt namn',
                      errorText: _nameError,
                    ),
                    onChanged: (_) {
                      if (_nameError == null) return;
                      setState(() => _nameError = null);
                    },
                  ),
                  gap16,
                  TextField(
                    controller: _bioCtrl,
                    enabled: !_isSubmitting,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Bio',
                      hintText: 'Valfritt',
                    ),
                  ),
                  gap20,
                  FilledButton(
                    onPressed: _isSubmitting ? null : _saveProfile,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Fortsätt till välkomststeget'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final displayName = _displayNameCtrl.text.trim();
    if (displayName.isEmpty) {
      setState(() => _nameError = 'Skriv ditt namn för att fortsätta.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _nameError = null;
    });

    try {
      final bio = _bioCtrl.text.trim();
      await ref
          .read(authControllerProvider.notifier)
          .createProfile(
            displayName: displayName,
            bio: bio,
            referralCode: widget.referralCode,
          );
      if (!mounted || !context.mounted) return;
      context.goNamed(AppRoute.welcome);
    } catch (error, stackTrace) {
      if (!mounted) return;
      final failure = AppFailure.from(error, stackTrace);
      showSnack(context, 'Kunde inte spara profilen: ${failure.message}');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}
