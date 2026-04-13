import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/core/routing/app_routes.dart';
import 'package:aveli/features/auth/application/user_access_provider.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/paywall/application/checkout_flow.dart';
import 'package:aveli/features/paywall/data/checkout_api.dart';
import 'package:aveli/shared/utils/money.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';

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
        courseIsIntro: course?.isIntroCourse,
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

class _PaywallBody extends ConsumerStatefulWidget {
  const _PaywallBody({
    required this.courseId,
    this.courseTitle,
    this.coursePrice,
    this.courseIsIntro,
    this.courseSlug,
    required this.isAuthenticated,
  });

  final String courseId;
  final String? courseTitle;
  final int? coursePrice;
  final bool? courseIsIntro;
  final String? courseSlug;
  final bool isAuthenticated;

  @override
  ConsumerState<_PaywallBody> createState() => _PaywallBodyState();
}

class _PaywallBodyState extends ConsumerState<_PaywallBody> {
  bool _startingCheckout = false;

  Future<void> _startCourseCheckout() async {
    if (_startingCheckout) return;
    final slug = widget.courseSlug;
    if (slug == null || slug.isEmpty) return;
    final router = GoRouter.of(context);
    final returnPath = _currentLocation(context);
    setState(() => _startingCheckout = true);
    try {
      final api = ref.read(checkoutApiProvider);
      final launch = await api.createCourseCheckout(slug: slug);
      ref.read(checkoutContextProvider.notifier).state = CheckoutContext(
        type: CheckoutItemType.course,
        courseSlug: slug,
        courseTitle: widget.courseTitle,
        returnPath: returnPath,
      );
      ref
          .read(checkoutRedirectStateProvider.notifier)
          .state = CheckoutRedirectState(
        status: CheckoutRedirectStatus.processing,
        sessionId: launch.sessionId,
        orderId: launch.orderId,
      );
      if (!mounted) return;
      router.pushNamed(AppRoute.checkout, extra: launch.url);
    } catch (error, stackTrace) {
      if (!mounted) return;
      final failure = AppFailure.from(error, stackTrace);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) {
        setState(() => _startingCheckout = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceLabel =
        widget.coursePrice != null && widget.courseIsIntro != true
        ? formatCoursePriceFromOre(
            amountOre: widget.coursePrice!,
            debugContext: widget.courseSlug == null
                ? 'PaywallPrompt'
                : 'slug=${widget.courseSlug}',
          )
        : null;
    final title = widget.courseTitle ?? 'Kursen är låst';

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
                    style: theme.textTheme.bodyMedium?.copyWith(
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
                        onPressed:
                            widget.isAuthenticated &&
                                widget.courseSlug != null &&
                                !_startingCheckout
                            ? _startCourseCheckout
                            : null,
                        child: _startingCheckout
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Köp kursen'),
                      ),
                    ),
                  ],
                ),
                if (!widget.isAuthenticated) ...[
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
                ] else if (widget.courseSlug != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            context.goNamed(
                              AppRoute.course,
                              pathParameters: {'slug': widget.courseSlug!},
                            );
                          },
                          child: const Text('Öppna kursöversikten'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Efter betalningen uppdaterar appen din session. Åtkomst låses upp först när köpet har bekräftats.',
                  style: theme.textTheme.bodySmall,
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
