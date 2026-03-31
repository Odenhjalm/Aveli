import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/core/routing/route_extras.dart';
import 'package:aveli/gate.dart';
import 'package:aveli/shared/widgets/app_scaffold.dart';
import 'package:aveli/shared/widgets/course_video.dart';
import 'package:aveli/shared/widgets/top_nav_action_buttons.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/shared/widgets/glass_card.dart';

class CourseIntroPage extends ConsumerWidget {
  const CourseIntroPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = GoRouterState.of(context);
    final extra = state.extra;
    final qp = state.uri.queryParameters;
    final args = extra is CourseIntroRouteArgs ? extra : null;
    final courseId = args?.courseId ?? qp['id'] ?? '';
    final title = args?.title ?? qp['title'] ?? 'Introduktionskurs';

    return AppScaffold(
      title: title,
      maxContentWidth: 900,
      showHomeAction: false,
      actions: const [TopNavActionButtons()],
      body: SafeArea(
        top: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GlassCard(
              padding: const EdgeInsets.all(24),
              opacity: 0.18,
              borderRadius: BorderRadius.circular(28),
              borderColor: Colors.white.withValues(alpha: 0.18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    courseId.isEmpty
                        ? 'Detta är en introduktionskurs.'
                        : 'Detta är introduktionen för kursen med ID: $courseId.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  _IntroVideoPreview(courseId: courseId),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GradientButton.icon(
                      onPressed: () {
                        gate.allow();
                        context.goNamed(AppRoute.home);
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Gå vidare till Home'),
                    ),
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

class _IntroVideoPreview extends StatelessWidget {
  const _IntroVideoPreview({required this.courseId});

  final String courseId;

  @override
  Widget build(BuildContext context) {
    if (courseId.isEmpty) {
      return const CourseVideoSkeleton(
        message: 'Ingen kurs vald. Välj en kurs för att se introduktionen.',
      );
    }
    return const CourseVideoSkeleton(
      message:
          'Introduktionsmedia publiceras via lektionsmedia. Öppna kursen för att fortsätta.',
    );
  }
}
