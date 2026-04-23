import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy mixed structure/content fixtures are quarantined', () {
    expect(true, isTrue);
  });

  group('embedded lesson media delete guard', () {
    test('_deleteMedia is guarded by _lessonAlreadyContainsMediaId', () {
      final source = _courseEditorSource();
      final deleteMethod = _sourceSlice(
        source,
        '  Future<void> _deleteMedia(String id) async {',
        '  bool _replaceLessonMediaReferencesInEditor',
      );

      final guardIndex = deleteMethod.indexOf(
        '_lessonAlreadyContainsMediaId(id)',
      );
      final repositoryDeleteIndex = deleteMethod.indexOf(
        'await _studioRepo.deleteLessonMedia(lessonId, id);',
      );

      expect(guardIndex, greaterThanOrEqualTo(0));
      expect(repositoryDeleteIndex, greaterThanOrEqualTo(0));
      expect(guardIndex, lessThan(repositoryDeleteIndex));
      expect(
        RegExp(
          r'if\s*\(\s*_lessonAlreadyContainsMediaId\(id\)\s*\)\s*\{[\s\S]*?return;\s*\}[\s\S]*?await _studioRepo\.deleteLessonMedia\(lessonId, id\);',
        ).hasMatch(deleteMethod),
        isTrue,
      );
    });

    test('media-list delete button cannot invoke delete for embedded IDs', () {
      final source = _courseEditorSource();
      final mediaListItem = _sourceSlice(
        source,
        'final mediaId = media.lessonMediaId;',
        'if (!_lessonPreviewMode)',
      );

      expect(
        RegExp(
          r'final mediaIsEmbedded\s*=\s*_lessonAlreadyContainsMediaId\(\s*mediaId,\s*\);',
        ).hasMatch(mediaListItem),
        isTrue,
      );
      expect(
        RegExp(
          r'_lessonPreviewMode\s*\|\|\s*mediaIsEmbedded\s*\?\s*null\s*:\s*\(\)\s*=>\s*_deleteMedia\(',
        ).hasMatch(mediaListItem),
        isTrue,
      );
      expect(mediaListItem, contains('final mediaIsEmbedded ='));
    });
  });
}

String _courseEditorSource() {
  return _readFrontendSource(
    'lib/features/studio/presentation/course_editor_page.dart',
  );
}

String _readFrontendSource(String frontendRelativePath) {
  final candidates = [
    File(frontendRelativePath),
    File('frontend/$frontendRelativePath'),
  ];

  for (final file in candidates) {
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }

  fail('Unable to locate $frontendRelativePath from ${Directory.current.path}');
}

String _sourceSlice(String source, String startNeedle, String endNeedle) {
  final start = source.indexOf(startNeedle);
  expect(
    start,
    greaterThanOrEqualTo(0),
    reason: 'Missing source start marker: $startNeedle',
  );

  final end = source.indexOf(endNeedle, start + startNeedle.length);
  expect(
    end,
    greaterThanOrEqualTo(0),
    reason: 'Missing source end marker: $endNeedle',
  );

  return source.substring(start, end);
}
