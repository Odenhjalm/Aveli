import 'package:flutter/material.dart';

import 'package:aveli/features/home/data/home_entry_view_repository.dart';
import 'package:aveli/features/home/widgets/ongoing_course_card.dart';

class OngoingCoursesStrip extends StatelessWidget {
  const OngoingCoursesStrip({
    super.key,
    required this.courses,
    required this.onOpenLesson,
  });

  final List<HomeEntryOngoingCourse> courses;
  final ValueChanged<String> onOpenLesson;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleCourses = courses.take(2).toList(growable: false);

    return Semantics(
      label: 'Mina kurser',
      child: Container(
        constraints: const BoxConstraints(minHeight: 40, maxHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.16),
          ),
        ),
        child: visibleCourses.length == 1
            ? Center(
                child: OngoingCourseCard(
                  key: ValueKey(
                    'home-ongoing-course-${visibleCourses.first.courseId}',
                  ),
                  course: visibleCourses.first,
                  onPressed: _ctaPressed(visibleCourses.first),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final course in visibleCourses) ...[
                    OngoingCourseCard(
                      key: ValueKey('home-ongoing-course-${course.courseId}'),
                      course: course,
                      onPressed: _ctaPressed(course),
                    ),
                    if (course != visibleCourses.last)
                      Container(
                        width: 1,
                        height: 20,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        color: colorScheme.outline.withValues(alpha: 0.18),
                      ),
                  ],
                ],
              ),
      ),
    );
  }

  VoidCallback? _ctaPressed(HomeEntryOngoingCourse course) {
    final action = course.cta.action;
    if (!course.cta.enabled || action == null) {
      return null;
    }
    return () => onOpenLesson(action.lessonId);
  }
}
