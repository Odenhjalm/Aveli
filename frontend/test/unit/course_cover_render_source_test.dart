import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/features/studio/presentation/course_editor_page.dart';

void main() {
  group('selectCourseCoverRenderSource', () {
    test('prioritizes resolved url over local preview bytes', () {
      expect(
        selectCourseCoverRenderSource(
          resolvedUrl: 'https://cdn.test/course-cover.jpg',
          localPreviewBytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
        'resolved_url',
      );
    });

    test('uses local preview bytes when resolved url is absent', () {
      expect(
        selectCourseCoverRenderSource(
          resolvedUrl: null,
          localPreviewBytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
        'local_bytes',
      );
    });

    test('falls back to placeholder when no preview source exists', () {
      expect(
        selectCourseCoverRenderSource(
          resolvedUrl: '   ',
          localPreviewBytes: Uint8List(0),
        ),
        'placeholder',
      );
    });
  });
}
