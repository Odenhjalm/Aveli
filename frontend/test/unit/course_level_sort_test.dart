import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/shared/utils/course_level_sort.dart';

void main() {
  test('levelOrder maps supported aliases and unknown levels last', () {
    expect(levelOrder('Intro'), 0);
    expect(levelOrder('Introduction'), 0);
    expect(levelOrder('step1'), 1);
    expect(levelOrder('Steg 1'), 1);
    expect(levelOrder('step-2'), 2);
    expect(levelOrder('steg_3'), 3);
    expect(levelOrder('advanced'), 999);
    expect(levelOrder(''), 999);
  });

  test('sortCourseMapsByLevelThenTitle is deterministic', () {
    final courses = <Map<String, dynamic>>[
      {'id': 'course-6', 'title': 'Zen', 'journey_step': 'step2'},
      {'id': 'course-2', 'title': 'alpha', 'journey_step': 'intro'},
      {'id': 'course-5', 'title': 'Breathwork', 'journey_step': 'step1'},
      {'id': 'course-3', 'title': 'Alpha', 'journey_step': 'step1'},
      {'id': 'course-4', 'title': 'Clarity', 'journey_step': 'step1'},
      {'id': 'course-1', 'title': 'Unknown'},
    ];

    final firstPass = courses
        .map((course) => Map<String, dynamic>.from(course))
        .toList(growable: false);
    final secondPass = courses
        .map((course) => Map<String, dynamic>.from(course))
        .toList(growable: false);

    sortCourseMapsByLevelThenTitle(firstPass);
    sortCourseMapsByLevelThenTitle(secondPass);

    expect(
      firstPass.map((course) => course['id']),
      orderedEquals(<String>[
        'course-2',
        'course-3',
        'course-5',
        'course-4',
        'course-6',
        'course-1',
      ]),
    );
    expect(
      secondPass.map((course) => course['id']),
      orderedEquals(firstPass.map((course) => course['id'])),
    );
  });
}
