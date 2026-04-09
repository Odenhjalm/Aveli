import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/auth/application/user_access_provider.dart';
import 'package:aveli/data/models/certificate.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/data/repositories/profile_repository.dart';
import 'package:aveli/features/courses/application/course_providers.dart'
    as courses_front;
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/effects_backdrop_filter.dart';
import 'package:aveli/shared/widgets/glass_card.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/shared/widgets/app_avatar.dart';
import 'package:aveli/shared/widgets/top_nav_action_buttons.dart';
import 'package:aveli/features/community/presentation/widgets/profile_logout_section.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/utils/app_images.dart';

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
      await ref.read(authControllerProvider.notifier).loadSession();
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

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final access = ref.watch(userAccessProvider);
    final profile = authState.profile;
    final certificatesAsync = ref.watch(myCertificatesProvider);
    final coursesAsync = ref.watch(courses_front.myCoursesProvider);
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
        image: AppImages.background,
        alignment: Alignment.center,
        topOpacity: 0.38,
        sideVignette: 0.15,
        overlayColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.black.withValues(alpha: 0.3)
            : const Color(0xFFFFE2B8).withValues(alpha: 0.22),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 880;
          const columnGap = SizedBox(height: 16);
          const rowGap = SizedBox(width: 16);

          Widget buildRow(Widget left, Widget right) {
            if (!isWide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [left, columnGap, right],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                rowGap,
                Expanded(child: right),
              ],
            );
          }

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
                  editing: _editing,
                  saving: _saving,
                  onStartEditing: _startEditing,
                  onCancelEditing: () => _cancelEditing(profile),
                  onSaveProfile: () => _saveProfile(profile),
                ),
                columnGap,
                buildRow(
                  _BioSection(
                    profile: profile,
                    editing: _editing,
                    saving: _saving,
                    controller: _bioCtrl,
                  ),
                  _CertificatesSection(certificatesAsync: certificatesAsync),
                ),
                columnGap,
                buildRow(
                  _ServicesSection(
                    isTeacher: access.isTeacher,
                    onOpenStudio: () => context.goNamed(AppRoute.studio),
                  ),
                  _CoursesSection(
                    coursesAsync: coursesAsync,
                    onSeeAll: () => context.goNamed(AppRoute.courseIntro),
                  ),
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
    required this.editing,
    required this.saving,
    required this.onStartEditing,
    required this.onCancelEditing,
    required this.onSaveProfile,
  });

  final Profile profile;
  final bool isTeacher;
  final bool isAdmin;
  final TextEditingController displayNameController;
  final bool editing;
  final bool saving;
  final VoidCallback onStartEditing;
  final VoidCallback onCancelEditing;
  final VoidCallback onSaveProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = profile.displayName?.trim().isNotEmpty == true
        ? profile.displayName!
        : profile.email;
    final initials = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part.characters.first.toUpperCase())
        .take(2)
        .join();
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
              _ProfileAvatar(
                profile: profile,
                initials: initials,
                displayName: displayName,
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

class _ProfileAvatar extends ConsumerWidget {
  const _ProfileAvatar({
    required this.profile,
    required this.initials,
    required this.displayName,
  });

  final Profile profile;
  final String initials;
  final String displayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final photoPath = profile.photoUrl?.trim();
    final resolvedUrl = photoPath == null || photoPath.isEmpty
        ? null
        : Uri.parse(
            ref.read(appConfigProvider).apiBaseUrl,
          ).resolve(photoPath).toString();
    final avatarLabel = initials.isEmpty
        ? displayName.characters.first.toUpperCase()
        : initials;

    return Tooltip(
      message: resolvedUrl == null
          ? 'Profilbild saknas'
          : 'Profilbild visas som skrivskyddad projektion',
      child: Stack(
        alignment: Alignment.center,
        children: [
          resolvedUrl == null
              ? CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  child: Text(
                    avatarLabel,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : AppAvatar(url: resolvedUrl, size: 64),
          Positioned(
            bottom: -2,
            right: -2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.visibility_outlined,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
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

class _CoursesSection extends StatelessWidget {
  const _CoursesSection({required this.coursesAsync, required this.onSeeAll});

  final AsyncValue<List<CourseSummary>> coursesAsync;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _GlassSection(
      title: 'Pågående kurser',
      actions: [
        TextButton(onPressed: onSeeAll, child: const Text('Utforska fler')),
      ],
      child: coursesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text(
          error is AppFailure ? error.message : error.toString(),
          style: theme.textTheme.bodyMedium,
        ),
        data: (courses) {
          if (courses.isEmpty) {
            return Text(
              'Du är inte inskriven i någon kurs ännu.',
              style: theme.textTheme.bodyMedium,
            );
          }
          return Column(
            children: courses
                .take(5)
                .map((course) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: InkWell(
                      onTap: () {
                        final slug = course.slug;
                        // TODO: Keep course detail routing strictly slug-based.
                        // Falling back to UUID course.id breaks /course/:slug navigation.
                        if (slug.isEmpty) {
                          debugPrint(
                            '[NAV_BLOCKED] Course missing slug: ${course.id}',
                          );
                          return;
                        }
                        context.goNamed(
                          AppRoute.course,
                          pathParameters: {'slug': slug},
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              course.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (course.isIntroCourse) ...[
                              const SizedBox(height: 10),
                              const _ProfileChip(
                                icon: Icons.auto_awesome,
                                label: 'Introduktion',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          );
        },
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
      title: 'Byt lÃ¶senord',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Byt losenord via glomt-losenord-flodet. Det ar den kanoniska authytan som fortfarande stods i frontend.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          GradientButton.icon(
            onPressed: () => context.goNamed(AppRoute.forgotPassword),
            icon: const Icon(Icons.lock_reset_rounded),
            label: const Text('Ga till glomt losenord'),
          ),
        ],
      ),
    );
  }
}

class _CertificatesSection extends StatelessWidget {
  const _CertificatesSection({required this.certificatesAsync});

  final AsyncValue<List<Certificate>> certificatesAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _GlassSection(
      title: 'Mina certifikat',
      child: certificatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text(
          error is AppFailure ? error.message : error.toString(),
          style: theme.textTheme.bodyMedium,
        ),
        data: (certificates) {
          if (certificates.isEmpty) {
            return Text(
              'Inga certifikat är registrerade ännu. Lägg till dina diplom och intyg via Studio.',
              style: theme.textTheme.bodyMedium,
            );
          }
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: certificates
                .map((c) => _CertificateBadge(certificate: c))
                .toList(growable: false),
          );
        },
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

class _CertificateBadge extends StatelessWidget {
  const _CertificateBadge({required this.certificate});

  final Certificate certificate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = certificate.status;
    final color = switch (status) {
      CertificateStatus.verified => Colors.greenAccent,
      CertificateStatus.rejected => Colors.redAccent,
      CertificateStatus.pending => Colors.orangeAccent,
      CertificateStatus.unknown => Colors.lightBlueAccent,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        color: color.withValues(alpha: 0.12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            certificate.isVerified
                ? Icons.workspace_premium_rounded
                : certificate.isPending
                ? Icons.hourglass_top_rounded
                : certificate.isRejected
                ? Icons.highlight_off_rounded
                : Icons.description_outlined,
            color: color,
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                certificate.title.trim().isEmpty
                    ? 'Certifikat'
                    : certificate.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _statusLabel(certificate),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _statusLabel(Certificate certificate) {
    switch (certificate.status) {
      case CertificateStatus.pending:
        return 'Under granskning';
      case CertificateStatus.verified:
        return 'Verifierat';
      case CertificateStatus.rejected:
        return 'Avslaget';
      case CertificateStatus.unknown:
        return certificate.statusRaw;
    }
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
