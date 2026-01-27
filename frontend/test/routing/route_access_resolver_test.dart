import 'package:flutter_test/flutter_test.dart';

import 'package:aveli/core/routing/route_access.dart';
import 'package:aveli/core/routing/route_access_resolver.dart';

void main() {
  group('resolveRouteAccessLevel', () {
    test('matches static public routes', () {
      expect(resolveRouteAccessLevel('/'), RouteAccessLevel.public);
      expect(resolveRouteAccessLevel('/landing'), RouteAccessLevel.public);
      expect(resolveRouteAccessLevel('/courses/catalog'), RouteAccessLevel.public);
      expect(resolveRouteAccessLevel('/privacy'), RouteAccessLevel.public);
      expect(resolveRouteAccessLevel('/terms'), RouteAccessLevel.public);
    });

    test('matches dynamic public routes', () {
      expect(resolveRouteAccessLevel('/course/some-slug'), RouteAccessLevel.public);
      expect(
        resolveRouteAccessLevel('/teacher/profile/user-1'),
        RouteAccessLevel.public,
      );
      expect(
        resolveRouteAccessLevel('/profile/view/user-1'),
        RouteAccessLevel.public,
      );
      expect(resolveRouteAccessLevel('/service/svc-1'), RouteAccessLevel.public);
    });

    test('matches authenticated routes', () {
      expect(resolveRouteAccessLevel('/home'), RouteAccessLevel.authenticated);
      expect(resolveRouteAccessLevel('/lesson/lesson-1'), RouteAccessLevel.authenticated);
      expect(resolveRouteAccessLevel('/messages'), RouteAccessLevel.authenticated);
      expect(resolveRouteAccessLevel('/profile'), RouteAccessLevel.authenticated);
    });

    test('defaults unknown routes to authenticated', () {
      expect(resolveRouteAccessLevel('/unknown'), RouteAccessLevel.authenticated);
    });
  });
}

