import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/auth/auth_controller.dart';
import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/route_paths.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/onboarding/data/onboarding_repository.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

class SelectIntroCoursePage extends ConsumerStatefulWidget {
  const SelectIntroCoursePage({super.key});

  @override
  ConsumerState<SelectIntroCoursePage> createState() =>
      _SelectIntroCoursePageState();
}

class _SelectIntroCoursePageState extends ConsumerState<SelectIntroCoursePage> {
  String? _savingCourseId;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final onboarding = authState.onboarding;
    final coursesAsync = ref.watch(onboardingIntroCoursesProvider);
    final selectedId = onboarding?.selectedIntroCourseId;

    return AppScaffold(
      title: 'Välj introduktionskurs',
      showHomeAction: false,
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Välj din introduktionskurs',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Varje introduktionskurs innehåller fyra lektioner. '
                        'När du har valt kurs fortsätter du till välkomststeget.',
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
                      SizedBox(
                        height: 420,
                        child: coursesAsync.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, stackTrace) => Center(
                            child: Text(
                              AppFailure.from(error, stackTrace).message,
                            ),
                          ),
                          data: (courses) {
                            if (courses.isEmpty) {
                              return const Center(
                                child: Text(
                                  'Det finns inga publicerade introduktionskurser ännu.',
                                ),
                              );
                            }
                            return ListView.separated(
                              itemCount: courses.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final course = courses[index];
                                final isSelected = selectedId == course.id;
                                final isSaving = _savingCourseId == course.id;
                                return _IntroCourseCard(
                                  course: course,
                                  selected: isSelected,
                                  loading: isSaving,
                                  onSelect: () => _selectCourse(course.id),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Du får en ny lektion per vecka när onboarding är klar.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
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
    );
  }

  Future<void> _selectCourse(String courseId) async {
    if (_savingCourseId != null) return;
    setState(() {
      _savingCourseId = courseId;
      _errorMessage = null;
    });
    try {
      final repo = ref.read(onboardingRepositoryProvider);
      await repo.selectIntroCourse(courseId);
      await ref.read(authControllerProvider.notifier).refreshOnboarding();
      if (!mounted || !context.mounted) return;
      context.go(RoutePath.welcome);
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppFailure.from(error, stackTrace).message;
      });
    } finally {
      if (mounted) {
        setState(() => _savingCourseId = null);
      }
    }
  }
}

class _IntroCourseCard extends StatelessWidget {
  const _IntroCourseCard({
    required this.course,
    required this.selected,
    required this.loading,
    required this.onSelect,
  });

  final CourseSummary course;
  final bool selected;
  final bool loading;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).dividerColor,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  course.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (selected) const Chip(label: Text('Vald')),
            ],
          ),
          if ((course.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(course.description!.trim()),
          ],
          const SizedBox(height: 16),
          GradientButton(
            onPressed: loading ? null : onSelect,
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(selected ? 'Välj igen' : 'Välj kurs'),
          ),
        ],
      ),
    );
  }
}
