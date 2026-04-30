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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.14),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
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
                const SizedBox(width: 8),
                for (final course in courses) ...[
                  OngoingCourseCard(
                    key: ValueKey('home-ongoing-course-${course.courseId}'),
                    course: course,
                    onPressed: _ctaPressed(course),
                  ),
                  if (course != courses.last) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
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
