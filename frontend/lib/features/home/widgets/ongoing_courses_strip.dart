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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Mina kurser',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface.withValues(alpha: 0.82),
              ),
            ),
            const SizedBox(width: 10),
            for (final course in courses) ...[
              OngoingCourseCard(
                key: ValueKey('home-ongoing-course-${course.courseId}'),
                course: course,
                onPressed: _ctaPressed(course),
              ),
              if (course != courses.last)
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
