import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/core/guards/guard_context.dart';

void main() {
  group('GuardContextResolver', () {
    test('classifies public routes via prefix matching', () {
      expect(
        GuardContextResolver.fromLocation('/'),
        GuardContext.publicLanding,
      );
      expect(
        GuardContextResolver.fromLocation('/landing'),
        GuardContext.publicLanding,
      );
      expect(
        GuardContextResolver.fromLocation('/landing/'),
        GuardContext.publicLanding,
      );
      expect(
        GuardContextResolver.fromLocation('/landing/welcome'),
        GuardContext.publicLanding,
      );
      expect(
        GuardContextResolver.fromLocation('/privacy'),
        GuardContext.publicLanding,
      );
      expect(
        GuardContextResolver.fromLocation('/terms'),
        GuardContext.publicLanding,
      );
    });

    test('strips query params and fragments before matching', () {
      expect(
        GuardContextResolver.fromLocation('/landing?ref=netlify'),
        GuardContext.publicLanding,
      );
      expect(
        GuardContextResolver.fromLocation('/landing?ref=netlify#top'),
        GuardContext.publicLanding,
      );
    });

    test('supports hash-based routing by using fragment path', () {
      expect(
        GuardContextResolver.fromLocation('https://app.aveli.app/#/landing'),
        GuardContext.publicLanding,
      );
      expect(
        GuardContextResolver.fromLocation('/#/landing?ref=hash'),
        GuardContext.publicLanding,
      );
    });

    test('classifies app-core routes as appCore', () {
      expect(GuardContextResolver.fromLocation('/login'), GuardContext.appCore);
      expect(
        GuardContextResolver.fromLocation('/profile'),
        GuardContext.appCore,
      );
    });
  });
}
