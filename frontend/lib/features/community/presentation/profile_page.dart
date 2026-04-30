import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/auth/application/user_access_provider.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/data/repositories/profile_repository.dart';
import 'package:aveli/features/media/application/profile_avatar_upload_controller.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/effects_backdrop_filter.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/shared/widgets/app_avatar.dart';
import 'package:aveli/shared/widgets/top_nav_action_buttons.dart';
import 'package:aveli/features/community/presentation/widgets/profile_logout_section.dart';
import 'package:aveli/shared/utils/snack.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _bioCtrl;
  bool _editing = false;
  bool _saving = false;
  String? _hydratedProfileId;
  ProfileAvatarUploadSnapshot _avatarUpload =
      const ProfileAvatarUploadSnapshot.empty();

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

  void _hydrateControllers(Profile profile) {
    final desiredName = profile.displayName ?? '';
    final desiredBio = profile.bio ?? '';
    final profileChanged = _hydratedProfileId != profile.id;
    if (profileChanged || (!_editing && !_saving)) {
      _hydratedProfileId = profile.id;
      _displayNameCtrl.text = desiredName;
      _bioCtrl.text = desiredBio;
    }
  }

  void _startEditing() {
    setState(() => _editing = true);
  }

  void _cancelEditing(Profile profile) {
    setState(() {
      _editing = false;
      _saving = false;
      _displayNameCtrl.text = profile.displayName ?? '';
      _bioCtrl.text = profile.bio ?? '';
    });
  }

  Future<void> _saveProfile(Profile profile) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(profileRepositoryProvider);
      final updated = await repo.updateMe(
        displayName: _displayNameCtrl.text.trim().isEmpty
            ? null
            : _displayNameCtrl.text.trim(),
        bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
      );
      ref
          .read(authControllerProvider.notifier)
          .refreshProfileProjection(updated);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editing = false;
        _hydratedProfileId = updated.id;
        _displayNameCtrl.text = updated.displayName ?? '';
        _bioCtrl.text = updated.bio ?? '';
      });
      showSnack(context, 'Profilen uppdaterad.');
    } catch (error, stackTrace) {
      final failure = AppFailure.from(error, stackTrace);
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'Kunde inte spara: ${failure.message}');
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_avatarUpload.isBusy) return;
    try {
      final picker = ref.read(profileAvatarPickerProvider);
      final picked = await picker();
      if (!mounted || picked == null) return;
      final controller = ref.read(profileAvatarUploadControllerProvider);
      final updatedProfile = await controller.uploadAndAttach(
        picked,
        onSnapshot: (snapshot) {
          if (!mounted) return;
          setState(() => _avatarUpload = snapshot);
        },
      );
      ref
          .read(authControllerProvider.notifier)
          .refreshProfileProjection(updatedProfile);
      if (!mounted) return;
      setState(() {
        _avatarUpload = ProfileAvatarUploadSnapshot(
          stage: ProfileAvatarUploadStage.attached,
          progress: 1,
          status: 'Profilbilden är sparad.',
          attachedAvatarMediaId: updatedProfile.avatarMediaId,
        );
      });
      showSnack(context, 'Profilbilden är sparad.');
    } catch (error, stackTrace) {
      _handleAvatarFailure(error, stackTrace);
    }
  }

  void _handleAvatarFailure(Object error, StackTrace stackTrace) {
    if (!mounted) return;
    AppFailure.from(error, stackTrace);
    setState(() => _avatarUpload = _avatarUpload.asFailed());
    showSnack(context, 'Kunde inte spara profilbilden. Försök igen.');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final access = ref.watch(userAccessProvider);
    final profile = authState.profile;
    if (authState.isLoading && profile == null) {
      return const AppScaffold(
        title: 'Profil',
        neutralBackground: true,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (profile == null) {
      return const _LoginRequiredCard();
    }

    _hydrateControllers(profile);

    return AppScaffold(
      title: 'Profil',
      extendBodyBehindAppBar: true,
      transparentAppBar: true,
      showHomeAction: false,
      onBack: () => context.goNamed(AppRoute.home),
      actions: const [TopNavActionButtons()],
      background: FullBleedBackground(
        alignment: Alignment.center,
        topOpacity: 0.38,
        sideVignette: 0.15,
        overlayColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.black.withValues(alpha: 0.3)
            : const Color(0xFFFFE2B8).withValues(alpha: 0.22),
      ),
      body: LayoutBuilder(
        builder: (context, _) {
          const columnGap = SizedBox(height: 16);

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 130, 16, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _IdentitySection(
                  profile: profile,
                  isTeacher: access.isTeacher,
                  isAdmin: access.isAdmin,
                  displayNameController: _displayNameCtrl,
                  avatarUpload: _avatarUpload,
                  editing: _editing,
                  saving: _saving,
                  onStartEditing: _startEditing,
                  onCancelEditing: () => _cancelEditing(profile),
                  onSaveProfile: () => _saveProfile(profile),
                  onPickAvatar: _pickAndUploadAvatar,
                ),
                columnGap,
                _BioSection(
                  profile: profile,
                  editing: _editing,
                  saving: _saving,
                  controller: _bioCtrl,
                ),
                columnGap,
                _ServicesSection(
                  isTeacher: access.isTeacher,
                  onOpenStudio: () => context.goNamed(AppRoute.studio),
                ),
                columnGap,
                _SubscriptionEntry(
                  onOpenSubscription: () =>
                      context.push(RoutePath.profileSubscription),
                ),
                columnGap,
                const _PasswordResetSection(),
                const ProfileLogoutSection(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _IdentitySection extends StatelessWidget {
  const _IdentitySection({
    required this.profile,
    required this.isTeacher,
    required this.isAdmin,
    required this.displayNameController,
    required this.avatarUpload,
    required this.editing,
    required this.saving,
    required this.onStartEditing,
    required this.onCancelEditing,
    required this.onSaveProfile,
    required this.onPickAvatar,
  });

  final Profile profile;
  final bool isTeacher;
  final bool isAdmin;
  final TextEditingController displayNameController;
  final ProfileAvatarUploadSnapshot avatarUpload;
  final bool editing;
  final bool saving;
  final VoidCallback onStartEditing;
  final VoidCallback onCancelEditing;
  final VoidCallback onSaveProfile;
  final VoidCallback onPickAvatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = profile.displayName?.trim().isNotEmpty == true
        ? profile.displayName!
        : profile.email;
    final initialsBuffer = StringBuffer();
    for (final part in displayName.trim().split(RegExp(r'\s+'))) {
      if (part.isEmpty) {
        continue;
      }
      initialsBuffer.write(part.characters.first.toUpperCase());
      if (initialsBuffer.length >= 2) {
        break;
      }
    }
    final initials = initialsBuffer.toString();
    final joinDate = MaterialLocalizations.of(
      context,
    ).formatFullDate(profile.createdAt.toLocal());

    final chips = <Widget>[
      _ProfileChip(
        icon: Icons.calendar_today_rounded,
        label: 'Medlem sedan $joinDate',
      ),
      if (isTeacher)
        const _ProfileChip(
          icon: Icons.workspace_premium_rounded,
          label: 'Lärare',
        ),
      if (isAdmin)
        const _ProfileChip(icon: Icons.shield_rounded, label: 'Admin'),
    ];

    final actions = <Widget>[];
    if (!editing) {
      actions.add(
        TextButton.icon(
          onPressed: onStartEditing,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Ändra'),
        ),
      );
    } else {
      actions.addAll([
        TextButton(
          onPressed: saving ? null : onCancelEditing,
          child: const Text('Avbryt'),
        ),
        FilledButton.icon(
          onPressed: saving ? null : onSaveProfile,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Spara'),
        ),
      ]);
    }

    return _GlassSection(
      title: 'Din profil',
      actions: actions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ProfileAvatar(
                    profile: profile,
                    initials: initials,
                    displayName: displayName,
                    uploadSnapshot: avatarUpload,
                    onTap: onPickAvatar,
                  ),
                  if (_shouldShowAvatarStatus(avatarUpload)) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 112,
                      child: Text(
                        profileAvatarVisibleStatus(avatarUpload),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              avatarUpload.stage ==
                                  ProfileAvatarUploadStage.failed
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  if (avatarUpload.errorMessage?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 112,
                      child: Text(
                        avatarUpload.errorMessage!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (editing)
                      TextField(
                        controller: displayNameController,
                        enabled: !saving,
                        decoration: InputDecoration(
                          labelText: 'Visningsnamn',
                          hintText: displayName,
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                        ),
                      )
                    else
                      Text(
                        displayName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(profile.email, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: chips),
        ],
      ),
    );
  }
}

bool _shouldShowAvatarStatus(ProfileAvatarUploadSnapshot snapshot) {
  return snapshot.stage != ProfileAvatarUploadStage.empty ||
      snapshot.status?.isNotEmpty == true ||
      snapshot.errorMessage?.isNotEmpty == true;
}

class _ProfileAvatar extends ConsumerWidget {
  const _ProfileAvatar({
    required this.profile,
    required this.initials,
    required this.displayName,
    required this.uploadSnapshot,
    required this.onTap,
  });

  final Profile profile;
  final String initials;
  final String displayName;
  final ProfileAvatarUploadSnapshot uploadSnapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final photoPath = profile.photoUrl?.trim();
    final resolvedUrl = photoPath == null || photoPath.isEmpty
        ? null
        : Uri.parse(
            ref.read(appConfigProvider).apiBaseUrl,
          ).resolve(photoPath).toString();
    final avatarLabel = initials.isEmpty
        ? displayName.characters.first.toUpperCase()
        : initials;
    final isError = uploadSnapshot.stage == ProfileAvatarUploadStage.failed;
    final isDone = uploadSnapshot.stage == ProfileAvatarUploadStage.attached;
    final isBusy = uploadSnapshot.isBusy;
    final tooltip = resolvedUrl == null ? 'Välj profilbild' : 'Byt profilbild';
    final progress =
        uploadSnapshot.progress <= 0 || uploadSnapshot.progress >= 1
        ? null
        : uploadSnapshot.progress;

    Widget image;
    if (uploadSnapshot.previewBytes != null &&
        uploadSnapshot.previewBytes!.isNotEmpty) {
      image = Image.memory(
        uploadSnapshot.previewBytes!,
        fit: BoxFit.cover,
        width: 64,
        height: 64,
        gaplessPlayback: true,
      );
    } else if (resolvedUrl == null) {
      image = CircleAvatar(
        radius: 32,
        backgroundColor: Colors.white.withValues(alpha: 0.2),
        child: Text(
          avatarLabel,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    } else {
      image = AppAvatar(url: resolvedUrl, size: 64);
    }

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: !isBusy,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            key: const ValueKey('profile-avatar-picker'),
            customBorder: const CircleBorder(),
            onTap: isBusy ? null : onTap,
            child: SizedBox(
              width: 76,
              height: 76,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isError
                            ? colorScheme.error
                            : Colors.white.withValues(alpha: 0.18),
                        width: 2,
                      ),
                    ),
                    child: ClipOval(child: Center(child: image)),
                  ),
                  if (uploadSnapshot.stage ==
                      ProfileAvatarUploadStage.uploading)
                    SizedBox(
                      width: 74,
                      height: 74,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 3,
                      ),
                    )
                  else if (isBusy)
                    const SizedBox(
                      width: 74,
                      height: 74,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isError
                            ? colorScheme.error
                            : isDone
                            ? colorScheme.primary
                            : Colors.black54,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          isError
                              ? Icons.priority_high
                              : isDone
                              ? Icons.check
                              : isBusy
                              ? Icons.cloud_upload_outlined
                              : Icons.add_a_photo_outlined,
                          size: 16,
                          color: isError
                              ? colorScheme.onError
                              : isDone
                              ? colorScheme.onPrimary
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BioSection extends StatelessWidget {
  const _BioSection({
    required this.profile,
    required this.editing,
    required this.saving,
    required this.controller,
  });

  final Profile profile;
  final bool editing;
  final bool saving;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bio = profile.bio?.trim();
    return _GlassSection(
      title: 'Om mig',
      child: editing
          ? TextField(
              controller: controller,
              enabled: !saving,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: 'Beskrivning',
                hintText:
                    'Berätta kort om dig själv och vad du erbjuder. Denna text visas i communityt och för potentiella kunder.',
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
              ),
            )
          : Text(
              bio?.isNotEmpty == true
                  ? bio!
                  : 'Berätta kort om dig själv och vad du erbjuder. Denna text visas i communityt och för potentiella kunder.',
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
    );
  }
}

class _SubscriptionEntry extends StatelessWidget {
  const _SubscriptionEntry({required this.onOpenSubscription});

  final VoidCallback onOpenSubscription;

  @override
  Widget build(BuildContext context) {
    final cardBorder = Colors.white.withValues(alpha: 0.16);
    final t = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      opacity: 0.18,
      borderRadius: BorderRadius.circular(16),
      borderColor: cardBorder,
      onTap: onOpenSubscription,
      child: Row(
        children: [
          const Icon(Icons.workspace_premium_rounded, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Min prenumeration',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hantera medlemskap och betalplan.',
                  style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _ServicesSection extends StatelessWidget {
  const _ServicesSection({required this.isTeacher, required this.onOpenStudio});

  final bool isTeacher;
  final VoidCallback onOpenStudio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (isTeacher) {
      return _GlassSection(
        title: 'Mina tjänster',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Du är certifierad Pro och kan sälja sessioner, ceremonier och vägledning.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            GradientButton(
              onPressed: onOpenStudio,
              child: const Text('Hantera i Studio'),
            ),
            const SizedBox(height: 8),
            Text(
              'Öppna Studio för att uppdatera tjänster, priser och tillgänglighet.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return _GlassSection(
      title: 'Mina tjänster',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'När du slutfört sista delen i Pro-kursen aktiveras möjligheten att sälja tjänster.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Dina publicerade tjänster visas här så snart certifieringen är klar.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordResetSection extends StatelessWidget {
  const _PasswordResetSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _GlassSection(
      title: 'Byt lösenord',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Byt lösenord via flödet för glömt lösenord.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          GradientButton.icon(
            onPressed: () => context.goNamed(AppRoute.forgotPassword),
            icon: const Icon(Icons.lock_reset_rounded),
            label: const Text('Gå till glömt lösenord'),
          ),
        ],
      ),
    );
  }
}

class _GlassSection extends StatelessWidget {
  const _GlassSection({required this.title, required this.child, this.actions});

  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.38);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: EffectsBackdropFilter(
        sigmaX: 20,
        sigmaY: 20,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [baseColor, baseColor.withValues(alpha: 0.68)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (actions != null)
                      Wrap(spacing: 8, runSpacing: 8, children: actions!),
                  ],
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        color: Colors.white.withValues(alpha: 0.12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurface),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _LoginRequiredCard extends StatelessWidget {
  const _LoginRequiredCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final router = GoRouter.of(context);
    final redirectTarget = router.namedLocation(AppRoute.profile);
    return AppScaffold(
      title: 'Profil',
      neutralBackground: true,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Logga in för att fortsätta',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Du behöver ett konto för att se din profil.'),
                  const SizedBox(height: 16),
                  GradientButton(
                    onPressed: () => context.goNamed(
                      AppRoute.login,
                      queryParameters: {'redirect': redirectTarget},
                    ),
                    child: const Text('Logga in'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => context.goNamed(
                      AppRoute.signup,
                      queryParameters: {'redirect': redirectTarget},
                    ),
                    child: const Text('Skapa konto'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
