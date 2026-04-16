import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
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
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).profile;
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name != null && name.isNotEmpty
                                ? 'Välkommen till Aveli $name'
                                : 'Välkommen till Aveli',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          gap16,
                          Text(
                            'Nu vet du var du börjar. Introduktionskurser släpps en gång i månaden och varje lektion släpps en gång i veckan.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          gap16,
                          const _WelcomeRhythm(),
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
                                : const Text('Jag förstår hur Aveli fungerar'),
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

  Future<void> _completeWelcome() async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(authControllerProvider.notifier).completeWelcome();
      if (!mounted || !context.mounted) return;
      showSnack(context, 'Introduktionen uppdaterad.');
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

class _WelcomeRhythm extends StatelessWidget {
  const _WelcomeRhythm();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WelcomePoint(
          title: 'Introduktionskurs',
          body:
              'Du kan välja en introduktionskurs nu eller senare. Valet är frivilligt.',
        ),
        SizedBox(height: 8),
        _WelcomePoint(
          title: 'Månad och vecka',
          body:
              'Nya introduktionskurser släpps en gång i månaden. Varje lektion släpps en gång i veckan.',
        ),
        SizedBox(height: 8),
        _WelcomePoint(
          title: 'Hela utbildningen',
          body:
              'Du kan också välja ett paketerbjudande med steg ett, två och tre och få alla introduktionskurser släppta direkt.',
        ),
      ],
    );
  }
}

class _WelcomePoint extends StatelessWidget {
  const _WelcomePoint({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(body, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _IntroCourseOffer extends ConsumerWidget {
  const _IntroCourseOffer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCourse = ref.watch(firstFreeIntroCourseProvider);
    return asyncCourse.when(
      loading: () => const _IntroOfferShell(
        title: 'Valfri introduktionskurs',
        body:
            'Du kan välja en introduktionskurs, men det är inte ett krav för att fortsätta.',
      ),
      error: (_, _) => const _IntroOfferShell(
        title: 'Valfri introduktionskurs',
        body:
            'Introduktionskursen kan väljas senare och blockerar inte appåtkomst.',
      ),
      data: (course) => _IntroOfferShell(
        title: course?.title ?? 'Valfri introduktionskurs',
        body: 'Det här valet är frivilligt och påverkar inte appåtkomst.',
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
