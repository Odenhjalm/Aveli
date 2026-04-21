import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/features/media/application/profile_avatar_upload_controller.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/app_avatar.dart';

typedef OnboardingAvatarFile = ProfileAvatarUploadFile;
typedef OnboardingAvatarPicker = ProfileAvatarPicker;

final onboardingAvatarPickerProvider = profileAvatarPickerProvider;

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
  bool _isHydratingControllers = false;
  String? _hydratedProfileId;
  String? _nameError;
  ProfileAvatarUploadSnapshot _avatarUpload =
      const ProfileAvatarUploadSnapshot.empty();

  bool get _isNameValid => _displayNameCtrl.text.trim().isNotEmpty;
  bool get _isAvatarBusy => _avatarUpload.isBusy;

  @override
  void initState() {
    super.initState();
    _displayNameCtrl = TextEditingController();
    _displayNameCtrl.addListener(_handleDisplayNameChanged);
    _bioCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _displayNameCtrl.removeListener(_handleDisplayNameChanged);
    _displayNameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _handleDisplayNameChanged() {
    if (_isHydratingControllers || !mounted) return;
    setState(() {
      if (_nameError != null) {
        _nameError = null;
      }
    });
  }

  void _hydrateControllers(Profile? profile) {
    if (profile == null || _hydratedProfileId == profile.id) return;
    _hydratedProfileId = profile.id;
    _isHydratingControllers = true;
    try {
      _displayNameCtrl.text = profile.displayName ?? '';
      _bioCtrl.text = profile.bio ?? '';
    } finally {
      _isHydratingControllers = false;
    }
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
                    'Skriv ditt namn så kan vi välkomna dig rätt. Bio är valfritt och profilbild kan läggas till nu eller senare.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (widget.referralCode?.trim().isNotEmpty == true) ...[
                    gap12,
                    Text(
                      'Din referenskod kopplas när profilen sparas.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  gap24,
                  _buildAvatarPicker(context, profile),
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
                    onPressed: (!_isNameValid || _isSubmitting)
                        ? null
                        : _saveProfile,
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

  Widget _buildAvatarPicker(BuildContext context, Profile? profile) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final photoUrl = profile?.photoUrl?.trim();
    final hasSavedAvatar =
        _avatarUpload.attachedAvatarMediaId?.trim().isNotEmpty == true ||
        profile?.avatarMediaId?.trim().isNotEmpty == true;
    final effectiveStage =
        _avatarUpload.stage == ProfileAvatarUploadStage.empty && hasSavedAvatar
        ? ProfileAvatarUploadStage.attached
        : _avatarUpload.stage;
    final canPickAvatar = !_isAvatarBusy && !_isSubmitting;
    final progress = _avatarUpload.progress <= 0 || _avatarUpload.progress >= 1
        ? null
        : _avatarUpload.progress;

    Widget image;
    if (_avatarUpload.previewBytes != null &&
        _avatarUpload.previewBytes!.isNotEmpty) {
      image = Image.memory(
        _avatarUpload.previewBytes!,
        fit: BoxFit.cover,
        width: 112,
        height: 112,
        gaplessPlayback: true,
      );
    } else if (photoUrl != null && photoUrl.isNotEmpty) {
      image = AppAvatar(url: photoUrl, size: 112);
    } else {
      image = Icon(
        Icons.person_add_alt_1,
        size: 42,
        color: colorScheme.onSurfaceVariant,
      );
    }

    return Column(
      children: [
        Semantics(
          button: true,
          label: 'Välj profilbild',
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: canPickAvatar ? _pickAndUploadAvatar : null,
              child: SizedBox(
                width: 124,
                height: 124,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              _avatarUpload.stage ==
                                  ProfileAvatarUploadStage.failed
                              ? colorScheme.error
                              : colorScheme.outlineVariant,
                          width: 2,
                        ),
                      ),
                      child: ClipOval(child: Center(child: image)),
                    ),
                    if (_avatarUpload.stage ==
                        ProfileAvatarUploadStage.uploading)
                      SizedBox(
                        width: 122,
                        height: 122,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 4,
                        ),
                      ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: _AvatarBadge(stage: effectiveStage),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _avatarActionText(effectiveStage),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _avatarStatusText(effectiveStage),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        if (_avatarUpload.errorMessage != null &&
            _avatarUpload.errorMessage!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _avatarUpload.errorMessage!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  String _avatarActionText(ProfileAvatarUploadStage stage) {
    return profileAvatarActionText(stage);
  }

  String _avatarStatusText(ProfileAvatarUploadStage stage) {
    return profileAvatarVisibleStatus(_avatarUpload.copyWith(stage: stage));
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_isAvatarBusy) return;
    try {
      final picker = ref.read(onboardingAvatarPickerProvider);
      final picked = await picker();
      if (!mounted || picked == null) return;
      final controller = ref.read(profileAvatarUploadControllerProvider);
      final profile = await controller.uploadAndAttach(
        picked,
        onSnapshot: (snapshot) {
          if (!mounted) return;
          setState(() => _avatarUpload = snapshot);
        },
      );
      ref
          .read(authControllerProvider.notifier)
          .refreshProfileProjection(profile);
      if (!mounted) return;
      setState(() {
        _avatarUpload = _avatarUpload.copyWith(
          stage: ProfileAvatarUploadStage.attached,
          attachedAvatarMediaId:
              profile.avatarMediaId ?? _avatarUpload.attachedAvatarMediaId,
          status: 'Profilbilden är sparad.',
          clearErrorMessage: true,
        );
      });
    } catch (error, stackTrace) {
      _handleAvatarFailure(error, stackTrace);
    }
  }

  void _handleAvatarFailure(Object error, StackTrace stackTrace) {
    if (!mounted) return;
    AppFailure.from(error, stackTrace);
    setState(() {
      _avatarUpload = _avatarUpload.asFailed();
    });
    showSnack(context, 'Kunde inte spara profilbilden. Försök igen.');
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

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({required this.stage});

  final ProfileAvatarUploadStage stage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isError = stage == ProfileAvatarUploadStage.failed;
    final isDone = stage == ProfileAvatarUploadStage.attached;
    final isBusy = stage.isBusy;

    final icon = isError
        ? Icons.priority_high
        : isDone
        ? Icons.check
        : isBusy
        ? Icons.cloud_upload_outlined
        : Icons.add_a_photo_outlined;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isError ? colorScheme.error : colorScheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.surface, width: 3),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: 18,
        color: isError ? colorScheme.onError : colorScheme.onPrimary,
      ),
    );
  }
}
