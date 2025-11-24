import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisdom/core/routing/app_routes.dart';
import 'package:wisdom/core/routing/not_found_page.dart';
import 'package:wisdom/core/routing/route_access.dart';
import 'package:wisdom/core/routing/route_manifest.dart';
import 'package:wisdom/core/routing/route_paths.dart';
import 'package:wisdom/core/routing/route_session.dart';
import 'package:wisdom/core/routing/route_extras.dart';
import 'package:wisdom/features/auth/presentation/forgot_password_page.dart';
import 'package:wisdom/features/auth/presentation/login_page.dart';
import 'package:wisdom/features/auth/presentation/new_password_page.dart';
import 'package:wisdom/features/auth/presentation/settings_page.dart';
import 'package:wisdom/features/auth/presentation/signup_page.dart';
import 'package:wisdom/features/community/presentation/admin_page.dart';
import 'package:wisdom/features/community/presentation/admin_settings_page.dart';
import 'package:wisdom/features/community/presentation/community_page.dart';
import 'package:wisdom/features/home/presentation/home_dashboard_page.dart';
import 'package:wisdom/features/home/presentation/livekit_demo_page.dart';
import 'package:wisdom/features/community/presentation/profile_page.dart'
    as community_profile;
import 'package:wisdom/features/community/presentation/profile_view_page.dart';
import 'package:wisdom/features/community/presentation/service_detail_page.dart';
import 'package:wisdom/features/community/presentation/tarot_page.dart';
import 'package:wisdom/features/community/presentation/teacher_profile_page.dart';
import 'package:wisdom/features/profile/presentation/my_subscription_page.dart';
import 'package:wisdom/features/courses/presentation/course_intro_page.dart';
import 'package:wisdom/features/courses/presentation/course_intro_redirect_page.dart';
import 'package:wisdom/features/courses/presentation/course_catalog_page.dart';
import 'package:wisdom/features/courses/presentation/course_page.dart';
import 'package:wisdom/features/courses/presentation/lesson_page.dart';
import 'package:wisdom/features/courses/presentation/quiz_take_page.dart';
import 'package:wisdom/features/landing/presentation/landing_page.dart';
import 'package:wisdom/features/landing/presentation/legal/privacy_page.dart';
import 'package:wisdom/features/landing/presentation/legal/terms_page.dart';
import 'package:wisdom/features/messages/presentation/chat_page.dart';
import 'package:wisdom/features/messages/presentation/messages_page.dart';
import 'package:wisdom/features/payments/presentation/booking_page.dart';
import 'package:wisdom/features/payments/presentation/claim_purchase_page.dart';
import 'package:wisdom/features/payments/presentation/order_history_page.dart';
import 'package:wisdom/features/payments/presentation/subscribe_screen.dart';
import 'package:wisdom/features/paywall/presentation/checkout_result_page.dart';
import 'package:wisdom/features/paywall/presentation/checkout_webview_page.dart';
import 'package:wisdom/features/paywall/presentation/subscription_webview_page.dart';
import 'package:wisdom/features/studio/presentation/course_editor_page.dart';
import 'package:wisdom/features/studio/presentation/profile_media_page.dart';
import 'package:wisdom/features/studio/presentation/studio_page.dart';
import 'package:wisdom/features/studio/presentation/teacher_home_page.dart';
import 'package:wisdom/features/teacher/presentation/course_bundle_page.dart';
import 'package:wisdom/features/seminars/presentation/seminar_studio_page.dart';
import 'package:wisdom/features/seminars/presentation/seminar_detail_page.dart';
import 'package:wisdom/features/seminars/presentation/seminar_prejoin_page.dart';
import 'package:wisdom/features/seminars/presentation/seminar_route_args.dart';
import 'package:wisdom/features/seminars/presentation/seminar_broadcast_page.dart';
import 'package:wisdom/features/seminars/presentation/seminar_discover_page.dart';
import 'package:wisdom/features/seminars/presentation/seminar_join_page.dart';

class AppRouterNotifier extends ChangeNotifier {
  AppRouterNotifier(this.ref) {
    _sessionSub = ref.listen<RouteSessionSnapshot>(
      routeSessionSnapshotProvider,
      (previous, next) => notifyListeners(),
    );
  }

  final Ref ref;
  late final ProviderSubscription<RouteSessionSnapshot> _sessionSub;

  RouteSessionSnapshot get session => ref.read(routeSessionSnapshotProvider);

  String? handleRedirect(GoRouterState state) {
    final session = ref.read(routeSessionSnapshotProvider);
    final meta = _resolveRouteMeta(state);
    final isAuthed = session.isAuthenticated;

    if (!isAuthed) {
      if (meta.level == RouteAccessLevel.public) {
        return null;
      }
      if (state.matchedLocation == RoutePath.login) {
        return null;
      }
      final redirectTarget = state.uri.toString();
      return state.namedLocation(
        AppRoute.login,
        queryParameters: {'redirect': redirectTarget},
      );
    }

    if (meta.redirectAuthed) {
      return state.namedLocation(AppRoute.home);
    }

    if (meta.level == RouteAccessLevel.admin && !session.isAdmin) {
      return state.namedLocation(AppRoute.home);
    }

    if (meta.level == RouteAccessLevel.teacher &&
        !session.isTeacher &&
        !session.isAdmin) {
      return state.namedLocation(AppRoute.home);
    }

    return null;
  }

