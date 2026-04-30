import 'package:flutter/material.dart';

import 'package:aveli/features/home/data/home_entry_view_repository.dart';

class OngoingCourseCard extends StatelessWidget {
  const OngoingCourseCard({
    super.key,
    required this.course,
    required this.onPressed,
  });

  final HomeEntryOngoingCourse course;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final coverUrl = course.coverMedia.resolvedUrl;

    return Semantics(
      button: onPressed != null,
      label: course.title,
      child: Material(
        color: colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 188,
            height: 58,
            child: Row(
              children: [
                if (coverUrl != null && coverUrl.isNotEmpty)
                  SizedBox(
                    width: 52,
                    height: 58,
                    child: Image.network(coverUrl, fit: BoxFit.cover),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        LinearProgressIndicator(
                          value: course.progress.percent,
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(999),
                          backgroundColor: colorScheme.outline.withValues(
                            alpha: 0.18,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          course.cta.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: onPressed == null
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
