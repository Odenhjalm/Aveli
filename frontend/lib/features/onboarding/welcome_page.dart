import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/data/models/profile.dart';
import 'package:aveli/data/repositories/profile_repository.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/shared/theme/ui_consts.dart';
import 'package:aveli/shared/utils/snack.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key});

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _bioCtrl;
  bool _isSubmitting = false;
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

  void _hydrateControllers(Profile? profile) {
    if (profile == null || _hydratedProfileId == profile.id) return;
    _hydratedProfileId = profile.id;
    _displayNameCtrl.text = profile.displayName ?? '';
    _bioCtrl.text = profile.bio ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final profile = authState.profile;
    _hydrateControllers(profile);
    final name = profile?.displayName?.trim();

    return AppScaffold(
      title: 'Välkommen',
      showHomeAction: false,
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: p16,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name != null && name.isNotEmpty
                            ? 'Välkommen, $name'
                            : 'Välkommen till Aveli',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      gap16,
                      Text(
                        'Fyll i din profilprojektion först. Onboarding slutförs bara via backendens kanoniska onboarding-endpoint, och appåtkomst avgörs efteråt av entry-state.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      gap24,
                      _ProfileImageProjection(profile: profile),
                      gap16,
                      TextField(
                        controller: _displayNameCtrl,
                        enabled: !_isSubmitting,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Visningsnamn',
                          hintText: 'Namnet som visas i profilen',
                        ),
                      ),
                      gap16,
                      TextField(
                        controller: _bioCtrl,
                        enabled: !_isSubmitting,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Kort bio',
                          hintText: 'Berätta kort om dig själv',
                        ),
                      ),
                      gap16,
                      const _IntroCourseOffer(),
                      gap24,
                      GradientButton(
                        onPressed: _isSubmitting ? null : _completeWelcome,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Fortsätt'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _completeWelcome() async {
    final bio = _bioCtrl.text.trim();
    if (bio.isEmpty) {
      showSnack(context, 'Skriv en kort bio innan du fortsätter.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(profileRepositoryProvider);
      await repo.updateMe(
        displayName: _displayNameCtrl.text.trim().isEmpty
            ? null
            : _displayNameCtrl.text.trim(),
        bio: bio,
      );
      await ref.read(authControllerProvider.notifier).completeWelcome();
      if (!mounted || !context.mounted) return;
      showSnack(context, 'Onboarding uppdaterad.');
    } catch (error, stackTrace) {
      if (!mounted) return;
      final failure = AppFailure.from(error, stackTrace);
      showSnack(
        context,
        'Kunde inte slutföra välkomststeget: ${failure.message}',
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

class _ProfileImageProjection extends StatelessWidget {
  const _ProfileImageProjection({required this.profile});

  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = _avatarImage(profile);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: image,
              child: image == null ? Text(_avatarLabel(profile)) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Profilbilden visas som backendägd profilprojektion. Den ger ingen appåtkomst och slutför inte onboarding.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  ImageProvider<Object>? _avatarImage(Profile? profile) {
    final photoUrl = profile?.photoUrl?.trim();
    if (photoUrl == null || photoUrl.isEmpty) return null;
    return NetworkImage(photoUrl);
  }

  String _avatarLabel(Profile? profile) {
    final source = profile?.displayName?.trim().isNotEmpty == true
        ? profile!.displayName!
        : profile?.email ?? 'A';
    final parts = source
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return 'A';
    return parts
        .map((part) => part.characters.first.toUpperCase())
        .take(2)
        .join();
  }
}

class _IntroCourseOffer extends ConsumerWidget {
  const _IntroCourseOffer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCourse = ref.watch(firstFreeIntroCourseProvider);
    return asyncCourse.when(
      loading: () => const _IntroOfferShell(
        title: 'Introduktionskurs',
        body:
            'Första månaden är en provperiod. Du erbjuds en introduktionskurs, och lektionerna droppas veckovis.',
      ),
      error: (_, _) => const _IntroOfferShell(
        title: 'Introduktionskurs',
        body:
            'Första månaden är en provperiod. Introduktionskursen kan väljas senare och blockerar inte appåtkomst.',
      ),
      data: (course) => _IntroOfferShell(
        title: course?.title ?? 'Introduktionskurs',
        body:
            'Första månaden är en provperiod. Du erbjuds en introduktionskurs, och lektionerna droppas veckovis. Valet är inte en app-entry-gate.',
        course: course,
      ),
    );
  }
}

class _IntroOfferShell extends StatelessWidget {
  const _IntroOfferShell({
    required this.title,
    required this.body,
    this.course,
  });

  final String title;
  final String body;
  final CourseSummary? course;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final course = this.course;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodySmall),
            if (course != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => context.goNamed(
                    AppRoute.courseIntro,
                    queryParameters: {'id': course.id, 'title': course.title},
                  ),
                  child: const Text('Visa introduktionskurs'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
