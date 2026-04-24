import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ICE-018 frontend intro selection stays backend-authored', () {
    final runtimeSources = _readFrontendRuntimeSources();
    final repositorySource = _readFrontendSource(
      'lib/features/courses/data/courses_repository.dart',
    );
    final coursePageSource = _readFrontendSource(
      'lib/features/courses/presentation/course_page.dart',
    );

    expect(runtimeSources, isNot(contains('groupPosition == 0')));
    expect(runtimeSources, isNot(contains('enrollable && !purchasable')));
    expect(runtimeSources, isNot(contains('firstFreeIntroCourseProvider')));
    expect(runtimeSources, isNot(contains('courseProgressProvider')));
    expect(runtimeSources, isNot(contains('ProgressRepository')));
    expect(repositorySource, contains('fetchIntroSelectionState'));
    expect(repositorySource, contains('/courses/intro-selection'));
    expect(
      coursePageSource,
      isNot(contains('courseState?.enrollable == true')),
    );
    expect(
      coursePageSource,
      isNot(contains('courseState?.enrollable == true || course.enrollable')),
    );
    expect(
      _findFrontendFile('lib/features/courses/data/progress_repository.dart'),
      isNull,
    );
  });
}

String _readFrontendRuntimeSources() {
  final resolvedLibPath = _findFrontendPath('lib');
  expect(
    resolvedLibPath,
    isNotNull,
    reason: 'Frontend runtime source root not found for ICE-018 contract test.',
  );
  final libDirectory = Directory(resolvedLibPath!);
  final buffer = StringBuffer();

  for (final entity in libDirectory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    buffer.writeln(entity.readAsStringSync());
  }

  return buffer.toString();
}

String _readFrontendSource(String frontendRelativePath) {
  final resolved = _findFrontendPath(frontendRelativePath);
  expect(
    resolved,
    isNotNull,
    reason: 'Source file not found in ICE-018 surface: $frontendRelativePath',
  );
  return File(resolved!).readAsStringSync();
}

String? _findFrontendFile(String frontendRelativePath) {
  final candidates = <File>[
    File(frontendRelativePath),
    File('frontend/$frontendRelativePath'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return file.path;
    }
  }
  return null;
}

String? _findFrontendPath(String frontendRelativePath) {
  final fileMatch = _findFrontendFile(frontendRelativePath);
  if (fileMatch != null) {
    return fileMatch;
  }

  final directoryCandidates = <Directory>[
    Directory(frontendRelativePath),
    Directory('frontend/$frontendRelativePath'),
  ];
  for (final directory in directoryCandidates) {
    if (directory.existsSync()) {
      return directory.path;
    }
  }
  return null;
}
