import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Presentation must not instantiate Scaffold/AppBar', () {
    final packageRoot = Directory.current;
    final featuresRoot = Directory('${packageRoot.path}/lib/features');
    if (!featuresRoot.existsSync()) {
      return;
    }

    final violations = <String>[];
    final scaffoldPattern = RegExp(r'\bScaffold\s*\(');
    final appBarPattern = RegExp(r'\bAppBar\s*\(');

    for (final entity in featuresRoot.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (!entity.path.contains(
        '${Platform.pathSeparator}presentation${Platform.pathSeparator}',
      )) {
        continue;
      }

      final content = entity.readAsStringSync();
      if (scaffoldPattern.hasMatch(content) ||
          appBarPattern.hasMatch(content)) {
        final relative = entity.path.replaceFirst('${packageRoot.path}/', '');
        violations.add(relative);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'App contract: UI pages must not create their own Scaffold/AppBar. '
          'All pages MUST render via AppScaffold, which provides the mandatory '
          'BrandHeader and enforces a single themed UI tree.',
    );
  });
}