  @override
  void dispose() {
    _sessionSub.close();
    super.dispose();
  }
}

const RouteAccessMeta _defaultPrivateMeta = RouteAccessMeta(
  level: RouteAccessLevel.authenticated,
);

RouteAccessMeta _resolveRouteMeta(GoRouterState state) {
  final routeName = state.name;
  if (routeName != null) {
    final meta = _routeAccessMeta[routeName];
    if (meta != null) return meta;
  }
  final pathMeta = _staticPathAccessMeta[state.uri.path];
  return pathMeta ?? _defaultPrivateMeta;
}

final Map<String, RouteAccessMeta> _routeAccessMeta = {
  for (final entry in routeManifest)
    entry.name: RouteAccessMeta(
      level: entry.access,
      redirectAuthed: entry.redirectAuthed,
    ),
};

final Map<String, RouteAccessMeta> _staticPathAccessMeta = {
  for (final entry in routeManifest.where((entry) => !entry.hasDynamicSegment))
    entry.path: RouteAccessMeta(
      level: entry.access,
      redirectAuthed: entry.redirectAuthed,
    ),
};

final appRouterNotifierProvider = Provider<AppRouterNotifier>((ref) {
  final notifier = AppRouterNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(appRouterNotifierProvider);
  final initialSession = ref.read(routeSessionSnapshotProvider);
  final initialLocation = initialSession.isAuthenticated
      ? RoutePath.home
      : RoutePath.landingRoot;
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: notifier,
    redirect: (context, state) => notifier.handleRedirect(state),
    errorBuilder: (context, state) => const NotFoundPage(),
    routes: [
      GoRoute(
        path: RoutePath.login,
        name: AppRoute.login,
        builder: (context, state) =>
            LoginPage(redirectPath: state.uri.queryParameters['redirect']),
      ),
      GoRoute(
        path: RoutePath.signup,
        name: AppRoute.signup,
        builder: (context, state) => const SignupPage(),
      ),
      GoRoute(
        path: RoutePath.forgotPassword,
        name: AppRoute.forgotPassword,
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: RoutePath.newPassword,
        name: AppRoute.newPassword,
        builder: (context, state) => const NewPasswordPage(),
      ),
      GoRoute(
        path: RoutePath.landingRoot,
        name: AppRoute.landingRoot,
        builder: (context, state) => const LandingPage(),
      ),
      GoRoute(
        path: RoutePath.landing,
        name: AppRoute.landing,
        builder: (context, state) => const LandingPage(),
      ),
      GoRoute(
        path: RoutePath.home,
        name: AppRoute.home,
        builder: (context, state) => const HomeDashboardPage(),
      ),
      GoRoute(
        path: RoutePath.sfuDemo,
        name: AppRoute.sfuDemo,
        builder: (context, state) => const LiveKitDemoPage(),
      ),
      GoRoute(
        path: RoutePath.courseIntro,
        name: AppRoute.courseIntro,
        builder: (context, state) => const CourseIntroPage(),
      ),
      GoRoute(
        path: RoutePath.courseCatalog,
        name: AppRoute.courseCatalog,
        builder: (context, state) => const CourseCatalogPage(),
      ),
      GoRoute(
        path: RoutePath.courseQuiz,
        name: AppRoute.courseQuiz,
        builder: (context, state) => const QuizTakePage(),
      ),
      GoRoute(
        path: RoutePath.course,
        name: AppRoute.course,
        builder: (context, state) =>
            CoursePage(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: RoutePath.lesson,
        name: AppRoute.lesson,
        builder: (context, state) =>
            LessonPage(lessonId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePath.courseIntroRedirect,
        name: AppRoute.courseIntroRedirect,
        builder: (context, state) => const CourseIntroRedirectPage(),
      ),
      GoRoute(
        path: RoutePath.messages,
        name: AppRoute.messages,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! MessagesRouteArgs) {
            return const NotFoundPage();
          }
          return MessagesPage(kind: extra.kind, id: extra.id);
        },
      ),
      GoRoute(
        path: RoutePath.directMessage,
        name: AppRoute.directMessage,
        builder: (context, state) => const ChatPage(),
      ),
      GoRoute(
        path: RoutePath.profile,
        name: AppRoute.profile,
        builder: (context, state) => const community_profile.ProfilePage(),
      ),
      GoRoute(
        path: RoutePath.profileSubscription,
        name: AppRoute.profileSubscription,
        builder: (context, state) => const MySubscriptionPage(),
      ),
      GoRoute(
        path: RoutePath.profileSubscriptionPortal,
        name: AppRoute.profileSubscriptionPortal,
      builder: (context, state) {
          final url = state.extra;
          if (url is! String || url.isEmpty) {
            return const NotFoundPage();
          }
          return SubscriptionWebViewPage(url: url);
        },
      ),
      GoRoute(
        path: RoutePath.checkout,
        name: AppRoute.checkout,
        builder: (context, state) {
          final url = state.extra;
          if (url is! String || url.isEmpty) {
            return const NotFoundPage();
          }
          return CheckoutWebViewPage(url: url);
        },
      ),
      GoRoute(
        path: RoutePath.checkoutSuccess,
        name: AppRoute.checkoutSuccess,
        builder: (context, state) => const CheckoutResultPage(success: true),
      ),
      GoRoute(
        path: RoutePath.checkoutCancel,
        name: AppRoute.checkoutCancel,
        builder: (context, state) => const CheckoutResultPage(success: false),
      ),
      GoRoute(
        path: RoutePath.profileView,
        name: AppRoute.profileView,
        builder: (context, state) =>
            ProfileViewPage(userId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePath.teacherProfile,
        name: AppRoute.teacherProfile,
        builder: (context, state) =>
            TeacherProfilePage(userId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePath.serviceDetail,
        name: AppRoute.serviceDetail,
        builder: (context, state) =>
            ServiceDetailPage(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePath.tarot,
        name: AppRoute.tarot,
        builder: (context, state) => const TarotPage(),
      ),
      GoRoute(
        path: RoutePath.admin,
        name: AppRoute.admin,
        builder: (context, state) => const AdminPage(),
      ),
      GoRoute(
        path: RoutePath.adminSettings,
        name: AppRoute.adminSettings,
        builder: (context, state) => const AdminSettingsPage(),
      ),
      GoRoute(
        path: RoutePath.studio,
        name: AppRoute.studio,
        builder: (context, state) => const StudioPage(),
      ),
      GoRoute(
        path: RoutePath.teacherHome,
        name: AppRoute.teacherHome,
        builder: (context, state) => const TeacherHomeScreen(),
      ),
      GoRoute(
        path: RoutePath.teacherBundles,
        name: AppRoute.teacherBundles,
        builder: (context, state) => const CourseBundlePage(),
      ),
      GoRoute(
        path: RoutePath.teacherEditor,
        name: AppRoute.teacherEditor,
        builder: (context, state) {
          final extra = state.extra;
          final courseId = extra is CourseEditorRouteArgs
              ? extra.courseId
              : null;
          return CourseEditorScreen(courseId: courseId);
        },
      ),
      GoRoute(
        path: RoutePath.studioProfile,
        name: AppRoute.studioProfile,
        builder: (context, state) => const StudioProfilePage(),
      ),
      GoRoute(
        path: RoutePath.seminarStudio,
        name: AppRoute.seminarStudio,
        builder: (context, state) => const SeminarStudioPage(),
      ),
      GoRoute(
        path: RoutePath.seminarDetail,
        name: AppRoute.seminarDetail,
        builder: (context, state) =>
            SeminarDetailPage(seminarId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePath.seminarPreJoin,
        name: AppRoute.seminarPreJoin,
        builder: (context, state) {
          final args = state.extra;
          if (args is! SeminarPreJoinArgs) {
            return const NotFoundPage();
          }
          return SeminarPreJoinPage(args: args);
        },
      ),
      GoRoute(
        path: RoutePath.seminarBroadcast,
        name: AppRoute.seminarBroadcast,
        builder: (context, state) {
          final args = state.extra;
          if (args is! SeminarBroadcastArgs) {
            return const NotFoundPage();
          }
          return SeminarBroadcastPage(args: args);
        },
      ),
      GoRoute(
        path: RoutePath.subscribe,
        name: AppRoute.subscribe,
        builder: (context, state) => const SubscribeScreen(),
      ),
      GoRoute(
        path: RoutePath.booking,
        name: AppRoute.booking,
        builder: (context, state) => const BookingPage(),
      ),
      GoRoute(
        path: RoutePath.orders,
        name: AppRoute.orders,
        builder: (context, state) => const OrderHistoryPage(),
      ),
      GoRoute(
        path: RoutePath.claim,
        name: AppRoute.claim,
        builder: (context, state) =>
            ClaimPurchasePage(token: state.uri.queryParameters['token']),
      ),
      GoRoute(
        path: RoutePath.privacy,
        name: AppRoute.privacy,
        builder: (context, state) => const PrivacyPage(),
      ),
      GoRoute(
        path: RoutePath.terms,
        name: AppRoute.terms,
        builder: (context, state) => const TermsPage(),
      ),
      GoRoute(
        path: RoutePath.settings,
        name: AppRoute.settings,
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: RoutePath.seminarDiscover,
        name: AppRoute.seminarDiscover,
        builder: (context, state) => const SeminarDiscoverPage(),
      ),
      GoRoute(
        path: RoutePath.seminarJoin,
        name: AppRoute.seminarJoin,
        builder: (context, state) =>
            SeminarJoinPage(seminarId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePath.community,
        name: AppRoute.community,
        builder: (context, state) {
          final extra = state.extra;
          final initialTab = extra is CommunityRouteArgs
              ? extra.initialTab
              : null;
          return CommunityPage(initialTab: initialTab);
        },
      ),
    ],
  );
});
