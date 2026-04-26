import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/courses/application/course_providers.dart';
import 'package:aveli/features/courses/data/courses_repository.dart';

class _CoursesListView extends ConsumerWidget {
  const _CoursesListView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(coursesProvider);
    return coursesAsync.when(
      data: (courses) => ListView(
        children: [
          for (final course in courses) ListTile(title: Text(course.title)),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('Error: $error'),
    );
  }
}

void main() {
  testWidgets('renders provided course summaries', (tester) async {
    final fakeCourses = <CourseSummary>[
      _course(id: '1', title: 'Intro to Tarot'),
      _course(id: '2', title: 'Meditation 101'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coursesProvider.overrideWith((ref) => Future.value(fakeCourses)),
        ],
        child: const MaterialApp(home: Scaffold(body: _CoursesListView())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Intro to Tarot'), findsOneWidget);
    expect(find.text('Meditation 101'), findsOneWidget);
  });
}

CourseSummary _course({required String id, required String title}) {
  return CourseSummary(
    id: id,
    slug: id,
    title: title,
    description: 'Backend course description',
    teacher: const CourseTeacherData(
      userId: 'teacher-1',
      displayName: 'Aveli Teacher',
    ),
    groupPosition: 1,
    courseGroupId: 'group-1',
    coverMediaId: null,
    cover: null,
    priceCents: 9900,
    dripEnabled: false,
    dripIntervalDays: null,
    requiredEnrollmentSource: 'purchase',
    enrollable: false,
    purchasable: true,
  );
}
