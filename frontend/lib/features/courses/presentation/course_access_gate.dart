import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/payments/presentation/paywall_prompt.dart';

class CourseAccessGate extends ConsumerWidget {
  const CourseAccessGate({
    super.key,
    required this.courseId,
    required this.child,
    this.loading,
  });

  final String courseId;
  final Widget child;
  final Widget? loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(hasCourseAccessProvider(courseId));
    return access.when(
      data: (hasAccess) {
        if (hasAccess) {
          return child;
        }
        return PaywallPrompt(courseId: courseId);
      },
      loading: () =>
          loading ?? const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => PaywallPrompt(courseId: courseId),
    );
  }
}
