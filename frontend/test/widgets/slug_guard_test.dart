import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/shared/utils/slug_validator.dart';

void main() {
  test('valid slug passes', () {
    expect(isValidSlug('my-course-slug'), isTrue);
  });

  test('UUID blocked', () {
    expect(isValidSlug('123e4567-e89b-12d3-a456-426614174000'), isFalse);
  });

  test('empty blocked', () {
    expect(isValidSlug(''), isFalse);
    expect(isValidSlug('   '), isFalse);
  });
}
