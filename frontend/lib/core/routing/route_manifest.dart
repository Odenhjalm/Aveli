import 'package:aveli/core/routing/app_routes.dart';

import 'route_access.dart';
import 'route_paths.dart';

class RouteManifestEntry {
  const RouteManifestEntry({
    required this.name,
    required this.path,
    required this.access,
    this.redirectAuthed = false,
  });

  final String name;
  final String path;
  final RouteAccessLevel access;
  final bool redirectAuthed;

  bool get hasDynamicSegment => path.contains(':');
}

const List<RouteManifestEntry> routeManifest = [
  RouteManifestEntry(
    name: AppRoute.landingRoot,
    path: RoutePath.landingRoot,
    access: RouteAccessLevel.public,
    redirectAuthed: false,
  ),
  RouteManifestEntry(
    name: AppRoute.boot,
    path: RoutePath.boot,
    access: RouteAccessLevel.public,
    redirectAuthed: false,
  ),
  RouteManifestEntry(
    name: AppRoute.landing,
    path: RoutePath.landing,
    access: RouteAccessLevel.public,
    redirectAuthed: false,
  ),
  RouteManifestEntry(
    name: AppRoute.login,
    path: RoutePath.login,
    access: RouteAccessLevel.public,
    redirectAuthed: true,
  ),
  RouteManifestEntry(
    name: AppRoute.signup,
    path: RoutePath.signup,
    access: RouteAccessLevel.public,
    redirectAuthed: true,
  ),
  RouteManifestEntry(
    name: AppRoute.forgotPassword,
    path: RoutePath.forgotPassword,
    access: RouteAccessLevel.public,
  ),
  RouteManifestEntry(
    name: AppRoute.newPassword,
    path: RoutePath.newPassword,
    access: RouteAccessLevel.public,
  ),
  RouteManifestEntry(
    name: AppRoute.courseIntro,
    path: RoutePath.courseIntro,
    access: RouteAccessLevel.public,
  ),
  RouteManifestEntry(
    name: AppRoute.courseIntroRedirect,
    path: RoutePath.courseIntroRedirect,
    access: RouteAccessLevel.public,
  ),
  RouteManifestEntry(
    name: AppRoute.courseCatalog,
    path: RoutePath.courseCatalog,
    access: RouteAccessLevel.public,
  ),
  RouteManifestEntry(
    name: AppRoute.courseQuiz,
    path: RoutePath.courseQuiz,
    access: RouteAccessLevel.public,
  ),
  RouteManifestEntry(
    name: AppRoute.course,
    path: RoutePath.course,
    access: RouteAccessLevel.public,
  ),
  RouteManifestEntry(
    name: AppRoute.lesson,
    path: RoutePath.lesson,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.serviceDetail,
    path: RoutePath.serviceDetail,
    access: RouteAccessLevel.public,
  ),
  RouteManifestEntry(
    name: AppRoute.profileView,
    path: RoutePath.profileView,
    access: RouteAccessLevel.public,
  ),
  RouteManifestEntry(
    name: AppRoute.teacherProfile,
    path: RoutePath.teacherProfile,
    access: RouteAccessLevel.public,
  ),
  RouteManifestEntry(
    name: AppRoute.privacy,
    path: RoutePath.privacy,
    access: RouteAccessLevel.public,
  ),
  RouteManifestEntry(
    name: AppRoute.terms,
    path: RoutePath.terms,
    access: RouteAccessLevel.public,
  ),
  RouteManifestEntry(
    name: AppRoute.claim,
    path: RoutePath.claim,
    access: RouteAccessLevel.public,
  ),
  RouteManifestEntry(
    name: AppRoute.home,
    path: RoutePath.home,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.sfuDemo,
    path: RoutePath.sfuDemo,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.messages,
    path: RoutePath.messages,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.directMessage,
    path: RoutePath.directMessage,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.profile,
    path: RoutePath.profile,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.profileSubscription,
    path: RoutePath.profileSubscription,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.profileSubscriptionPortal,
    path: RoutePath.profileSubscriptionPortal,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.checkout,
    path: RoutePath.checkout,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.tarot,
    path: RoutePath.tarot,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.subscribe,
    path: RoutePath.subscribe,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.booking,
    path: RoutePath.booking,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.orders,
    path: RoutePath.orders,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.settings,
    path: RoutePath.settings,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.community,
    path: RoutePath.community,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.admin,
    path: RoutePath.admin,
    access: RouteAccessLevel.admin,
  ),
  RouteManifestEntry(
    name: AppRoute.adminSettings,
    path: RoutePath.adminSettings,
    access: RouteAccessLevel.admin,
  ),
  RouteManifestEntry(
    name: AppRoute.studio,
    path: RoutePath.studio,
    access: RouteAccessLevel.teacher,
  ),
  RouteManifestEntry(
    name: AppRoute.teacherHome,
    path: RoutePath.teacherHome,
    access: RouteAccessLevel.teacher,
  ),
  RouteManifestEntry(
    name: AppRoute.teacherBundles,
    path: RoutePath.teacherBundles,
    access: RouteAccessLevel.teacher,
  ),
  RouteManifestEntry(
    name: AppRoute.teacherEditor,
    path: RoutePath.teacherEditor,
    access: RouteAccessLevel.teacher,
  ),
  RouteManifestEntry(
    name: AppRoute.studioProfile,
    path: RoutePath.studioProfile,
    access: RouteAccessLevel.teacher,
  ),
  RouteManifestEntry(
    name: AppRoute.seminarStudio,
    path: RoutePath.seminarStudio,
    access: RouteAccessLevel.teacher,
  ),
  RouteManifestEntry(
    name: AppRoute.seminarDetail,
    path: RoutePath.seminarDetail,
    access: RouteAccessLevel.teacher,
  ),
  RouteManifestEntry(
    name: AppRoute.seminarPreJoin,
    path: RoutePath.seminarPreJoin,
    access: RouteAccessLevel.teacher,
  ),
  RouteManifestEntry(
    name: AppRoute.seminarBroadcast,
    path: RoutePath.seminarBroadcast,
    access: RouteAccessLevel.teacher,
  ),
  RouteManifestEntry(
    name: AppRoute.seminarDiscover,
    path: RoutePath.seminarDiscover,
    access: RouteAccessLevel.authenticated,
  ),
  RouteManifestEntry(
    name: AppRoute.seminarJoin,
    path: RoutePath.seminarJoin,
    access: RouteAccessLevel.authenticated,
  ),
];
