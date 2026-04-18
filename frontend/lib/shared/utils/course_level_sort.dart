int levelOrder(String level) {
  final normalized = level.trim().toLowerCase().replaceAll(
    RegExp(r'[\s_-]+'),
    '',
  );

  switch (normalized) {
    case 'intro':
    case 'introduction':
      return 0;
    case 'steg1':
    case 'position1':
      return 1;
    case 'steg2':
    case 'position2':
      return 2;
    case 'steg3':
    case 'position3':
      return 3;
    default:
      return 999;
  }
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
  for (final key in const ['level', 'group_position']) {
    final value = course[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  return '';
}

String _normalizedValue(Object? value) {
  return value?.toString().trim().toLowerCase() ?? '';
}
