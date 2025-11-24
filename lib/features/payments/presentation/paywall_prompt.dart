import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisdom/core/errors/app_failure.dart';
import 'package:wisdom/core/routing/app_routes.dart';
import 'package:wisdom/features/auth/application/user_access_provider.dart';
import 'package:wisdom/features/courses/application/course_providers.dart';
import 'package:wisdom/shared/widgets/gradient_button.dart';

class PaywallPrompt extends ConsumerWidget {
  const PaywallPrompt({super.key, required this.courseId});

  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(courseByIdProvider(courseId));
    final access = ref.watch(userAccessProvider);
    final isAuthenticated = access.isAuthenticated;

    return summary.when(
      data: (course) => _PaywallBody(
        courseId: courseId,
        courseTitle: course?.title,
        coursePrice: course?.priceCents,
        courseSlug: course?.slug,
        isAuthenticated: isAuthenticated,
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _PaywallBody(
        courseId: courseId,
        courseTitle: _friendlyTitle(error),
        isAuthenticated: isAuthenticated,
      ),
    );
  }

  String? _friendlyTitle(Object error) {
    if (error is AppFailure && error.message.isNotEmpty) {
      return error.message;
    }
    return null;
  }
}

class _PaywallBody extends StatelessWidget {
  const _PaywallBody({
    required this.courseId,
    this.courseTitle,
    this.coursePrice,
    this.courseSlug,
    required this.isAuthenticated,
  });

  final String courseId;
  final String? courseTitle;
  final int? coursePrice;
  final String? courseSlug;
  final bool isAuthenticated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceLabel = coursePrice != null
        ? '${(coursePrice! / 100).toStringAsFixed(0)} kr'
        : null;
    final title = courseTitle ?? 'Kursen är låst';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Den här delen av kursen kräver full åtkomst. '
                  'Köp kursen eller logga in för att fortsätta.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (priceLabel != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Pris: $priceLabel',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: GradientButton(
                        onPressed: courseSlug == null
                            ? null
                            : () {
                                final slug = courseSlug!;
                                context.goNamed(
                                  AppRoute.course,
                                  pathParameters: {'slug': slug},
                                );
                              },
                        child: const Text('Öppna kursöversikten'),
                      ),
                    ),
                  ],
                ),
                if (!isAuthenticated) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            final location = _currentLocation(context);
                            context.goNamed(
                              AppRoute.login,
                              queryParameters: {'redirect': location},
                            );
                          },
                          child: const Text('Logga in'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Har du redan köpt kursen? Försök uppdatera sidan efter betalning '
                  'eller kontakta supporten om åtkomsten inte låses upp.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

String _currentLocation(BuildContext context) {
  try {
    return GoRouterState.of(context).uri.toString();
  } catch (_) {
    return '/';
  }
}
