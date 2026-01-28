import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Landing/Home UI must not use Colors.black directly', () {
    final packageRoot = Directory.current;
    final targets = <Directory>[
      Directory('${packageRoot.path}/lib/features/landing'),
      Directory('${packageRoot.path}/lib/features/home'),
    ];

    final violations = <String>[];
    for (final dir in targets) {
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        if (content.contains('Colors.black')) {
          final relative = entity.path.replaceFirst('${packageRoot.path}/', '');
          violations.add(relative);
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Theme contract: Landing/Home must not use `Colors.black*` directly. '
          'Use ThemeData text styles + semantic wrappers, and limit black text '
          'to CourseDescriptionText on light cards.',
    );
  });
}

