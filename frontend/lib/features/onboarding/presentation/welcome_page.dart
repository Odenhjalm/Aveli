import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/onboarding/data/onboarding_repository.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key});

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  bool _submitting = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final onboarding = authState.onboarding;
    final selectedCourseId = onboarding?.selectedIntroCourseId;
    final selectedCourseAsync = selectedCourseId == null
        ? AsyncValue<CourseSummary?>.data(null)
        : ref.watch(courseByIdProvider(selectedCourseId));

    return AppScaffold(
      title: 'Välkommen',
      showHomeAction: false,
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Du är nästan klar',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Nu är din e-post verifierad, medlemskapet aktivt och '
                        'din profil sparad. Nästa steg är att bekräfta starten.',
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Du får en lektion per vecka, och din valda introduktionskurs innehåller fyra lektioner.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 20),
                      selectedCourseAsync.when(
                        loading: () => const CircularProgressIndicator(),
                        error: (error, stackTrace) =>
                            Text(AppFailure.from(error, stackTrace).message),
                        data: (course) => Text(
                          course == null
                              ? 'Ingen introduktionskurs vald ännu.'
                              : 'Vald introduktionskurs: ${course.title}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      GradientButton(
                        onPressed: _submitting ? null : _completeOnboarding,
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Starta i Aveli'),
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

  Future<void> _completeOnboarding() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final repo = ref.read(onboardingRepositoryProvider);
      await repo.complete();
      await ref.read(authControllerProvider.notifier).refreshOnboarding();
      if (!mounted || !context.mounted) return;
      context.go(RoutePath.home);
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppFailure.from(error, stackTrace).message;
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
