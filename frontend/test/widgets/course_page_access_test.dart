import 'package:aveli/core/env/app_config.dart';
import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';
import 'package:aveli/features/courses/presentation/course_page.dart';
import 'package:aveli/features/paywall/application/pricing_providers.dart';
import 'package:aveli/features/paywall/data/course_pricing_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'teacher access keeps paid lessons unlocked without intro quota UI',
    (tester) async {
      final detail = CourseDetailData(
        course: const CourseSummary(
          id: 'course-1',
          slug: 'paid-course',
          title: 'Paid Course',
          description: 'Teacher owned',
          isFreeIntro: false,
          isPublished: false,
          priceCents: 12900,
        ),
        modules: const [
          CourseModule(
            id: 'course-1',
            courseId: 'course-1',
            title: 'Lektioner',
            position: 0,
          ),
        ],
        lessonsByModule: const {
          'course-1': [
            LessonSummary(
              id: 'lesson-1',
              title: 'Premium Lesson',
              position: 1,
              isIntro: false,
            ),
          ],
        },
        hasAccess: true,
        accessReason: 'teacher',
        isEnrolled: false,
        hasActiveSubscription: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(
                apiBaseUrl: 'http://localhost:8080',
                stripePublishableKey: 'pk_test',
                stripeMerchantDisplayName: 'Aveli Test',
                subscriptionsEnabled: true,
              ),
            ),
            courseDetailProvider.overrideWith((ref, slug) async => detail),
            coursePricingProvider.overrideWith(
              (ref, slug) async =>
                  CoursePricing(amountCents: 12900, currency: 'sek'),
            ),
          ],
          child: const MaterialApp(home: CoursePage(slug: 'paid-course')),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Läraråtkomst'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
      expect(find.textContaining('Använda introduktioner'), findsNothing);
    },
  );
}
