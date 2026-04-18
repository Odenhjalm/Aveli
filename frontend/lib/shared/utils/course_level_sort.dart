int levelOrder(String groupPosition) {
  final position = int.tryParse(groupPosition.trim());
  if (position == null || position < 0) {
    return 999;
  }
  return position;
}

void sortCourseMapsByLevelThenTitle(List<Map<String, dynamic>> courses) {
  courses.sort(compareCourseMapsByLevelThenTitle);
}

int compareCourseMapsByLevelThenTitle(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
) {
  final levelCompare = levelOrder(
    _courseLevel(a),
  ).compareTo(levelOrder(_courseLevel(b)));
  if (levelCompare != 0) {
    return levelCompare;
  }

  final titleCompare = _normalizedValue(
    a['title'],
  ).compareTo(_normalizedValue(b['title']));
  if (titleCompare != 0) {
    return titleCompare;
  }

  final slugCompare = _normalizedValue(
    a['slug'],
  ).compareTo(_normalizedValue(b['slug']));
  if (slugCompare != 0) {
    return slugCompare;
  }

  return _normalizedValue(a['id']).compareTo(_normalizedValue(b['id']));
}

String _courseLevel(Map<String, dynamic> course) {
  final value = course['group_position']?.toString().trim();
  if (value != null && value.isNotEmpty) {
    return value;
  }

  return '';
}

String _normalizedValue(Object? value) {
  return value?.toString().trim().toLowerCase() ?? '';
}
