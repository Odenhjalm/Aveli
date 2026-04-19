import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('course cover frontend contract', () {
    test('rendering surfaces do not reference legacy authorities', () {
      for (final path in _courseCoverRenderingPaths) {
        final source = File(path).readAsStringSync();

        expect(
          source,
          isNot(contains('resolved_cover_url')),
          reason: '$path must not consume legacy resolved_cover_url',
        );
        expect(
          source,
          isNot(contains('resolvedCoverUrl')),
          reason: '$path must not consume legacy resolvedCoverUrl',
        );
        expect(
          source,
          isNot(contains('cover_url')),
          reason: '$path must not consume legacy cover_url',
        );
      }
    });

    test('active course cover paths do not construct storage URLs', () {
      for (final path in _activeCourseCoverConsumerPaths) {
        final source = File(path).readAsStringSync();

        expect(
          source,
          isNot(contains('media/derived')),
          reason: '$path must not construct storage object paths',
        );
        expect(
          source,
          isNot(contains('media/source')),
          reason: '$path must not construct storage object paths',
        );
        expect(
          source,
          isNot(contains('storage/v1')),
          reason: '$path must not construct Supabase storage URLs',
        );
      }
    });

    test('frontend parsers reject legacy cover authorities explicitly', () {
      for (final path in _courseCoverParserPaths) {
        final source = File(path).readAsStringSync();

        expect(source, contains('_legacyCourseCoverFields'));
        expect(source, contains('Invalid course cover field'));
      }
    });

    test('course surfaces read only the canonical cover resolved URL', () {
      expect(
        File(
          'lib/features/courses/presentation/course_catalog_page.dart',
        ).readAsStringSync(),
        contains('courseCoverResolvedUrl(course.cover)'),
      );
      expect(
        File(
          'lib/features/courses/presentation/course_page.dart',
        ).readAsStringSync(),
        contains('courseCoverResolvedUrl(detail.course.cover)'),
      );
      expect(
        File(
          'lib/shared/widgets/courses_showcase_section.dart',
        ).readAsStringSync(),
        contains('courseCoverResolvedUrl(course.cover)'),
      );
      expect(
        File('lib/shared/widgets/courses_grid.dart').readAsStringSync(),
        contains('courseCoverResolvedUrl(c.cover)'),
      );
    });

    test(
      'landing providers are inert instead of a separate cover authority',
      () {
        final source = File(
          'lib/features/landing/application/landing_providers.dart',
        ).readAsStringSync();

        expect(source, contains('_unsupportedLandingRuntime'));
        expect(source, contains('Landing edge is inert in mounted runtime'));
        expect(source, isNot(contains('/landing/popular-courses')));
        expect(source, isNot(contains('/landing/intro-courses')));
        expect(source, isNot(contains('ApiClient')));
      },
    );

    test('showcase maps course summaries without alternate cover fields', () {
      final source = File(
        'lib/shared/widgets/courses_showcase_section.dart',
      ).readAsStringSync();

      expect(source, contains('coverMediaId: course.coverMediaId'));
      expect(source, contains('cover: course.cover'));
      expect(source, isNot(contains('resolvedCoverUrl')));
    });
  });
}

const _activeCourseCoverConsumerPaths = <String>[
  'lib/features/courses/data/courses_repository.dart',
  'lib/features/courses/presentation/course_catalog_page.dart',
  'lib/features/courses/presentation/course_page.dart',
  'lib/features/landing/application/landing_providers.dart',
  'lib/shared/utils/course_cover_contract.dart',
  'lib/shared/widgets/courses_grid.dart',
  'lib/shared/widgets/courses_showcase_section.dart',
];

const _courseCoverParserPaths = <String>[
  'lib/features/courses/data/courses_repository.dart',
  'lib/features/landing/application/landing_providers.dart',
];

const _courseCoverRenderingPaths = <String>[
  'lib/features/courses/presentation/course_catalog_page.dart',
  'lib/features/courses/presentation/course_page.dart',
  'lib/shared/widgets/courses_grid.dart',
  'lib/shared/widgets/courses_showcase_section.dart',
];
