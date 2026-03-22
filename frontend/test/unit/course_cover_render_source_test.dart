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

  group('shouldClearStudioLocalCoverOverride', () {
    test('returns true for control-plane covers with a media id', () {
      expect(
        shouldClearStudioLocalCoverOverride(<String, dynamic>{
          'cover': <String, dynamic>{
            'media_id': 'media-1',
            'source': 'control_plane',
          },
        }),
        isTrue,
      );
    });

    test('returns false when the backend cover is not control-plane', () {
      expect(
        shouldClearStudioLocalCoverOverride(<String, dynamic>{
          'cover': <String, dynamic>{
            'media_id': 'media-1',
            'source': 'editor_override',
          },
        }),
        isFalse,
      );
    });

    test('returns false when the backend cover has no media id', () {
      expect(
        shouldClearStudioLocalCoverOverride(<String, dynamic>{
          'cover': <String, dynamic>{'source': 'control_plane'},
        }),
        isFalse,
      );
    });
  });

  group('selectStudioCourseCoverUrl', () {
    test('prefers the backend control-plane cover over a local override', () {
      expect(
        selectStudioCourseCoverUrl(
          backendResolvedUrl: 'https://cdn.test/control-plane.jpg',
          backendSource: 'control_plane',
          localOverrideResolvedUrl: 'https://cdn.test/local-override.jpg',
        ),
        'https://cdn.test/control-plane.jpg',
      );
    });

    test(
      'falls back to the local override before placeholder/backend gaps',
      () {
        expect(
          selectStudioCourseCoverUrl(
            backendResolvedUrl: null,
            backendSource: 'placeholder',
            localOverrideResolvedUrl: 'https://cdn.test/local-override.jpg',
          ),
          'https://cdn.test/local-override.jpg',
        );
      },
    );

    test('uses the backend url when no local override exists', () {
      expect(
        selectStudioCourseCoverUrl(
          backendResolvedUrl: 'https://cdn.test/legacy.jpg',
          backendSource: 'legacy_cover_url',
          localOverrideResolvedUrl: null,
        ),
        'https://cdn.test/legacy.jpg',
      );
    });
  });
}
