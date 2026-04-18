import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/shared/utils/course_level_sort.dart';

void main() {
  test('levelOrder maps canonical group positions and unknown levels last', () {
    expect(levelOrder('0'), 0);
    expect(levelOrder('1'), 1);
    expect(levelOrder('2'), 2);
    expect(levelOrder('3'), 3);
    expect(levelOrder('advanced'), 999);
    expect(levelOrder(''), 999);
  });

  test(
    'sortCourseMapsByLevelThenTitle uses group_position deterministically',
    () {
      final courses = <Map<String, dynamic>>[
        {'id': 'course-6', 'title': 'Zen', 'group_position': 2},
        {'id': 'course-2', 'title': 'alpha', 'group_position': 0},
        {'id': 'course-5', 'title': 'Breathwork', 'group_position': 1},
        {'id': 'course-3', 'title': 'Alpha', 'group_position': 1},
        {'id': 'course-4', 'title': 'Clarity', 'group_position': 1},
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
    },
  );
}
