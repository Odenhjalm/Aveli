import 'package:aveli/features/courses/data/courses_repository.dart';

class CourseJourneyFamily {
  CourseJourneyFamily({
    required this.courseGroupId,
    required Iterable<CourseSummary> courses,
  }) : courses = List.unmodifiable(courses);

  final String courseGroupId;
  final List<CourseSummary> courses;

  CourseSummary? get introCourse {
    final introCourses = courses.where((course) => course.isIntroCourse);
    if (introCourses.isEmpty) {
      return null;
    }
    final orderedIntroCourses = [...introCourses]..sort(_compareFamilyCourses);
    return orderedIntroCourses.first;
  }

  List<CourseSummary> get progressionCourses =>
      List.unmodifiable(courses.where((course) => !course.isIntroCourse));
}

List<CourseJourneyFamily> buildCourseJourneyFamilies(
  Iterable<CourseSummary> courses,
) {
  final grouped = <String, List<CourseSummary>>{};
  final groupOrder = <String>[];

  for (final course in courses) {
    final courseGroupId = course.courseGroupId.trim();
    if (courseGroupId.isEmpty) {
      continue;
    }
    final familyCourses = grouped.putIfAbsent(courseGroupId, () {
      groupOrder.add(courseGroupId);
      return <CourseSummary>[];
    });
    familyCourses.add(course);
  }

  final families = <CourseJourneyFamily>[];
  for (final courseGroupId in groupOrder) {
    final familyCourses = [...grouped[courseGroupId]!]
      ..sort(_compareFamilyCourses);
    if (!_hasCanonicalFamilyOrder(familyCourses)) {
      continue;
    }
    families.add(
      CourseJourneyFamily(courseGroupId: courseGroupId, courses: familyCourses),
    );
  }

  return List.unmodifiable(families);
}

int _compareFamilyCourses(CourseSummary left, CourseSummary right) {
  final positionCompare = left.groupPosition.compareTo(right.groupPosition);
  if (positionCompare != 0) {
    return positionCompare;
  }
  return left.id.compareTo(right.id);
}

bool _hasCanonicalFamilyOrder(List<CourseSummary> courses) {
  if (courses.isEmpty) {
    return false;
  }
  for (var index = 0; index < courses.length; index++) {
    if (courses[index].groupPosition != index) {
      return false;
    }
  }
  return true;
}
